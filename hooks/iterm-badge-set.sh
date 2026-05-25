#!/bin/bash
# SessionStart: iTerm2 뱃지에 현재 작업 디렉토리(basename) 표시
# - escape sequence는 /dev/tty로 직접 출력 (stdout은 Claude 컨텍스트로 주입됨)
# - iTerm2 환경에서만 동작 (TERM_PROGRAM 가드)
# - tmux 안이면 DCS passthrough로 래핑

set -u

# stdin drain (Claude Code hook 규약: stdin 무시해도 OK)
[ ! -t 0 ] && cat >/dev/null 2>&1 || true

# iTerm2 외 터미널은 종료 (Terminal.app, Ghostty 등에서 garbage 방지)
[ "${TERM_PROGRAM:-}" = "iTerm.app" ] || exit 0

# /dev/tty 열기 가능 여부 사전 점검 (Bash tool 등 비대화형 환경에서 silent skip)
{ exec 9>/dev/tty; } 2>/dev/null || exit 0

# 뱃지 텍스트: stdin JSON의 cwd 우선, 없으면 PWD
CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
BADGE_TEXT=$(basename "$CWD")

# iTerm2는 SetBadgeFormat 값을 base64로 받음
BADGE_B64=$(printf '%s' "$BADGE_TEXT" | /usr/bin/base64 | /usr/bin/tr -d '\n')

# OSC 1337 sequence
OSC=$'\033]1337;SetBadgeFormat='"$BADGE_B64"$'\a'

if [ -n "${TMUX:-}" ]; then
    # tmux DCS passthrough: ESC P tmux; ESC <inner ESC를 doubled> ESC \
    INNER=${OSC//$'\033'/$'\033\033'}
    printf '\033Ptmux;%s\033\\' "$INNER" >&9
else
    printf '%s' "$OSC" >&9
fi

exec 9>&-
exit 0
