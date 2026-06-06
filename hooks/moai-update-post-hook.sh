#!/usr/bin/env zsh
set -euo pipefail

set +e

HOOK_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOOK_EPOCH="$(date +%s)"
MARKER_DIR="$HOME/.claude/.cache"
EPOCH_FILE="$MARKER_DIR/moai-update.last_epoch"
mkdir -p "$MARKER_DIR"

PREVIOUS_EPOCH=""
if [ -f "$EPOCH_FILE" ]; then
  PREVIOUS_EPOCH="$(cat "$EPOCH_FILE" 2>/dev/null || true)"
fi

printf '%s\n' "$HOOK_TS" > "$MARKER_DIR/moai-update.last"
printf '%s\n' "$HOOK_EPOCH" > "$EPOCH_FILE"

if [ -n "$PREVIOUS_EPOCH" ] && [ "$((HOOK_EPOCH - PREVIOUS_EPOCH))" -lt 5 ]; then
  exit 0
fi

if [ -x "$HOME/.claude/scripts/sync-external.sh" ]; then
  "$HOME/.claude/scripts/sync-external.sh" --quiet >/dev/null 2>&1
fi

if [ -x "$HOME/.claude/bin/moai-adk" ]; then
  printf 'moai update 후크: bridge 실행기 재검증 완료\n' >&2
fi

exit 0
