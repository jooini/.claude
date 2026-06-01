#!/bin/zsh
# 공통 라이브러리: 세션별 "ToolSearch로 로드된 도구" 추적
#
# 배경 (2026-06-01):
#   MCP 도구가 많으면 Claude Code가 deferred(지연 로딩) 모드로 95개+ 도구를
#   이름만 노출하고 스키마를 안 띄운다. LLM이 ToolSearch 없이 mcp__ 도구를
#   바로 부르면 InputValidationError가 나서 ToolSearch → 재호출 왕복이 발생.
#   하루 7회+ 반복 관측. deferred 목록은 파일로 안 남아 hook이 직접 추적해야 한다.
#
# 데이터:
#   ${LOADED_TOOLS_DIR:-~/.claude/cache/loaded-tools}/{session8}.txt
#   한 줄당 로드된 도구명 1개. ToolSearch PostToolUse 가 적립.
#
# 테스트 격리: LOADED_TOOLS_DIR override 가능.

: "${HOME:?}"

_lt_dir() {
    echo "${LOADED_TOOLS_DIR:-$HOME/.claude/cache/loaded-tools}"
}

# session_id(앞 8자)로 세션 파일 경로
_lt_file() {
    local session="$1"
    [ -z "$session" ] && session="unknown"
    echo "$(_lt_dir)/${session}.txt"
}

# stdin INPUT JSON 에서 session_id 앞 8자 추출
lt_session() {
    sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]\{1,8\}\).*/\1/p' <<< "$1"
}

# 도구 1개 적립 (중복 무시)
lt_mark() {
    local session="$1" tool="$2"
    [ -z "$tool" ] && return 0
    local f; f="$(_lt_file "$session")"
    mkdir -p "$(dirname "$f")" 2>/dev/null
    grep -qxF "$tool" "$f" 2>/dev/null || printf '%s\n' "$tool" >> "$f"
}

# 도구가 이번 세션에서 이미 로드됐나? (0=로드됨, 1=아님)
lt_is_loaded() {
    local session="$1" tool="$2"
    local f; f="$(_lt_file "$session")"
    grep -qxF "$tool" "$f" 2>/dev/null
}
