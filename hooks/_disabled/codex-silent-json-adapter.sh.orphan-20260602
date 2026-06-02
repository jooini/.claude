#!/bin/zsh
# Codex hook adapter for Claude-compatible hooks.
#
# Codex parses hook stdout as event JSON. Most Claude hooks in this setup emit
# human-readable reminders, so imported hooks must be side-effect only.

set -u

if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
    shift
fi

[ "$#" -gt 0 ] || exit 0

INPUT=$(cat 2>/dev/null || true)
OUT_FILE=$(/usr/bin/mktemp -t codex-hook-stdout.XXXXXX 2>/dev/null) || exit 0
ERR_FILE=$(/usr/bin/mktemp -t codex-hook-stderr.XXXXXX 2>/dev/null) || {
    rm -f "$OUT_FILE"
    exit 0
}

printf '%s' "$INPUT" | "$@" >"$OUT_FILE" 2>"$ERR_FILE"
STATUS=$?

STDOUT_BYTES=$(wc -c < "$OUT_FILE" 2>/dev/null | tr -d ' ')
STDERR_BYTES=$(wc -c < "$ERR_FILE" 2>/dev/null | tr -d ' ')
: "${STDOUT_BYTES:=0}"
: "${STDERR_BYTES:=0}"

if [ "$STATUS" -ne 0 ] || [ "$STDOUT_BYTES" -gt 0 ] || [ "$STDERR_BYTES" -gt 0 ]; then
    LOG_DIR="${CODEX_HOOK_ADAPTER_LOG_DIR:-$HOME/.claude/cache/codex-hook-adapter}"
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')
    COMMAND_TEXT="$*"
    printf '%s\tstatus=%s\tstdout=%s\tstderr=%s\tcommand=%s\n' \
        "$TS" "$STATUS" "$STDOUT_BYTES" "$STDERR_BYTES" "$COMMAND_TEXT" \
        >> "$LOG_DIR/events.log" 2>/dev/null || true
fi

rm -f "$OUT_FILE" "$ERR_FILE"

if [ "${CODEX_HOOK_ADAPTER_STRICT_EXIT:-0}" = "1" ]; then
    exit "$STATUS"
fi

exit 0
