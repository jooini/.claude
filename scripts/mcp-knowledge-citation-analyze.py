#!/usr/bin/env python3
"""
mcp-knowledge-citation-analyze.py

지식도메인 MCP 호출의 citation rate 분석.
- 입력: ~/.claude/cache/mcp-knowledge-telemetry/{date}.jsonl
        ~/.claude/projects/-Users-leonard/{session}.jsonl
- 출력: ~/.claude/cache/mcp-knowledge-citation-{N}d.json

citation 정의:
  호출 결과(top filePath 또는 결과 텍스트의 키워드)가 같은 turn 안의
  후속 assistant 메시지 텍스트에 등장하면 'cited'.

사용:
  python3 ~/.claude/scripts/mcp-knowledge-citation-analyze.py [days=7]
"""
import json
import sys
import re
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict

HOME = Path.home()
TELEMETRY_DIR = HOME / ".claude" / "cache" / "mcp-knowledge-telemetry"
TRANSCRIPT_ROOTS = [
    HOME / ".claude" / "projects" / "-Users-leonard",
]
# 다른 워크스페이스 루트도 추가 검색
for p in (HOME / ".claude" / "projects").glob("-Users-leonard-Workspace-*"):
    if p.is_dir():
        TRANSCRIPT_ROOTS.append(p)

OUTPUT_DIR = HOME / ".claude" / "cache"


def load_telemetry(days):
    """최근 N일 telemetry 로드"""
    rows = []
    cutoff = datetime.now() - timedelta(days=days)
    for f in sorted(TELEMETRY_DIR.glob("*.jsonl")):
        try:
            d = datetime.strptime(f.stem, "%Y-%m-%d")
            if d < cutoff - timedelta(days=1):
                continue
        except ValueError:
            continue
        with open(f) as fh:
            for line in fh:
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return rows


def load_transcript(session_prefix):
    """세션 prefix(8자)로 transcript jsonl 로드. 없으면 빈 리스트"""
    for root in TRANSCRIPT_ROOTS:
        for f in root.glob(f"{session_prefix}*.jsonl"):
            with open(f) as fh:
                events = []
                for line in fh:
                    try:
                        events.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
                return events
    return []


def extract_citation_keywords(tool_response_text):
    """tool_response 안에서 citation 매칭에 쓸 키워드 추출.

    local-rag: filePath 의 마지막 segment (확장자 포함)
    mem-search: 'Found' 같은 메타 텍스트는 제외, file path 패턴 추출
    """
    keywords = set()
    # 파일 경로 패턴 (md, py, ts, tsx 등)
    for m in re.finditer(r'([\w\-]+\.(md|py|ts|tsx|js|jsx|kt|java|sh|json|yaml|yml))', tool_response_text):
        kw = m.group(1)
        if len(kw) >= 8:  # 너무 짧으면 우연 매칭 위험
            keywords.add(kw)
    # 백틱 인용 (`xxx`)
    for m in re.finditer(r'`([^`]{6,40})`', tool_response_text):
        keywords.add(m.group(1))
    return keywords


def analyze(days=7):
    telemetry = load_telemetry(days)
    if not telemetry:
        return {
            "days": days,
            "total_calls": 0,
            "by_tool": {},
            "summary": "No telemetry data",
        }

    # 세션별 transcript 캐시 (한 번만 로드)
    transcript_cache = {}
    def get_transcript(sid):
        if sid not in transcript_cache:
            transcript_cache[sid] = load_transcript(sid)
        return transcript_cache[sid]

    by_tool = defaultdict(lambda: {
        "total": 0,
        "cited": 0,
        "empty": 0,
        "errors": 0,
        "avg_latency_ms": 0,
        "avg_result_count": 0,
        "_lat_sum": 0,
        "_lat_n": 0,
        "_res_sum": 0,
        "_res_n": 0,
    })

    for row in telemetry:
        tool = row.get("tool", "unknown")
        sid = row.get("session", "")

        bucket = by_tool[tool]
        bucket["total"] += 1

        if row.get("error"):
            bucket["errors"] += 1
            continue

        rc = row.get("result_count", 0) or 0
        if rc == 0 and not row.get("has_results"):
            bucket["empty"] += 1
            continue

        # latency / result_count 누적
        lat = row.get("latency_ms")
        if isinstance(lat, int) and lat > 0:
            bucket["_lat_sum"] += lat
            bucket["_lat_n"] += 1
        bucket["_res_sum"] += rc
        bucket["_res_n"] += 1

        # citation 매칭: 같은 세션의 후속 assistant 메시지에 키워드 등장하나
        # telemetry에는 tool_response 본문이 없으므로 transcript에서 매칭된 tool_use_id로 결과 가져오기
        events = get_transcript(sid)
        if not events:
            continue

        # transcript 내에서 해당 호출 찾기 (query 일치 기준)
        query = (row.get("query") or "").strip()
        if not query:
            continue

        cited = False
        # tool_use 매칭 → 다음 assistant 텍스트에서 키워드 검색
        for i, ev in enumerate(events):
            if ev.get("type") != "assistant":
                continue
            content = ev.get("message", {}).get("content", [])
            if not isinstance(content, list):
                continue
            for c in content:
                if c.get("type") != "tool_use":
                    continue
                if c.get("name") != tool:
                    continue
                inp = c.get("input", {}) or {}
                if (inp.get("query") or "").strip() != query:
                    continue
                # 매칭된 호출 — 다음 turn (다음 user 메시지까지의 assistant text) 검사
                tu_id = c.get("id", "")
                # tool_result 찾기
                response_text = ""
                for j in range(i + 1, len(events)):
                    e2 = events[j]
                    if e2.get("type") == "user":
                        cont2 = e2.get("message", {}).get("content", [])
                        if isinstance(cont2, list):
                            for c2 in cont2:
                                if c2.get("type") == "tool_result" and c2.get("tool_use_id") == tu_id:
                                    rc_content = c2.get("content", "")
                                    if isinstance(rc_content, str):
                                        response_text = rc_content
                                    elif isinstance(rc_content, list):
                                        response_text = " ".join(
                                            cc.get("text", "")
                                            for cc in rc_content
                                            if isinstance(cc, dict)
                                        )
                                    break
                        if response_text:
                            break
                    elif e2.get("type") == "assistant":
                        # 후속 assistant 텍스트
                        pass
                if not response_text:
                    continue

                keywords = extract_citation_keywords(response_text)
                if not keywords:
                    continue

                # 다음 user(다른 input)까지 assistant text 누적
                following_text = ""
                for j in range(i + 1, len(events)):
                    e2 = events[j]
                    t2 = e2.get("type")
                    if t2 == "user":
                        cont2 = e2.get("message", {}).get("content", [])
                        if isinstance(cont2, list) and any(
                            cc.get("type") == "text" for cc in cont2 if isinstance(cc, dict)
                        ):
                            break  # 새 user 발화 시작
                    if t2 == "assistant":
                        cont2 = e2.get("message", {}).get("content", [])
                        if isinstance(cont2, list):
                            for cc in cont2:
                                if isinstance(cc, dict) and cc.get("type") == "text":
                                    following_text += " " + cc.get("text", "")

                if any(kw in following_text for kw in keywords):
                    cited = True
                break  # 매칭된 호출 처리 완료
            if cited:
                break

        if cited:
            bucket["cited"] += 1

    # 평균 계산
    out_by_tool = {}
    for tool, b in by_tool.items():
        total = b["total"]
        out_by_tool[tool] = {
            "total": total,
            "cited": b["cited"],
            "empty": b["empty"],
            "errors": b["errors"],
            "citation_rate": round(b["cited"] / max(total - b["errors"] - b["empty"], 1), 3),
            "empty_rate": round(b["empty"] / max(total, 1), 3),
            "error_rate": round(b["errors"] / max(total, 1), 3),
            "avg_latency_ms": round(b["_lat_sum"] / max(b["_lat_n"], 1)),
            "avg_result_count": round(b["_res_sum"] / max(b["_res_n"], 1), 1),
        }

    total_calls = sum(b["total"] for b in by_tool.values())
    total_cited = sum(b["cited"] for b in by_tool.values())
    total_errors = sum(b["errors"] for b in by_tool.values())
    total_empty = sum(b["empty"] for b in by_tool.values())

    return {
        "days": days,
        "total_calls": total_calls,
        "total_cited": total_cited,
        "total_empty": total_empty,
        "total_errors": total_errors,
        "overall_citation_rate": round(total_cited / max(total_calls - total_errors - total_empty, 1), 3),
        "by_tool": out_by_tool,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
    }


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    result = analyze(days)

    out_path = OUTPUT_DIR / f"mcp-knowledge-citation-{days}d.json"
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2))

    # stdout — 사람용 요약
    print(f"=== MCP Knowledge Citation Analysis (최근 {days}일) ===\n")
    print(f"총 호출: {result['total_calls']}회")
    if result['total_calls'] == 0:
        print("(데이터 없음 — telemetry 가 새 세션부터 누적됩니다)")
        return
    print(f"  citation: {result['total_cited']}회 ({result['overall_citation_rate']*100:.1f}%)")
    print(f"  empty:    {result['total_empty']}회")
    print(f"  errors:   {result['total_errors']}회")
    print()
    print("도구별:")
    for tool, b in result["by_tool"].items():
        short = tool.replace("mcp__plugin_claude-mem_mcp-search__", "mem:").replace("mcp__local-rag__", "rag:")
        print(f"  {short:35} | total={b['total']:4} cited={b['citation_rate']*100:5.1f}% empty={b['empty_rate']*100:5.1f}% err={b['error_rate']*100:5.1f}% lat={b['avg_latency_ms']}ms results={b['avg_result_count']}")
    print()
    print(f"리포트 저장: {out_path}")


if __name__ == "__main__":
    main()
