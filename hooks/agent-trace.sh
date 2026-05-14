#!/bin/zsh
# PostToolUse(Agent): 에이전트 호출 → cache/md-live/agent-trace-{date}.jsonl
# 같은 turn_id 로 md-read-trace / tool-trace 와 조인 → 그래프에 agent 노드 표시
#
# 출력 포맷:
#   {ts_utc, ts, session, turn_id, agent, description}

: "${HOME:?}"

INPUT=$(cat)

AGENT_TYPE=""
DESCRIPTION=""
TRANSCRIPT=""
SESSION=""

if command -v jq >/dev/null 2>&1; then
    AGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
    DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null | tr '\n' ' ')
    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | cut -c1-8)
fi
if [ -z "$AGENT_TYPE" ]; then
    AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION=$(echo "$INPUT" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr '\n' ' ')
fi
if [ -z "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -z "$SESSION" ]; then
    SESSION=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]\{1,8\}\).*/\1/p')
fi

[ -z "$AGENT_TYPE" ] && AGENT_TYPE="general-purpose"

# turn_id = transcript 마지막 user prompt 의 promptId
TURN_ID=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TURN_ID=$(/usr/bin/python3 - "$TRANSCRIPT" <<'PYEOF' 2>/dev/null
import json, sys
path = sys.argv[1]
last_pid = ""
try:
    with open(path) as f:
        for ln in f:
            try:
                d = json.loads(ln)
            except:
                continue
            if d.get("type") == "user" and "toolUseResult" not in d:
                msg = d.get("message", {})
                if isinstance(msg, dict) and isinstance(msg.get("content"), str):
                    pid = d.get("promptId")
                    if pid:
                        last_pid = pid
except Exception:
    pass
print(last_pid)
PYEOF
)
fi

LOG_DIR="$HOME/.claude/cache/md-live"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/agent-trace-$(date +%Y-%m-%d).jsonl"

TS_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TS_LOCAL=$(date +"%Y-%m-%dT%H:%M:%S")

DESC_ESC=$(printf '%s' "$DESCRIPTION" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{"ts_utc":"%s","ts":"%s","session":"%s","turn_id":"%s","agent":"%s","description":"%s"}\n' \
    "$TS_UTC" "$TS_LOCAL" "$SESSION" "$TURN_ID" "$AGENT_TYPE" "$DESC_ESC" >> "$LOG_FILE"

exit 0
