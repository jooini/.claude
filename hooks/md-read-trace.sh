#!/bin/zsh
# PostToolUse(Read): Read tool 호출 → cache/md-live/{date}.jsonl 에 append
# md / workflow / agents / knowledge / skill / memory / CLAUDE.md 등 관심 파일만 기록
#
# 출력 포맷 (JSONL):
#   {"ts_utc":"2026-05-09T10:36:00Z","ts":"2026-05-09T19:36:00","session":"abcd1234",
#    "turn_id":"60a265d8-...","category":"workflow","file":"/Users/.../standard-routines.md"}
#
# 카테고리:
#   workflow / agent / skill / knowledge / memory / claude_md / other
#
# turn_id: transcript_path 의 마지막 user prompt 의 promptId — chains 그래프 조인 키.

: "${HOME:?}"

INPUT=$(cat)

# file_path 추출
FILE_PATH=""
TRANSCRIPT=""
if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
fi
if [ -z "$FILE_PATH" ]; then
    FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -z "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
    *.md|*/CLAUDE.md|*/MEMORY.md|*/skill.md|*/SKILL.md) ;;
    *) exit 0 ;;
esac

SESSION=""
if command -v jq >/dev/null 2>&1; then
    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | cut -c1-8)
fi
if [ -z "$SESSION" ]; then
    SESSION=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]\{1,8\}\).*/\1/p')
fi

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

CATEGORY="other"
case "$FILE_PATH" in
    */CLAUDE.md) CATEGORY="claude_md" ;;
    */MEMORY.md|*/memory/*.md) CATEGORY="memory" ;;
    */workflows/*.md) CATEGORY="workflow" ;;
    */skills/*/skill.md|*/skills/*/SKILL.md|*/skills/*.md) CATEGORY="skill" ;;
    */agents-src/*.md|*/agents/builds/*/*.md|*/agents/*.md) CATEGORY="agent" ;;
    */knowledge/*.md) CATEGORY="knowledge" ;;
esac

LOG_DIR="$HOME/.claude/cache/md-live"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

# UTC + KST 둘 다 기록 (UTC 가 조인용 정공법, KST 는 사람용 표시)
TS_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TS_LOCAL=$(date +"%Y-%m-%dT%H:%M:%S")

printf '{"ts_utc":"%s","ts":"%s","session":"%s","turn_id":"%s","category":"%s","file":"%s"}\n' \
    "$TS_UTC" "$TS_LOCAL" "$SESSION" "$TURN_ID" "$CATEGORY" "$FILE_PATH" >> "$LOG_FILE"

exit 0
