#!/bin/zsh
# PostToolUse: 지식도메인 MCP 호출 telemetry 기록
#
# 대상 도구:
#   - mcp__local-rag__query_documents
#   - mcp__plugin_claude-mem_mcp-search__search (외 mcp-search 그룹)
#
# 기록 위치: ~/.claude/cache/mcp-knowledge-telemetry/{date}.jsonl
#
# 필드:
#   {ts, session, tool, query, latency_ms, result_count, top_score, error, has_results}
#
# 비차단 — 실패해도 exit 0

: "${HOME:?}"

INPUT=$(cat)

PARSED=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys, re
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', '')

    # 지식도메인 도구만 필터
    if not (tool.startswith('mcp__local-rag__') or tool.startswith('mcp__plugin_claude-mem_mcp-search__')):
        sys.exit(0)

    tin = d.get('tool_input', {}) or {}
    tout = d.get('tool_response', {}) or {}
    session = (d.get('session_id', '') or '')[:8]

    query = tin.get('query', '')
    if isinstance(query, str):
        query = query[:200]

    # 결과 분석
    error = ''
    result_count = 0
    top_score = ''
    has_results = False

    if isinstance(tout, dict) and tout.get('isError'):
        error = str(tout.get('content', ''))[:200]
    else:
        # tool_response.content 구조: [{type:'text', text:'...'}] 또는 [{ score, ... }]
        content = tout.get('content', tout) if isinstance(tout, dict) else tout

        if isinstance(content, list):
            # local-rag: list of {filePath, score, ...}
            scored = [c for c in content if isinstance(c, dict) and 'score' in c]
            if scored:
                result_count = len(scored)
                top_score = f\"{scored[0].get('score', ''):.4f}\" if scored[0].get('score') is not None else ''
                has_results = True
            else:
                # mem-search: text 안에 'Found N result(s)'
                texts = [c.get('text','') for c in content if isinstance(c, dict)]
                blob = ' '.join(texts)
                m = re.search(r'Found (\d+) result', blob)
                if m:
                    result_count = int(m.group(1))
                    has_results = result_count > 0
                elif blob.strip():
                    has_results = True

    print(json.dumps({
        'tool': tool,
        'session': session,
        'query': query,
        'result_count': result_count,
        'top_score': top_score,
        'error': error,
        'has_results': has_results,
    }, ensure_ascii=False))
except SystemExit:
    raise
except Exception as e:
    pass
" 2>/dev/null)

# 파싱 실패 / 비대상 도구 → 스킵
[ -z "$PARSED" ] && exit 0

LOG_DIR="$HOME/.claude/cache/mcp-knowledge-telemetry"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LATENCY="${HOOK_TIMING_MS:-}"

# ts/latency 추가하여 기록
echo "$PARSED" | /usr/bin/python3 -c "
import json, sys, os
try:
    d = json.loads(sys.stdin.read())
    d['ts'] = '$TS'
    d['latency_ms'] = int('$LATENCY') if '$LATENCY'.isdigit() else None
    print(json.dumps(d, ensure_ascii=False))
except Exception:
    pass
" >> "$LOG_FILE" 2>/dev/null

exit 0
