#!/bin/zsh
# PostToolUse(Agent): 파이프라인 메트릭 기록
# 에이전트 실행 시간/성공여부/프로젝트별 분포 측정용
# 비동기 비차단 — 실패해도 파이프라인 영향 없음

: "${HOME:?}"

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="general-purpose"

DURATION_MS=$(echo "$INPUT" | sed -n 's/.*"duration_ms"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
[ -z "$DURATION_MS" ] && DURATION_MS="0"

EXIT_CODE=$(echo "$INPUT" | sed -n 's/.*"exit_code"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
STATUS="ok"
[ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ] && STATUS="fail"

DESC=$(echo "$INPUT" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -c 80)

METRICS_DIR="$HOME/.claude/cache/metrics"
mkdir -p "$METRICS_DIR"

DATE=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S")
METRICS_FILE="$METRICS_DIR/${DATE}.tsv"

if [ ! -f "$METRICS_FILE" ]; then
    echo -e "timestamp\tagent\tproject\tstatus\tduration_ms\tdescription" > "$METRICS_FILE"
fi

CWD=$(pwd)
PROJECT=$(basename "${CWD}")

printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TIMESTAMP" "$AGENT_TYPE" "$PROJECT" "$STATUS" "$DURATION_MS" "$DESC" \
    >> "$METRICS_FILE"

exit 0
