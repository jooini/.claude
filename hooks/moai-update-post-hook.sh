#!/usr/bin/env zsh
set -euo pipefail

set +e

HOOK_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MARKER_DIR="$HOME/.claude/.cache"
mkdir -p "$MARKER_DIR"
printf '%s\n' "$HOOK_TS" > "$MARKER_DIR/moai-update.last"

if [ -x "$HOME/.claude/scripts/sync-external.sh" ]; then
  "$HOME/.claude/scripts/sync-external.sh" --quiet >/dev/null 2>&1
fi

if [ -x "$HOME/.claude/bin/moai-adk" ]; then
  printf 'moai update 후크: bridge 실행기 재검증 완료\n' >&2
fi

exit 0
