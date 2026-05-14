#!/bin/zsh
# PostToolUse(Bash|Edit|Write|MultiEdit): 종착 tool 호출 기록
# 출력: ~/.claude/cache/md-live/tool-trace-{date}.jsonl
# 같은 turn_id 로 md-read-trace 와 조인 → 발화→md체인→tool 그래프
#
# 필드:
#   {ts_utc, ts, session, turn_id, tool, target}
#
# target 추출 정책:
#   Bash       → command 의 첫 30자
#   Edit/Write → file_path
#   MultiEdit  → file_path

: "${HOME:?}"

INPUT=$(cat)

# 디버그: 첫 한 번 stdin 덤프 (이후 자동 비활성)
DBG_FLAG="$HOME/.claude/cache/md-live/.dbg-tool-trace-once"
if [ ! -f "$DBG_FLAG" ]; then
    mkdir -p "$(dirname "$DBG_FLAG")"
    echo "$INPUT" > "$HOME/.claude/cache/md-live/.dbg-stdin-tool-trace.json"
    : > "$DBG_FLAG"
fi

TOOL=""
TRANSCRIPT=""
TARGET=""
SESSION=""

if command -v jq >/dev/null 2>&1; then
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | cut -c1-8)
fi
if [ -z "$TOOL" ]; then
    TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -z "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# 관심 도구만
case "$TOOL" in
    Bash|Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

# target 추출
case "$TOOL" in
    Bash)
        if command -v jq >/dev/null 2>&1; then
            TARGET=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr '\n' ' ')
        fi
        if [ -z "$TARGET" ]; then
            TARGET=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        fi
        ;;
    Edit|Write|MultiEdit)
        if command -v jq >/dev/null 2>&1; then
            TARGET=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        fi
        if [ -z "$TARGET" ]; then
            TARGET=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        fi
        ;;
esac

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
LOG_FILE="$LOG_DIR/tool-trace-$(date +%Y-%m-%d).jsonl"

TS_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TS_LOCAL=$(date +"%Y-%m-%dT%H:%M:%S")

# JSON 안전: target 의 따옴표/백슬래시 이스케이프
TARGET_ESC=$(printf '%s' "$TARGET" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{"ts_utc":"%s","ts":"%s","session":"%s","turn_id":"%s","tool":"%s","target":"%s"}\n' \
    "$TS_UTC" "$TS_LOCAL" "$SESSION" "$TURN_ID" "$TOOL" "$TARGET_ESC" >> "$LOG_FILE"

exit 0
