#!/bin/zsh
# PreToolUse(mcp__*): ToolSearch 로 로드 안 된 deferred MCP 도구 직접 호출 차단
#
# 문제 (2026-06-01 진단):
#   deferred(지연 로딩) 모드에서 mcp__ 도구를 ToolSearch 없이 바로 부르면
#   InputValidationError → ToolSearch → 재호출 왕복. 하루 7회+ 반복.
#
# 동작:
#   - tool_name 이 mcp__ 이고, 이번 세션에서 ToolSearch 로 로드된 적 없으면 exit 2 차단.
#   - toolsearch-mark-loaded.sh 가 PostToolUse(ToolSearch)에서 로드분을 적립.
#
# fail-open 안전장치 (오탐 방지):
#   - tool_name 못 읽으면 통과
#   - mcp__ 아니면 통과 (일반 도구는 항상 로드돼 있음)
#   - session_id 못 읽으면 통과 (추적 불가 시 막지 않음)
#   - 이미 로드된 도구면 통과 (ssh 등 반복 호출 정상 케이스)

: "${HOME:?}"
source "$HOME/.claude/hooks/_lib/loaded-tools.sh" 2>/dev/null || exit 0
source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT=$(cat)

TOOL=$(sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$INPUT" | head -1)

# mcp__ 도구가 아니면 관심 없음
case "$TOOL" in
    mcp__*) ;;
    *) exit 0 ;;
esac

SESSION="$(lt_session "$INPUT")"
# 세션 추적 불가 → fail-open (막지 않음)
[ -z "$SESSION" ] && exit 0

# 이미 ToolSearch 로 로드된 도구면 정상 통과
if lt_is_loaded "$SESSION" "$TOOL"; then
    type outcome_log >/dev/null 2>&1 && outcome_log "mcp-deferred-guard" "pass" "$TOOL" "already-loaded"
    exit 0
fi

# 로드 안 된 mcp__ 도구 직접 호출 → 차단
cat >&2 <<MSGEOF
[차단] 로드되지 않은 MCP 도구 직접 호출: $TOOL

이 도구는 deferred(지연 로딩) 상태일 가능성이 높다.
바로 호출하면 InputValidationError 가 나고 ToolSearch 왕복이 발생한다.

먼저 ToolSearch 로 스키마를 로드한 뒤 호출하라:
  ToolSearch(query: "select:$TOOL", max_results: 3)

또는 키워드 검색:
  ToolSearch(query: "<관련 키워드>", max_results: 5)

ToolSearch 결과에 이 도구가 나오면 그 다음 호출은 통과된다.
MSGEOF

type outcome_log >/dev/null 2>&1 && outcome_log "mcp-deferred-guard" "block" "$TOOL" "not-toolsearched"
exit 2
