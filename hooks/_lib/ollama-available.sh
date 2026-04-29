#!/bin/zsh
# 공통 라이브러리: Ollama 서버 도달 가능 여부 빠른 체크
#
# 사용법 (다른 hook에서):
#   source "$HOME/.claude/hooks/_lib/ollama-available.sh"
#   ollama_available || exit 0
#
# 또는 직접 함수 호출 없이:
#   "$HOME/.claude/hooks/_lib/ollama-available.sh" || exit 0
#
# 동작:
# - 5분 내 캐시된 결과 있으면 그것 사용 (0.001초)
# - 없으면 nc로 TCP 체크 (1초 타임아웃)
# - 결과를 ~/.claude/cache/ollama-available에 캐시
#
# 회사 Wi-Fi 외부에서 hook 호출 시 매번 5-15초 timeout 대기 → 0.05초로 단축

: "${HOME:?}"

OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
CACHE_FILE="$HOME/.claude/cache/ollama-available"
CACHE_TTL=300  # 5분

ollama_available() {
    /bin/mkdir -p "$(/usr/bin/dirname "$CACHE_FILE")"

    # 캐시 신선도 확인
    if [ -f "$CACHE_FILE" ]; then
        local age
        age=$(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
        if [ "$age" -lt "$CACHE_TTL" ]; then
            local cached
            cached=$(/bin/cat "$CACHE_FILE" 2>/dev/null)
            [ "$cached" = "1" ] && return 0
            [ "$cached" = "0" ] && return 1
        fi
    fi

    # 새로 확인 — nc 우선, 실패 시 /dev/tcp fallback
    local available=0
    if /usr/bin/command -v nc >/dev/null 2>&1; then
        if /usr/bin/nc -z -G 1 "$OLLAMA_HOST" "$OLLAMA_PORT" >/dev/null 2>&1; then
            available=1
        fi
    elif (echo > "/dev/tcp/$OLLAMA_HOST/$OLLAMA_PORT") >/dev/null 2>&1; then
        available=1
    fi

    /bin/echo "$available" > "$CACHE_FILE"
    [ "$available" = "1" ] && return 0
    return 1
}

# 직접 실행 시: 결과를 exit code로
if [ "${ZSH_EVAL_CONTEXT:-toplevel}" = "toplevel" ] || [ "${BASH_SOURCE:-$0}" = "$0" ]; then
    ollama_available
    exit $?
fi
