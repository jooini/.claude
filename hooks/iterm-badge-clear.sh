#!/bin/bash
# Stop: iTerm2 뱃지 제거 (빈 값으로 SetBadgeFormat)
# - escape sequence는 /dev/tty로 직접 출력
# - iTerm2 환경에서만 동작
# - tmux 안이면 DCS passthrough로 래핑

set -u

[ ! -t 0 ] && cat >/dev/null 2>&1 || true

[ "${TERM_PROGRAM:-}" = "iTerm.app" ] || exit 0

# 부모 체인을 거슬러 올라가며 tty 있는 ancestor 탐지
find_tty() {
    local pid="${1:-$PPID}"
    local depth=0
    while [ "$pid" != "1" ] && [ "$pid" != "0" ] && [ "$depth" -lt 10 ]; do
        local tty ppid
        read -r tty ppid <<<"$(ps -p "$pid" -o tty=,ppid= 2>/dev/null)"
        tty="${tty// /}"
        ppid="${ppid// /}"
        if [ -n "$tty" ] && [ "$tty" != "??" ]; then
            echo "$tty"
            return 0
        fi
        [ -z "$ppid" ] && return 1
        pid="$ppid"
        depth=$((depth + 1))
    done
    return 1
}
PARENT_TTY=$(find_tty "$PPID")
[ -n "$PARENT_TTY" ] || exit 0
TTY_PATH="/dev/$PARENT_TTY"
{ exec 9>"$TTY_PATH"; } 2>/dev/null || exit 0

OSC=$'\033]1337;SetBadgeFormat=\a'

if [ -n "${TMUX:-}" ]; then
    INNER=${OSC//$'\033'/$'\033\033'}
    printf '\033Ptmux;%s\033\\' "$INNER" >&9
else
    printf '%s' "$OSC" >&9
fi

exec 9>&-
exit 0
