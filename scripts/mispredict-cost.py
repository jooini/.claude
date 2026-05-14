#!/usr/bin/env python3
"""
mispredict-cost — 추정 정정으로 낭비된 비용 측정

정의:
- BAD 발화 = 직전 사용자 발화에서 정정 신호 ("아니/틀렸/잘못/추정") 감지
- 낭비 비용 = BAD 직전의 assistant 응답 + 그 직전 user 발화 사이 발생한 모든 assistant 토큰 비용
  (= 추정으로 만든 답변이 폐기되어 다시 만들어야 했던 비용)

사용:
  python3 ~/.claude/scripts/mispredict-cost.py --days 30
  python3 ~/.claude/scripts/mispredict-cost.py --json
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta

CORRECTION_RE = re.compile(
    r"(아니야|아니지|^아니 |틀렸|잘못|왜 자꾸|왜 그래|추정|추측|가정|wrong|incorrect)",
    re.IGNORECASE,
)

# 모델별 1M 토큰당 USD (llm-usage.py와 동일 — 가격 변동 시 외부 yaml로 분리 가능)
PRICING = {
    'claude-opus-4-7':   {'input': 15.0, 'output': 75.0, 'cache_read': 1.5, 'cache_create': 18.75},
    'claude-sonnet-4-6': {'input':  3.0, 'output': 15.0, 'cache_read': 0.3, 'cache_create':  3.75},
    'claude-haiku-4-5':  {'input':  1.0, 'output':  5.0, 'cache_read': 0.1, 'cache_create':  1.25},
    'default':           {'input':  3.0, 'output': 15.0, 'cache_read': 0.3, 'cache_create':  3.75},
}


def cost_of_usage(model, usage):
    p = PRICING.get(model) or PRICING['default']
    return (
        usage.get('input_tokens', 0) / 1_000_000 * p['input']
        + usage.get('output_tokens', 0) / 1_000_000 * p['output']
        + usage.get('cache_read_input_tokens', 0) / 1_000_000 * p['cache_read']
        + usage.get('cache_creation_input_tokens', 0) / 1_000_000 * p['cache_create']
    )


def extract_text(msg):
    if not isinstance(msg, dict):
        return ""
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                out.append(part.get("text", ""))
            elif isinstance(part, str):
                out.append(part)
        return " ".join(out)
    return ""


def is_real_user(obj):
    """진짜 사용자 발화 (시스템 reminder/hook 제외)"""
    if obj.get("type") != "user":
        return False
    msg = obj.get("message", {})
    if not isinstance(msg, dict) or msg.get("role") != "user":
        return False
    text = extract_text(msg)
    if not text:
        return False
    # tool_use_result, system-reminder 등 자동 메시지 거름
    content = msg.get("content")
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and part.get("type") in ("tool_result", "tool_use"):
                return False
    if "<system-reminder>" in text and len(text.replace("<system-reminder>", "").strip()) < 50:
        return False
    return True


def analyze_session(path, since_ts):
    """1 session jsonl → 정정 사건 + 낭비 비용 리스트"""
    events = []
    try:
        with open(path) as f:
            for line in f:
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                ts = obj.get("timestamp", "")
                if ts and since_ts and ts < since_ts:
                    continue
                events.append(obj)
    except Exception:
        return []

    incidents = []
    pending_assistant_cost = 0.0
    pending_assistant_tokens = 0
    last_user_idx = None

    for i, obj in enumerate(events):
        t = obj.get("type")

        if t == "assistant":
            msg = obj.get("message", {})
            usage = msg.get("usage") if isinstance(msg, dict) else None
            if usage:
                model = msg.get("model", "default")
                pending_assistant_cost += cost_of_usage(model, usage)
                pending_assistant_tokens += (
                    usage.get("output_tokens", 0)
                    + usage.get("input_tokens", 0)
                )

        elif is_real_user(obj):
            text = extract_text(obj.get("message", {}))
            # 슬래시/시스템 reminder 단독은 거름
            stripped = re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.S).strip()
            if not stripped:
                continue

            # 정정 발화?
            if last_user_idx is not None and CORRECTION_RE.search(stripped[:200]):
                incidents.append({
                    "session": os.path.basename(path),
                    "timestamp": obj.get("timestamp", ""),
                    "correction_text": stripped[:120],
                    "wasted_cost": round(pending_assistant_cost, 4),
                    "wasted_tokens": pending_assistant_tokens,
                })

            last_user_idx = i
            pending_assistant_cost = 0.0
            pending_assistant_tokens = 0

    return incidents


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--days", type=int, default=30)
    p.add_argument("--json", action="store_true")
    p.add_argument("--top", type=int, default=10)
    args = p.parse_args()

    since = (datetime.now() - timedelta(days=args.days)).isoformat()
    pattern = os.path.expanduser("~/.claude/projects/**/*.jsonl")
    all_incidents = []
    for path in glob.glob(pattern, recursive=True):
        all_incidents.extend(analyze_session(path, since))

    total_wasted = sum(i["wasted_cost"] for i in all_incidents)
    total_tokens = sum(i["wasted_tokens"] for i in all_incidents)
    by_session = defaultdict(lambda: {"count": 0, "cost": 0.0})
    for inc in all_incidents:
        s = inc["session"]
        by_session[s]["count"] += 1
        by_session[s]["cost"] += inc["wasted_cost"]

    daily = defaultdict(lambda: {"count": 0, "cost": 0.0})
    for inc in all_incidents:
        day = (inc["timestamp"] or "")[:10]
        if day:
            daily[day]["count"] += 1
            daily[day]["cost"] += inc["wasted_cost"]

    summary = {
        "days": args.days,
        "total_incidents": len(all_incidents),
        "total_wasted_usd": round(total_wasted, 2),
        "total_wasted_krw": int(total_wasted * 1380),
        "total_wasted_tokens": total_tokens,
        "by_session_top": sorted(
            ({"session": s, **v} for s, v in by_session.items()),
            key=lambda x: x["cost"], reverse=True
        )[: args.top],
        "daily": dict(sorted(daily.items(), reverse=True)),
        "top_incidents": sorted(all_incidents, key=lambda i: i["wasted_cost"], reverse=True)[: args.top],
    }

    if args.json:
        json.dump(summary, sys.stdout, ensure_ascii=False, indent=2)
        return

    print(f"💸 추정 정정 낭비 비용 — 최근 {args.days}일")
    print(f"   사건: {summary['total_incidents']:,}회")
    print(f"   낭비: ${summary['total_wasted_usd']:,.2f} (₩{summary['total_wasted_krw']:,})")
    print(f"   토큰: {summary['total_wasted_tokens']:,}")
    print()
    print(f"📅 일별 TOP")
    for day, v in list(summary["daily"].items())[:7]:
        print(f"   {day}  {v['count']:3d}건  ${v['cost']:7.2f}  ₩{int(v['cost']*1380):,}")
    print()
    print(f"🔥 비싼 정정 사건 TOP {args.top}")
    for inc in summary["top_incidents"]:
        print(f"   ${inc['wasted_cost']:7.2f}  ₩{int(inc['wasted_cost']*1380):>7,}  {inc['timestamp'][:16]}")
        print(f"      → {inc['correction_text'][:80]}")


if __name__ == "__main__":
    main()
