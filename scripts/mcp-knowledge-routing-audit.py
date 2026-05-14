#!/usr/bin/env python3
"""
mcp-knowledge-routing-audit.py

라우팅 미스매치 탐지: 발화 분류와 실제 활용 결과의 일치도 분석.

원리:
  - memory-search-suggest hook은 "조사/분석" → claude-mem만 권고
  - 하지만 사용자가 코드 위치/구현 의도였다면 claude-mem 결과는 무관 → empty/no-citation
  - 같은 키워드 분류에서 empty_rate 또는 low citation 패턴이 반복되면 라우팅 재조정 필요

입력:
  - ~/.claude/cache/mcp-knowledge-telemetry/{date}.jsonl
  - ~/.claude/cache/hook-trace/{date}.jsonl   (memory-search-suggest 분류)
  - 같은 turn 시간 ±60초 매칭 (정확한 매칭 어려움 → heuristic)

출력:
  ~/.claude/cache/mcp-knowledge-routing-audit-{N}d.json

사용:
  python3 ~/.claude/scripts/mcp-knowledge-routing-audit.py [days=7]
"""
import json
import sys
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict

HOME = Path.home()
TELEMETRY_DIR = HOME / ".claude" / "cache" / "mcp-knowledge-telemetry"
HOOK_TRACE_DIR = HOME / ".claude" / "cache" / "hook-trace"
OUTPUT_DIR = HOME / ".claude" / "cache"


def load_jsonl(path):
    rows = []
    if not path.exists():
        return rows
    with open(path) as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def load_recent(days, dir_path, pattern="*.jsonl"):
    cutoff = datetime.now() - timedelta(days=days)
    rows = []
    for f in sorted(dir_path.glob(pattern)):
        try:
            d = datetime.strptime(f.stem, "%Y-%m-%d")
            if d < cutoff - timedelta(days=1):
                continue
        except ValueError:
            continue
        rows.extend(load_jsonl(f))
    return rows


def parse_ts(s):
    if not s:
        return None
    try:
        # 다양한 포맷 핸들링
        s = s.replace("Z", "+00:00")
        if "T" in s:
            return datetime.fromisoformat(s).replace(tzinfo=None)
        return datetime.strptime(s[:19], "%Y-%m-%d %H:%M:%S")
    except (ValueError, TypeError):
        return None


def audit(days=7):
    telemetry = load_recent(days, TELEMETRY_DIR)
    if not telemetry:
        return {"days": days, "total_calls": 0, "by_routing": {}, "summary": "No telemetry data"}

    # 도구 카테고리별 집계
    # 라우팅 의도(권고된 도구) vs 실제 활용 패턴 매칭
    by_tool = defaultdict(lambda: {
        "total": 0,
        "empty": 0,
        "errors": 0,
        "low_score_calls": 0,  # top_score > 0.15 (관련성 낮음)
    })

    for row in telemetry:
        tool = row.get("tool", "unknown")
        b = by_tool[tool]
        b["total"] += 1
        if row.get("error"):
            b["errors"] += 1
            continue
        rc = row.get("result_count", 0) or 0
        if rc == 0 and not row.get("has_results"):
            b["empty"] += 1
            continue
        ts = row.get("top_score", "")
        try:
            score = float(ts) if ts else None
        except (ValueError, TypeError):
            score = None
        if score is not None and score > 0.15:
            b["low_score_calls"] += 1

    # 라우팅 권고 (memory-search-suggest 키워드 그룹별 도구)
    routing_table = {
        "기능/구현": "local-rag",
        "리팩터": "local-rag",
        "쿼리/성능": "local-rag",
        "배포/인프라": "local-rag",
        "조사/분석": "claude-mem",
        "후속/확인": "claude-mem",
        "일반작업(15자+ 폴백)": "claude-mem",
        "설계/아키텍처": "both",
        "버그/에러": "both",
    }

    # 미스매치 후보 자동 탐지
    findings = []
    for tool, b in by_tool.items():
        total = b["total"]
        if total < 5:
            continue
        empty_rate = b["empty"] / total
        low_rate = b["low_score_calls"] / max(total - b["empty"] - b["errors"], 1)

        short = tool.replace("mcp__plugin_claude-mem_mcp-search__", "mem:").replace("mcp__local-rag__", "rag:")

        if empty_rate > 0.4:
            findings.append({
                "severity": "high",
                "tool": short,
                "issue": "empty_rate_high",
                "value": round(empty_rate, 3),
                "recommendation": f"{short} 호출 중 {empty_rate*100:.0f}%가 빈 결과. 라우팅 키워드가 이 도구에 부적합한 발화를 보내고 있을 가능성.",
            })
        if low_rate > 0.5 and tool.endswith("query_documents"):
            findings.append({
                "severity": "medium",
                "tool": short,
                "issue": "low_relevance",
                "value": round(low_rate, 3),
                "recommendation": f"{short}에서 score>0.15 (낮은 관련성) 비율 {low_rate*100:.0f}%. 쿼리 키워드 추출 개선 또는 다른 도구로 라우팅 검토.",
            })

    return {
        "days": days,
        "total_calls": sum(b["total"] for b in by_tool.values()),
        "routing_table": routing_table,
        "by_tool": {k: dict(v) for k, v in by_tool.items()},
        "findings": findings,
        "summary": (
            f"{len(findings)} 라우팅 이슈 발견" if findings
            else "라우팅 이상 신호 없음 (또는 데이터 부족)"
        ),
        "generated_at": datetime.now().isoformat(timespec="seconds"),
    }


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    result = audit(days)
    out_path = OUTPUT_DIR / f"mcp-knowledge-routing-audit-{days}d.json"
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2))

    print(f"=== MCP Knowledge Routing Audit (최근 {days}일) ===\n")
    print(f"총 호출: {result['total_calls']}")
    if result["total_calls"] == 0:
        print("(데이터 없음 — telemetry 누적 후 다시 실행)")
        return
    print(f"\n라우팅 테이블 (현재):")
    for trigger, tool in result["routing_table"].items():
        print(f"  {trigger:30} → {tool}")
    print(f"\n발견 사항 ({len(result['findings'])}건):")
    if not result["findings"]:
        print("  (이상 없음)")
    for f in result["findings"]:
        sev_icon = {"high": "🔴", "medium": "🟡", "low": "🟢"}.get(f["severity"], "⚪")
        print(f"  {sev_icon} [{f['issue']}] {f['tool']}: {f['recommendation']}")
    print(f"\n리포트: {out_path}")


if __name__ == "__main__":
    main()
