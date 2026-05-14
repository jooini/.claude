#!/usr/bin/env python3
"""
agent 출력 품질 측정 — 3차원:
1) 도메인 용어 매칭 — agent 출력에 자기 knowledge 용어 등장 빈도
2) 의사결정 패턴 — 근거/제약/트레이드오프/대안 키워드 등장
3) 출력 구조 — 단계 명시(Step), 코드블록, 표, 헤더 등

입력:
  ~/.claude/projects/*/*/subagents/agent-*.jsonl  (subagent 출력 텍스트)
  ~/.claude/agents/knowledge/{agent_type}/*.md    (도메인 용어집)
  ~/.claude/cache/md-live/agent-trace-*.jsonl     (시간/세션/turn_id 매칭)

출력:
  ~/.claude/cache/md-live/agent-quality.jsonl     (agent 호출 1건 = 1줄)

실행: python3 ~/.claude/scripts/agent-quality-analyze.py [--days N]
"""
import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROJECTS_DIR = Path.home() / ".claude" / "projects"
KNOWLEDGE_DIR = Path.home() / ".claude" / "agents" / "knowledge"
LIVE_DIR = Path.home() / ".claude" / "cache" / "md-live"
LIVE_DIR.mkdir(parents=True, exist_ok=True)

# 의사결정 패턴 — 다국어 키워드 (한국어/영어)
DECISION_PATTERNS = {
    "근거": [r"왜냐하면", r"이유는", r"근거", r"because", r"reason", r"why\s"],
    "제약": [r"제약", r"한계", r"불가능", r"안\s*돼", r"limitation", r"constraint", r"cannot"],
    "트레이드오프": [r"트레이드오프", r"대신", r"vs\s", r"vs\.|선택", r"trade.?off", r"versus"],
    "대안": [r"대안", r"옵션\s?[ABC]", r"방안\s?[ABC]", r"alternative", r"option\s?[ABC]"],
    "검증": [r"검증", r"테스트", r"확인", r"verify", r"verified", r"tested"],
}

# 출력 구조 패턴
STRUCTURE_PATTERNS = {
    "step": [r"^\s*Step\s+\d+", r"^\s*\d+단계", r"^\s*##\s+\d+\."],
    "header": [r"^#+\s+.+$"],
    "code": [r"```[a-zA-Z]*\n"],
    "list": [r"^\s*[-*+]\s+", r"^\s*\d+\.\s+"],
    "table": [r"^\s*\|.+\|.+\|"],
}


def extract_knowledge_terms(agent_type):
    """agent_type knowledge 디렉토리에서 도메인 시그널 용어 추출.

    핵심:
    - 헤더에서 번호/괄호 prefix 제거 ("1. CTE (Common Table Expressions)" → "cte" + "common table expressions")
    - 괄호 안 영어 약자 분리 (한국어 + 영어 둘 다 매칭 가능)
    - 흔한 단어 stoplist
    """
    terms = set()
    STOPLIST = {
        'type', 'types', 'test', 'tests', 'user', 'users', 'name', 'names',
        'value', 'values', 'data', 'list', 'item', 'items', 'page', 'pages',
        'time', 'date', 'file', 'files', 'code', 'option', 'options',
        'default', 'config', 'method', 'function', 'class', 'object',
        'state', 'event', 'events', 'error', 'errors', 'click',
        '아이콘', '버튼', '메뉴', '페이지', '리스트', '데이터', '코드',
        'compare', 'check', 'true', 'false', 'null', 'none',
        '소개', '개요', '정의', '예시', '결론', '요약', '참고', '비고',
        '안티패턴', '베스트', '예제', '샘플', '예외',
    }

    def clean_term(t):
        """헤더 raw → 정제된 용어들 (1개 이상 반환)."""
        out = []
        # 마크다운 기호 제거
        t = re.sub(r"[*`_~]", "", t)
        # 앞 번호 prefix 제거: "1.", "1)", "Step 1:", "1.1", "①" 등
        t = re.sub(r"^\s*(?:\d+(?:\.\d+)*[.)]\s*|step\s+\d+[:.]\s*|[①-⑩]\s*)", "", t, flags=re.IGNORECASE)
        # 괄호 안 영어/약자 추출 후 본문에서 분리
        # "CTE (Common Table Expressions)" → ["CTE", "Common Table Expressions"]
        # "외삽(extrapolation)" → ["외삽", "extrapolation"]
        paren_inner = re.findall(r"\(([^)]+)\)", t)
        t_no_paren = re.sub(r"\([^)]+\)", "", t).strip()
        # 본 텍스트
        if t_no_paren:
            out.append(t_no_paren)
        # 괄호 안 텍스트 (영어 약자/풀네임)
        for p in paren_inner:
            p = p.strip()
            if 2 <= len(p) <= 60:
                out.append(p)
        return out

    def is_noise(t):
        """노이즈 필터: 문장형/숫자/특수문자 비율 등."""
        if not t: return True
        # 따옴표 시작 = 문장 인용
        if t[0] in ('"', "'", '`', '“', '‘'): return True
        # 슬래시/콜론/콤마 등 구분자 다수 = 문장
        if t.count(',') >= 2 or t.count(':') >= 2: return True
        # ↔, →, =, * 등 기호 시작
        if re.match(r"^[-*+→←↔=]", t): return True
        # 숫자만 또는 숫자 비율 큼
        if re.match(r"^[\d.\-]+$", t): return True
        digit_ratio = sum(1 for c in t if c.isdigit()) / max(1, len(t))
        if digit_ratio > 0.4: return True
        # 단어 5개 초과 = 문장 가능성
        if len(t.split()) > 5: return True
        # path/url
        if t.count('/') >= 2: return True
        return False

    kdir = KNOWLEDGE_DIR / agent_type
    if not kdir.exists():
        return terms
    for md in kdir.rglob("*.md"):
        # _archive, _disabled 같은 underscore prefix 디렉토리 제외
        if any(part.startswith("_") for part in md.relative_to(kdir).parts):
            continue
        try:
            txt = md.read_text()
        except Exception:
            continue
        # 헤더만 (가장 강한 시그널) — 굵은글씨는 노이즈 너무 많아 제외
        for m in re.findall(r"^#+\s+(.+?)$", txt, re.MULTILINE):
            for cleaned in clean_term(m):
                t = cleaned.lower().strip()
                t = re.sub(r"\s+", " ", t)
                if 3 <= len(t) <= 50 and t not in STOPLIST and not is_noise(t):
                    terms.add(t)
        # 인라인 코드 — 식별자성만 (영어 + 하이픈/언더스코어, 4자 이상, 공백 없음)
        for m in re.findall(r"`([a-zA-Z][a-zA-Z0-9_\-]{3,30})`", txt):
            t = m.strip().lower()
            if t in STOPLIST: continue
            if ' ' in t: continue
            terms.add(t)
    return terms


def extract_subagent_text(jsonl_path):
    """subagent jsonl 에서 assistant text 합쳐서 반환."""
    chunks = []
    try:
        with jsonl_path.open() as f:
            for ln in f:
                try:
                    d = json.loads(ln)
                except Exception:
                    continue
                if d.get("type") != "assistant":
                    continue
                msg = d.get("message", {})
                for c in msg.get("content", []) if isinstance(msg.get("content"), list) else []:
                    if isinstance(c, dict) and c.get("type") == "text":
                        chunks.append(c.get("text", ""))
    except Exception as e:
        print(f"  ! parse error {jsonl_path.name}: {e}", file=sys.stderr)
    return "\n".join(chunks)


def find_user_trigger(subagent_jsonl, first_ts_utc):
    """subagent jsonl 의 부모 메인 transcript 에서, agent 호출 직전의 user prompt 찾기.
    경로: ~/.claude/projects/{proj}/{main_session_uuid}/subagents/agent-*.jsonl
    부모: ~/.claude/projects/{proj}/{main_session_uuid}.jsonl
    """
    try:
        main_session = subagent_jsonl.parent.parent.name  # session uuid
        proj_dir = subagent_jsonl.parent.parent.parent
        main_file = proj_dir / f"{main_session}.jsonl"
        if not main_file.exists():
            return ""
        # first_ts 직전의 user prompt 찾기
        last_user = ""
        for ln in main_file.read_text().splitlines():
            try:
                d = json.loads(ln)
            except Exception:
                continue
            ts_str = d.get("timestamp", "")
            if not ts_str:
                continue
            # ISO 비교 — first_ts_utc 보다 같거나 이전
            if ts_str.replace("Z", "") > first_ts_utc.replace("Z", ""):
                break
            if d.get("type") == "user" and "toolUseResult" not in d:
                msg = d.get("message", {})
                c = msg.get("content", "") if isinstance(msg, dict) else ""
                if isinstance(c, str) and c.strip():
                    last_user = c
        return last_user
    except Exception:
        return ""


def extract_subagent_meta(jsonl_path):
    """subagent jsonl 의 첫 user / 시작 시각 / agentId 등."""
    info = {
        "agent_id": "",
        "agent_type": "general-purpose",
        "first_ts_utc": "",
        "session_id": "",
        "kickoff_prompt": "",
    }
    meta_file = jsonl_path.parent / f"{jsonl_path.stem}.meta.json"
    if meta_file.exists():
        try:
            md = json.loads(meta_file.read_text())
            info["agent_type"] = md.get("agentType", info["agent_type"])
        except Exception:
            pass
    try:
        with jsonl_path.open() as f:
            for ln in f:
                try:
                    d = json.loads(ln)
                except Exception:
                    continue
                if not info["agent_id"]:
                    info["agent_id"] = d.get("agentId", "")
                if not info["session_id"]:
                    info["session_id"] = d.get("sessionId", "")
                ts_str = d.get("timestamp", "")
                if ts_str and not info["first_ts_utc"]:
                    try:
                        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                        info["first_ts_utc"] = ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                    except Exception:
                        pass
                if d.get("type") == "user" and not info["kickoff_prompt"]:
                    msg = d.get("message", {})
                    c = msg.get("content", "") if isinstance(msg, dict) else ""
                    if isinstance(c, str) and c.strip():
                        info["kickoff_prompt"] = c
                # 메타만 빨리 끝
                if info["agent_id"] and info["first_ts_utc"] and info["kickoff_prompt"]:
                    break
    except Exception:
        pass
    return info


def score_domain_match(text, terms):
    """text 에 terms 가 얼마나 등장하는가 (unique 매칭 + 빈도)."""
    if not text or not terms:
        return {"unique_hits": 0, "total_hits": 0, "term_count": len(terms), "ratio": 0.0, "top_terms": []}
    text_lower = text.lower()
    hits = Counter()
    for t in terms:
        # 단어 경계로 매칭 (한국어는 단어경계 의미 적음 — 그냥 substring)
        if t and t in text_lower:
            hits[t] = text_lower.count(t)
    unique = len(hits)
    total = sum(hits.values())
    ratio = unique / max(1, len(terms))
    top = hits.most_common(10)
    return {
        "unique_hits": unique,
        "total_hits": total,
        "term_count": len(terms),
        "ratio": round(ratio, 4),
        "top_terms": [{"term": k, "count": v} for k, v in top],
    }


def score_decision_patterns(text):
    if not text:
        return {k: 0 for k in DECISION_PATTERNS}
    out = {}
    for kind, pats in DECISION_PATTERNS.items():
        cnt = 0
        for p in pats:
            cnt += len(re.findall(p, text, re.IGNORECASE | re.MULTILINE))
        out[kind] = cnt
    return out


def score_structure(text):
    if not text:
        return {k: 0 for k in STRUCTURE_PATTERNS}
    out = {}
    for kind, pats in STRUCTURE_PATTERNS.items():
        cnt = 0
        for p in pats:
            cnt += len(re.findall(p, text, re.MULTILINE))
        out[kind] = cnt
    return out


def composite_score(domain, decision, structure, text_len, has_domain):
    """0~100 종합 점수.
    has_domain=False (knowledge 없는 외부 agent) → 도메인 차원 빼고 의사결정/구조/길이로만 평가.

    가중치:
    - has_domain=True:  domain 35% + decision 35% + structure 20% + length 10%
    - has_domain=False: decision 50% + structure 30% + length 20%

    domain_score 정상화:
    - unique_hits 절대값이 신호. 5개 이상 = 만점
    - 짧은 응답은 도메인 매칭 적은 게 정상 → text_len 으로 정규화
    """
    if text_len < 100:
        return 0.0

    decision_diversity = sum(1 for v in decision.values() if v > 0) / max(1, len(decision))
    decision_volume = min(1.0, sum(decision.values()) / 10)
    decision_score = (decision_diversity * 0.6 + decision_volume * 0.4)
    structure_score = min(1.0, sum(structure.values()) / 20)
    length_score = min(1.0, text_len / 2000)

    if has_domain:
        # unique_hits 5개 이상 = 만점, 0개 = 0점
        unique = domain.get("unique_hits", 0)
        domain_score = min(1.0, unique / 5)
        final = (domain_score * 0.35 + decision_score * 0.35 +
                 structure_score * 0.20 + length_score * 0.10) * 100
    else:
        # knowledge 없는 agent — 도메인 항목 제외
        final = (decision_score * 0.50 + structure_score * 0.30 +
                 length_score * 0.20) * 100
    return round(final, 1)


def build_terms_cache(quiet=False):
    terms_cache = {}
    for kdir in KNOWLEDGE_DIR.iterdir():
        if not kdir.is_dir():
            continue
        if kdir.name.startswith("_"):
            continue
        terms_cache[kdir.name] = extract_knowledge_terms(kdir.name)
    if not quiet:
        print(f"📚 용어집: {len(terms_cache)} agent types")
        for at, terms in sorted(terms_cache.items(), key=lambda x: -len(x[1])):
            print(f"  {at:25} {len(terms)} 용어")
    return terms_cache


def analyze_one(jsonl_path: Path, terms_cache: dict, existing_ids: set):
    """단일 subagent jsonl 분석 → result dict 또는 None.
    existing_ids 에 agent_id 있으면 None (중복)."""
    meta = extract_subagent_meta(jsonl_path)
    if not meta["first_ts_utc"]:
        return None
    if meta["agent_id"] and meta["agent_id"] in existing_ids:
        return None
    text = extract_subagent_text(jsonl_path)
    if not text:
        return None

    user_trigger = find_user_trigger(jsonl_path, meta["first_ts_utc"])
    agent_type = meta["agent_type"]
    terms = terms_cache.get(agent_type, set())

    domain = score_domain_match(text, terms)
    decision = score_decision_patterns(text)
    structure = score_structure(text)
    has_domain = bool(terms)
    score = composite_score(domain, decision, structure, len(text), has_domain)

    recommendations = []
    if len(text) < 500:
        recommendations.append({
            "type": "too_short", "priority": "high",
            "msg": f"출력이 너무 짧음 ({len(text)}자) — agent 가 작업 거부 / 결과 누락 가능. kickoff 명확화 필요.",
        })
    if has_domain and domain.get("unique_hits", 0) == 0:
        recommendations.append({
            "type": "domain_zero", "priority": "high",
            "msg": "자기 knowledge 용어 0개 매칭 — 빌드 미반영 또는 knowledge 부적합. agent rebuild 또는 knowledge 재작성 필요.",
        })
    decision_total = sum(decision.values())
    if decision_total < 2:
        recommendations.append({
            "type": "low_decision", "priority": "medium",
            "msg": f"의사결정 패턴 거의 없음 (총 {decision_total}). '왜', '대안', '검증' 명시하도록 prompt 개선.",
        })
    elif decision.get("근거", 0) == 0 and decision.get("트레이드오프", 0) == 0:
        recommendations.append({
            "type": "no_reasoning", "priority": "medium",
            "msg": "근거/트레이드오프 0건 — 결정 이유를 명시하지 않음. system prompt 에 'why' 강제 추가.",
        })
    struct_total = sum(structure.values())
    if struct_total < 3:
        recommendations.append({
            "type": "no_structure", "priority": "low",
            "msg": "구조화 거의 없음 (헤더/리스트/표/코드 합 < 3) — 산문형 출력. 템플릿 적용 권장.",
        })
    if has_domain and 1 <= domain.get("unique_hits", 0) < 3 and len(text) > 1500:
        recommendations.append({
            "type": "shallow_domain", "priority": "medium",
            "msg": f"긴 출력({len(text)}자) 대비 도메인 용어 {domain['unique_hits']}개만 — 일반론 위주. 자기 knowledge 명시 참조 강제.",
        })

    kickoff_and_output = (meta["kickoff_prompt"] + "\n" + text).lower()
    cross_scores = {}
    for other_at, other_terms in terms_cache.items():
        if not other_terms:
            continue
        hits = sum(1 for t in other_terms if t in kickoff_and_output)
        if hits > 0:
            cross_scores[other_at] = hits
    cross_top = sorted(cross_scores.items(), key=lambda x: -x[1])[:3]
    own_hits = cross_scores.get(agent_type, 0)
    suggested = None
    for other_at, hits in cross_top:
        if other_at != agent_type and hits >= max(3, own_hits * 1.5):
            suggested = other_at
            break
    if suggested:
        recommendations.append({
            "type": "wrong_agent", "priority": "high",
            "msg": f"이 작업은 '{suggested}' agent 가 더 적합 (다른 도메인 용어가 더 많이 매칭됨). 다음번엔 그쪽으로 호출.",
        })

    return {
        "agent_id": meta["agent_id"],
        "agent_type": agent_type,
        "session_id": meta["session_id"],
        "first_ts_utc": meta["first_ts_utc"],
        "kickoff_prompt": meta["kickoff_prompt"],
        "user_trigger": user_trigger,
        "text_len": len(text),
        "score": score,
        "domain": domain,
        "decision": decision,
        "structure": structure,
        "cross_top": [{"agent": a, "hits": h} for a, h in cross_top],
        "suggested_agent": suggested,
        "recommendations": recommendations,
    }


def load_existing_ids(out_file: Path) -> set:
    existing = set()
    if out_file.exists():
        for ln in out_file.read_text().splitlines():
            try:
                d = json.loads(ln)
                existing.add(d.get("agent_id", ""))
            except Exception:
                pass
    return existing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=14, help="최근 N 일 (default 14)")
    ap.add_argument("--limit", type=int, default=0, help="최대 N 개 처리 (0=무제한)")
    ap.add_argument("--single", type=str, default="", help="단일 subagent jsonl 파일만 분석 → 1줄 append (incremental 용)")
    args = ap.parse_args()

    out_file = LIVE_DIR / "agent-quality.jsonl"

    # === --single 모드: 단일 파일 분석 후 1줄 append ===
    if args.single:
        single_path = Path(args.single)
        if not single_path.exists():
            print(f"❌ 파일 없음: {single_path}", file=sys.stderr)
            sys.exit(1)
        terms_cache = build_terms_cache(quiet=True)
        existing = load_existing_ids(out_file)
        result = analyze_one(single_path, terms_cache, existing)
        if not result:
            # 중복 또는 분석 불가 (조용히 종료, 노이즈 없도록)
            sys.exit(0)
        with out_file.open("a") as f:
            f.write(json.dumps(result, ensure_ascii=False) + "\n")
        print(f"✅ +1 ({result['agent_type']} score={result['score']}) → {out_file.name}")
        sys.exit(0)

    # === 기존 batch 모드 ===
    since_utc = datetime.now(timezone.utc) - timedelta(days=args.days)
    print(f"📅 since: {since_utc.isoformat()}")

    terms_cache = build_terms_cache()

    # 모든 subagent jsonl 스캔
    sub_files = list(PROJECTS_DIR.glob("*/*/subagents/agent-*.jsonl"))
    print(f"\n🔍 subagent jsonl 후보: {len(sub_files)}")

    existing = load_existing_ids(out_file)
    print(f"📊 기존 분석된 agent: {len(existing)}")

    results = []
    processed = 0
    for f in sub_files:
        try:
            mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
        except Exception:
            continue
        if mtime < since_utc:
            continue

        result = analyze_one(f, terms_cache, existing)
        if not result:
            continue
        existing.add(result["agent_id"])  # 같은 batch 내 중복 방지
        results.append({
            "agent_id": result["agent_id"],
            "agent_type": result["agent_type"],
            "session_id": result["session_id"],
            "first_ts_utc": result["first_ts_utc"],
            "kickoff_prompt": result["kickoff_prompt"],
            "user_trigger": result["user_trigger"],
            "text_len": result["text_len"],
            "score": result["score"],
            "domain": result["domain"],
            "decision": result["decision"],
            "structure": result["structure"],
            "cross_top": result["cross_top"],
            "suggested_agent": result["suggested_agent"],
            "recommendations": result["recommendations"],
        })
        processed += 1
        if args.limit and processed >= args.limit:
            break

    print(f"\n🔢 새로 분석: {len(results)}개")

    if results:
        results.sort(key=lambda x: x["first_ts_utc"])
        with out_file.open("a") as f:
            for r in results:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        # 요약
        print("\n=== Agent Type 별 평균 점수 ===")
        by_type = {}
        for r in results:
            by_type.setdefault(r["agent_type"], []).append(r["score"])
        for at, scores in sorted(by_type.items(), key=lambda x: -sum(x[1])/max(1,len(x[1]))):
            avg = sum(scores) / max(1, len(scores))
            print(f"  {at:25} count={len(scores):3} avg_score={avg:5.1f}")

    print(f"\n✅ 완료: {out_file}")


if __name__ == "__main__":
    main()
