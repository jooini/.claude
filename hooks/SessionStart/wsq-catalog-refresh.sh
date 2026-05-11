#!/usr/bin/env bash
# Workspace Console: SessionStart 마다 quick refresh.
# - hooks/skills/agents/commands 만 재인덱싱 (1초 미만)
# - repos 는 별도 (wsq sweep / wsq refresh --no-quick)
#
# settings.json 등록은 사용자 결정 영역 (이 파일은 스크립트만 제공).
# 등록 예시:
#   "SessionStart": [
#     {"hooks": [{"command": "$HOME/.claude/hooks/SessionStart/wsq-catalog-refresh.sh"}]}
#   ]
set -euo pipefail

VENV="$HOME/Workspace/claude-harness/.venv/bin/activate"
[ -f "$VENV" ] || exit 0

# shellcheck disable=SC1090
source "$VENV"
command -v wsq >/dev/null 2>&1 || exit 0

# 백그라운드 실행 — SessionStart latency 0
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
nohup wsq refresh >>"$LOG_DIR/wsq-catalog-refresh.log" 2>&1 &

exit 0
