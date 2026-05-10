#!/usr/bin/env bash
# Workspace Console: 매일 첫 SessionStart에서 vitality sweep 자동 실행.
# 같은 날 두 번째 이상 SessionStart에서는 즉시 종료.
# 동작: ~/Workspace/weaversbrain/weaversbrain/Reports/YYYY-MM/YYYY-MM-DD-vitality-sweep.json
# 등록: settings.json SessionStart 항목 (사용자 결정 영역).
set -euo pipefail

TODAY=$(date +%Y-%m-%d)
LAST_FILE=~/.claude/console/.last-sweep
LAST=$(cat "$LAST_FILE" 2>/dev/null || echo "")

[ "$LAST" = "$TODAY" ] && exit 0

VENV=~/.claude/console/.venv/bin/activate
[ -f "$VENV" ] || exit 0

# shellcheck disable=SC1090
source "$VENV"
command -v wsq >/dev/null 2>&1 || exit 0

MONTH_DIR=~/Workspace/weaversbrain/weaversbrain/Reports/$(date +%Y-%m)
mkdir -p "$MONTH_DIR"
OUT="$MONTH_DIR/$TODAY-vitality-sweep.json"

# 백그라운드 실행 — SessionStart latency 0
nohup wsq sweep --out "$OUT" >/dev/null 2>&1 &

echo "$TODAY" > "$LAST_FILE"
exit 0
