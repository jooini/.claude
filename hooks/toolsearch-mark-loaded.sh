#!/bin/zsh
# PostToolUse(ToolSearch): ToolSearch 가 로드한 도구명을 세션 파일에 적립
#
# ToolSearch 호출이 성공하면 그 결과로 도구 스키마가 세션에 로드된다.
# 어떤 도구가 로드됐는지를 추적해, PreToolUse(mcp-deferred-guard)가
# "아직 ToolSearch 안 한 mcp__ 도구"만 골라 차단할 수 있게 한다.
#
# 적립 소스 2개:
#   1) tool_input.query 의 "select:A,B,C" — 명시 선택분
#   2) tool_response 안의 "name":"..." — 키워드 검색으로 매칭된 결과
# 둘 다 긁어서 합집합으로 적립 (fail-open: 못 긁어도 조용히 통과).

: "${HOME:?}"
source "$HOME/.claude/hooks/_lib/loaded-tools.sh" 2>/dev/null || exit 0

INPUT=$(cat)
SESSION="$(lt_session "$INPUT")"

# 1) query 의 select: 목록 파싱 (select:A,B,C 형태)
QUERY=$(sed -n 's/.*"query"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$INPUT" | head -1)
case "$QUERY" in
    select:*)
        # "select:" 뒤를 콤마 분리. 끝에 echo 로 개행 보강(개행 없는 마지막 항목 누락 방지)
        { printf '%s' "${QUERY#select:}" | tr ',' '\n'; echo; } | while IFS= read -r t; do
            t="${t## }"; t="${t%% }"
            [ -n "$t" ] && lt_mark "$SESSION" "$t"
        done
        ;;
esac

# 2) tool_response 안의 "name":"..." 전부 적립 (키워드 검색 결과 포함)
#    tool_response 는 JSON 문자열 내부라 name 이 \"name\" 로 이스케이프될 수 있다.
#    이스케이프(\")와 비이스케이프(") 양쪽 모두 매칭. 도구명만 뽑아 적립.
{ printf '%s' "$INPUT" \
    | grep -oE '\\?"name\\?"[[:space:]]*:[[:space:]]*\\?"[A-Za-z0-9_]+\\?"' \
    | grep -oE '[A-Za-z0-9_]+\\?"$' \
    | sed -E 's/\\?"$//'; echo; } \
    | while IFS= read -r t; do
        [ -n "$t" ] && [ "$t" != "name" ] && lt_mark "$SESSION" "$t"
    done

exit 0
