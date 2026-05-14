#!/usr/bin/env python3
"""
Question Quality Meter — 사용자 발화 품질 학습 + 다음 발화 모호도 예측.

학습 데이터:
- ~/.claude/projects/-*/*.jsonl 의 user 메시지
- 각 발화 직후 outcome 라벨링:
  • 정정 발생 (BAD) — 다음 5턴 내 사용자가 "아니/틀렸/수정해" 발화
  • 명확 완료 (GOOD) — 정정 없이 다음 작업 진행
  • 짧은 ack (NEUTRAL) — "ㅇㅇ", "yes" 등

발화 특성 추출:
- 길이 (너무 짧음/너무 긺)
- 모호도 키워드 ("좀", "그냥", "아무거나", "알아서", "적당히")
- 구체성 (파일경로/함수명/숫자/명사 비율)
- 명령형 vs 의문형
- 컨텍스트 부재 ("그것", "거기", "저번에")

출력:
- ~/.claude/cache/question-quality.{md,json}
- 모호도 점수표 + BAD/GOOD 패턴 예시
- 사용자 자기 발화 통계 ("당신 발화의 N% 가 5턴 내 정정 유발")
"""

import os
import re
import sys
import json
import argparse
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime

PROJECTS_DIR = Path.home() / ".claude/projects"
OUT_MD = Path.home() / ".claude/cache/question-quality.md"
OUT_JSON = Path.home() / ".claude/cache/question-quality.json"
RULES_OUT = Path.home() / ".claude/cache/question-quality-rules.json"

CORRECTION_RE = re.compile(
    r"(아니|틀렸|잘못|그게 아니|다시 해|다시해|수정해|wrong|incorrect|nope|fix that)"
)
AMBIGUOUS_RE = re.compile(
    r"\b(좀|그냥|아무거나|알아서|적당히|뭐|뭐든|어떻게든|대충|maybe|kinda|sort of|whatever)\b"
)
CONTEXT_DEIXIS_RE = re.compile(
    r"(그것|이것|저것|거기|저기|아까|저번에|그거|이거|that|this|it)"
)
COMMAND_RE = re.compile(r"(해|하라|해라|만들어|짜|수정해|fix|build|make|create|do|run)$|^[가-힣A-Za-z]+해$")
QUESTION_RE = re.compile(r"(\?|뭐야|뭐냐|왜|어떻게|어디|언제)")
CONCRETE_RE = re.compile(r"[/\\]|\.[a-z]+\b|[A-Z][a-zA-Z]{2,}|`[^`]+`|[0-9]+")


def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                t = item.get("type")
                if t == "text":
                    parts.append(item.get("text", ""))
        return "\n".join(parts)
    return ""


def is_synthetic_user(text):
    """skill paste / system-reminder / tool-result / 긴 paste 는 진짜 사용자 발화 아님."""
    if not text:
        return True
    if re.match(r"^(Base directory for this skill|<system-reminder|<command-name|---\nname:)", text, re.MULTILINE):
        return True
    if text.count("\n") > 8:
        return True
    if "<local-command-stdout>" in text:
        return True
    return False


def features(text):
    text = (text or "").strip()
    n_chars = len(text)
    n_words = len(text.split())
    return {
        "chars": n_chars,
        "words": n_words,
        "ambiguous_hits": len(AMBIGUOUS_RE.findall(text)),
        "deixis_hits": len(CONTEXT_DEIXIS_RE.findall(text)),
        "concrete_hits": len(CONCRETE_RE.findall(text)),
        "is_command": bool(COMMAND_RE.search(text)),
        "is_question": bool(QUESTION_RE.search(text)),
        "is_short": n_chars < 10,
        "is_very_short": n_chars < 5,
    }


def label_outcome(msgs, idx, lookahead=5):
    """idx 의 user 발화에 대한 outcome 라벨링."""
    next_user_idx = None
    for j in range(idx + 1, min(idx + 1 + lookahead * 2, len(msgs))):
        if msgs[j]["role"] == "user" and not is_synthetic_user(msgs[j]["text"]):
            next_user_idx = j
            break
    if next_user_idx is None:
        return "UNKNOWN"
    next_text = msgs[next_user_idx]["text"] or ""
    if CORRECTION_RE.search(next_text):
        return "BAD"  # 정정 발생
    if next_text.strip() in {"ㅇㅇ", "ok", "OK", "응", "yes", "good", "좋아", "고마워"}:
        return "GOOD"
    return "NEUTRAL"


def parse_session(jsonl_path):
    msgs = []
    try:
        for line in jsonl_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if not line.strip():
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") not in ("user", "assistant"):
                continue
            msg = d.get("message", {}) or {}
            msgs.append({
                "role": msg.get("role") or d.get("type"),
                "text": extract_text(msg.get("content", "")),
                "ts": d.get("timestamp") or "",
            })
    except Exception:
        return []
    return msgs


def aggregate(stats_list):
    """list of stat dicts → mean/sum."""
    if not stats_list:
        return {}
    keys = stats_list[0].keys()
    out = {}
    for k in keys:
        if isinstance(stats_list[0][k], (int, float, bool)):
            vals = [s.get(k, 0) for s in stats_list]
            out[k + "_mean"] = sum(vals) / len(vals) if vals else 0
            out[k + "_sum"] = sum(vals)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-sessions", type=int, default=200)
    ap.add_argument("--show", action="store_true")
    ap.add_argument("--lookahead", type=int, default=5)
    args = ap.parse_args()

    if not PROJECTS_DIR.exists():
        print("세션 디렉토리 없음", file=sys.stderr)
        sys.exit(1)

    all_jsonls = []
    for d in PROJECTS_DIR.iterdir():
        if d.is_dir():
            all_jsonls.extend(d.glob("*.jsonl"))
    all_jsonls = sorted(all_jsonls, key=lambda p: p.stat().st_mtime, reverse=True)[:args.max_sessions]
    print(f"분석 세션: {len(all_jsonls)}", file=sys.stderr)

    by_outcome = defaultdict(list)  # outcome -> list of feature dicts
    bad_examples = []
    good_examples = []

    total_user_msgs = 0
    real_user_msgs = 0

    for jp in all_jsonls:
        msgs = parse_session(jp)
        for i, m in enumerate(msgs):
            if m["role"] != "user":
                continue
            total_user_msgs += 1
            if is_synthetic_user(m["text"]):
                continue
            real_user_msgs += 1
            f = features(m["text"])
            outcome = label_outcome(msgs, i, lookahead=args.lookahead)
            by_outcome[outcome].append(f)
            if outcome == "BAD" and len(bad_examples) < 30:
                bad_examples.append({"text": m["text"][:200], "ts": m["ts"][:16]})
            elif outcome == "GOOD" and len(good_examples) < 10:
                good_examples.append({"text": m["text"][:150], "ts": m["ts"][:16]})

    summary = {}
    for outcome, fs in by_outcome.items():
        summary[outcome] = {
            "count": len(fs),
            **aggregate(fs),
        }

    bad = by_outcome.get("BAD", [])
    good = by_outcome.get("GOOD", [])
    neutral = by_outcome.get("NEUTRAL", [])
    total = len(bad) + len(good) + len(neutral)

    bad_rate = len(bad) / total if total else 0

    rules = {
        "very_short_bad_rate": 0,
        "ambiguous_bad_rate": 0,
        "deixis_bad_rate": 0,
        "no_concrete_bad_rate": 0,
    }
    if total:
        very_short_bad = sum(1 for f in bad if f["is_very_short"])
        very_short_total = sum(1 for f in bad + good + neutral if f["is_very_short"])
        rules["very_short_bad_rate"] = very_short_bad / very_short_total if very_short_total else 0

        amb_bad = sum(1 for f in bad if f["ambiguous_hits"] > 0)
        amb_total = sum(1 for f in bad + good + neutral if f["ambiguous_hits"] > 0)
        rules["ambiguous_bad_rate"] = amb_bad / amb_total if amb_total else 0

        deixis_bad = sum(1 for f in bad if f["deixis_hits"] > 0)
        deixis_total = sum(1 for f in bad + good + neutral if f["deixis_hits"] > 0)
        rules["deixis_bad_rate"] = deixis_bad / deixis_total if deixis_total else 0

        no_concrete_bad = sum(1 for f in bad if f["concrete_hits"] == 0)
        no_concrete_total = sum(1 for f in bad + good + neutral if f["concrete_hits"] == 0)
        rules["no_concrete_bad_rate"] = no_concrete_bad / no_concrete_total if no_concrete_total else 0

    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    lines.append("# Question Quality Meter")
    lines.append("")
    lines.append(f"분석: {len(all_jsonls)}세션, 총 user 메시지 {total_user_msgs}, 진짜 발화 {real_user_msgs}")
    lines.append("")
    lines.append("## Outcome 분포")
    lines.append("")
    lines.append("| Outcome | 횟수 | 비율 |")
    lines.append("|---|---|---|")
    for o in ("GOOD", "NEUTRAL", "BAD", "UNKNOWN"):
        c = summary.get(o, {}).get("count", 0)
        pct = c / real_user_msgs * 100 if real_user_msgs else 0
        lines.append(f"| {o} | {c} | {pct:.1f}% |")
    lines.append("")
    lines.append(f"**전체 정정 유발률 (BAD)**: {bad_rate * 100:.1f}%")
    lines.append("")

    lines.append("## 패턴별 정정 유발률 (높을수록 모호한 발화)")
    lines.append("")
    lines.append("| 패턴 | 정정률 | 의미 |")
    lines.append("|---|---|---|")
    lines.append(f"| 매우 짧은 발화 (<5자) | {rules['very_short_bad_rate']*100:.1f}% | '응', 'ㅇㅇ' 같은 짧은 ack가 다음 정정 유발하는지 |")
    lines.append(f"| 모호 키워드 포함 (좀/그냥/알아서) | {rules['ambiguous_bad_rate']*100:.1f}% | 명시 없이 위임 시 결과 |")
    lines.append(f"| 지시대명사 포함 (그것/거기/아까) | {rules['deixis_bad_rate']*100:.1f}% | 컨텍스트 의존 발화 |")
    lines.append(f"| 구체성 0 (파일경로/숫자 없음) | {rules['no_concrete_bad_rate']*100:.1f}% | 추상적 지시 |")
    lines.append("")

    lines.append("## 평균 발화 특성 비교 (BAD vs GOOD)")
    lines.append("")
    lines.append("| 특성 | BAD | GOOD | NEUTRAL |")
    lines.append("|---|---|---|---|")
    keys = [("chars_mean", "평균 글자 수"), ("words_mean", "평균 단어 수"),
            ("ambiguous_hits_mean", "모호 키워드"), ("deixis_hits_mean", "지시대명사"),
            ("concrete_hits_mean", "구체 토큰")]
    for k, label in keys:
        b = summary.get("BAD", {}).get(k, 0)
        g = summary.get("GOOD", {}).get(k, 0)
        n = summary.get("NEUTRAL", {}).get(k, 0)
        lines.append(f"| {label} | {b:.2f} | {g:.2f} | {n:.2f} |")
    lines.append("")

    lines.append("## BAD 발화 예시 (정정 유발한 발화 30개)")
    lines.append("")
    for ex in bad_examples[:20]:
        text = ex["text"].replace("\n", " ")
        lines.append(f"- **{ex['ts']}**: `{text}`")
    lines.append("")

    lines.append("## GOOD 발화 예시 (정정 없이 진행된 발화)")
    lines.append("")
    for ex in good_examples[:5]:
        text = ex["text"].replace("\n", " ")
        lines.append(f"- **{ex['ts']}**: `{text}`")
    lines.append("")

    lines.append("## 권고")
    lines.append("")
    lines.append(f"- 매우 짧은 발화: 정정률 {rules['very_short_bad_rate']*100:.0f}% — 5자 미만 발화 시 더 명확하게 쓸 것 권장")
    lines.append(f"- 모호 키워드: 정정률 {rules['ambiguous_bad_rate']*100:.0f}% — '좀/그냥/알아서' 사용 시 구체화")
    lines.append(f"- 지시대명사: 정정률 {rules['deixis_bad_rate']*100:.0f}% — '그거/거기' 대신 명시")
    lines.append("")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")
    OUT_JSON.write_text(json.dumps({
        "sessions": len(all_jsonls),
        "real_user_msgs": real_user_msgs,
        "bad_rate": bad_rate,
        "summary": summary,
        "rules": rules,
    }, indent=2, ensure_ascii=False), encoding="utf-8")
    RULES_OUT.write_text(json.dumps(rules, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\n리포트: {OUT_MD}", file=sys.stderr)
    print(f"  진짜 발화: {real_user_msgs}", file=sys.stderr)
    print(f"  정정률 (BAD): {bad_rate*100:.1f}%", file=sys.stderr)
    print(f"  Rules: {RULES_OUT}", file=sys.stderr)

    if args.show:
        print(OUT_MD.read_text())


if __name__ == "__main__":
    main()
