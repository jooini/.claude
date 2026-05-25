#!/bin/bash
# Stop: iTerm2 뱃지 제거 (빈 값으로 SetBadgeFormat)
# - escape sequence는 /dev/tty로 직접 출력
# - iTerm2 환경에서만 동작
# - tmux 안이면 DCS passthrough로 래핑

set -u

[ ! -t 0 ] && cat >/dev/null 2>&1 || true

[ "${TERM_PROGRAM:-}" = "iTerm.app" ] || exit 0

{ exec 9>/dev/tty; } 2>/dev/null || exit 0

OSC=$'\033]1337;SetBadgeFormat=\a'

if [ -n "${TMUX:-}" ]; then
    INNER=${OSC//$'\033'/$'\033\033'}
    printf '\033Ptmux;%s\033\\' "$INNER" >&9
else
    printf '%s' "$OSC" >&9
fi

exec 9>&-
exit 0
