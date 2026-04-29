#!/bin/zsh
# PostToolUse(Agent): 에이전트 사용 로그 기록
# async로 실행 (비차단)

: "${HOME:?}"

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="general-purpose"

LOG_DIR="$HOME/.claude/cache/usage"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
DATE=$(date +"%Y-%m-%d")
LOG_FILE="$LOG_DIR/${DATE}.log"

CWD=$(pwd)
PROJECT=$(basename "${CWD}")

echo "${TIMESTAMP}|agent:${AGENT_TYPE}|${PROJECT}|ok|" >> "$LOG_FILE"

exit 0
