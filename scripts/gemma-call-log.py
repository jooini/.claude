#!/usr/bin/env python3
"""
Gemma 호출 로그 통합 뷰어.

사용:
  ./gemma-call-log.py                  # 오늘 호출 요약
  ./gemma-call-log.py --tail            # 마지막 10건 전문
  ./gemma-call-log.py --search "JWT"    # 키워드 검색
  ./gemma-call-log.py --date 2026-04-22 # 특정 날짜
  ./gemma-call-log.py --stats           # 훅별 통계

데이터 소스:
  - ~/.claude/cache/gemma-calls.jsonl   # 모든 호출 raw 로그 (신규)
  - ~/.claude/cache/{health,daily,...}/ # 결과물 캐시
  - ~/.claude/cache/gemma-queue.log     # 훅 실행 로그
"""
import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

LOG_FILE = Path.home() / ".claude" / "cache" / "gemma-calls.jsonl"
CACHE_BASE = Path.home() / ".claude" / "cache"


def load_calls(date_filter=None):
    """JSONL 로그에서 호출 기록 로드."""
    if not LOG_FILE.exists():
        return []

    calls = []
    with LOG_FILE.open(encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
                if date_filter:
                    ts = rec.get("timestamp", "")
                    if not ts.startswith(date_filter):
                        continue
                calls.append(rec)
            except Exception:
                continue
    return calls


def cmd_stats(args):
    """훅별 집계."""
    calls = load_calls()
    if not calls:
        print("로그 없음 — 아직 호출 기록 안 됨")
        print(f"경로: {LOG_FILE}")
        return

    by_hook = {}
    by_date = {}
    total_duration = 0
    total_tokens_in = 0
    total_tokens_out = 0

    for c in calls:
        hook = c.get("caller", "unknown")
        date = c.get("timestamp", "")[:10]
        by_hook[hook] = by_hook.get(hook, 0) + 1
        by_date[date] = by_date.get(date, 0) + 1
        total_duration += c.get("duration_ms", 0) or 0
        total_tokens_in += c.get("input_tokens", 0) or 0
        total_tokens_out += c.get("output_tokens", 0) or 0

    print(f"=== Gemma 호출 통계 (총 {len(calls)}건) ===\n")
    print(f"총 소요 시간: {total_duration/1000:.1f}초")
    print(f"입력 토큰 추정: {total_tokens_in:,}")
    print(f"출력 토큰: {total_tokens_out:,}")
    print()
    print("## 훅별 호출 (top 10)")
    for hook, count in sorted(by_hook.items(), key=lambda x: -x[1])[:10]:
        print(f"  {hook:30s} {count}회")
    print()
    print("## 날짜별 호출 (최근 7일)")
    for date in sorted(by_date.keys(), reverse=True)[:7]:
        print(f"  {date}  {by_date[date]}회")


def cmd_tail(args):
    """최근 N건 전문 출력."""
    calls = load_calls()
    if not calls:
        print("로그 없음")
        return
    n = args.n or 10
    print(f"=== 최근 {n}건 Gemma 호출 ===\n")
    for c in calls[-n:]:
        ts = c.get("timestamp", "?")
        hook = c.get("caller", "?")
        duration = c.get("duration_ms", 0) / 1000
        status = c.get("status", "?")
        print(f"━━━━━ {ts} [{hook}] ({duration:.1f}s, {status}) ━━━━━")
        print(f"모델: {c.get('model', '?')}")
        prompt = c.get("prompt_preview", "")
        if prompt:
            print(f"입력 (앞 200자): {prompt[:200]}")
        resp = c.get("response_preview", "")
        if resp:
            print(f"출력 (앞 300자): {resp[:300]}")
        print()


def cmd_search(args):
    """키워드 검색."""
    calls = load_calls()
    keyword = args.keyword.lower()
    matches = []
    for c in calls:
        haystack = (
            c.get("prompt_preview", "") + " " +
            c.get("response_preview", "") + " " +
            c.get("caller", "")
        ).lower()
        if keyword in haystack:
            matches.append(c)

    if not matches:
        print(f"'{keyword}' 매칭 호출 없음")
        return

    print(f"=== '{keyword}' 검색 결과 ({len(matches)}건) ===\n")
    for c in matches[-20:]:
        ts = c.get("timestamp", "?")
        hook = c.get("caller", "?")
        print(f"━━━ {ts} [{hook}]")
        for field in ("prompt_preview", "response_preview"):
            text = c.get(field, "")
            if keyword in text.lower():
                # 키워드 주변 100자
                idx = text.lower().find(keyword)
                start = max(0, idx - 50)
                end = min(len(text), idx + 150)
                snippet = text[start:end].replace("\n", " ")
                label = "입력" if "prompt" in field else "출력"
                print(f"  {label}: ...{snippet}...")
        print()


def cmd_summary(args):
    """오늘 요약."""
    today = args.date or datetime.now().strftime("%Y-%m-%d")
    calls = load_calls(date_filter=today)

    print(f"=== {today} Gemma 호출 요약 ===\n")

    if not calls:
        print(f"{today} 호출 기록 없음")
        print()
        print("힌트: 로그 수집 시작하려면")
        print(f"  touch {LOG_FILE}")
        print("  훅 스크립트에서 호출 전후 로깅 추가 필요")
        return

    # 훅별 + 총 시간
    by_hook = {}
    total_ms = 0
    for c in calls:
        hook = c.get("caller", "unknown")
        if hook not in by_hook:
            by_hook[hook] = {"count": 0, "duration": 0}
        by_hook[hook]["count"] += 1
        by_hook[hook]["duration"] += c.get("duration_ms", 0) or 0
        total_ms += c.get("duration_ms", 0) or 0

    print(f"총 호출: {len(calls)}건, {total_ms/1000:.1f}초")
    print()
    print("훅별 분포:")
    for hook, stats in sorted(by_hook.items(), key=lambda x: -x[1]["count"]):
        avg = stats["duration"] / stats["count"] / 1000 if stats["count"] else 0
        print(f"  {hook:30s} {stats['count']:3d}회  평균 {avg:.1f}s")

    # 결과물 파일도 같이 보여주기
    print()
    print("## 오늘의 결과물")
    for sub in ("health-report", "daily-draft", "morning-brief", "triage-dirty"):
        f = CACHE_BASE / sub / f"{today}.md"
        if f.exists():
            size = f.stat().st_size
            print(f"  ✅ {sub}: {f} ({size}B)")


def main():
    parser = argparse.ArgumentParser(description="Gemma 호출 로그 조회")
    sub = parser.add_subparsers(dest="cmd")

    p_stats = sub.add_parser("stats", help="통계")
    p_stats.set_defaults(func=cmd_stats)

    p_tail = sub.add_parser("tail", help="최근 호출")
    p_tail.add_argument("-n", type=int, default=10)
    p_tail.set_defaults(func=cmd_tail)

    p_search = sub.add_parser("search", help="키워드 검색")
    p_search.add_argument("keyword")
    p_search.set_defaults(func=cmd_search)

    parser.add_argument("--date", help="특정 날짜 요약 (YYYY-MM-DD)")

    args = parser.parse_args()

    if hasattr(args, "func"):
        args.func(args)
    else:
        # 기본: 오늘 요약
        cmd_summary(args)


if __name__ == "__main__":
    main()
