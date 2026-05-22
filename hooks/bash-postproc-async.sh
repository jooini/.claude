#!/bin/zsh
# PostToolUse(Bash) async 통합: 파일 기록만 하는 hook 묶음
#   1) tool-trace          → ~/.claude/cache/md-live/tool-trace-{date}.jsonl
#   2) tool-usage-log      → ~/.claude/cache/usage/{date}.log (gemini/codex)
#
# stdout 출력 없음 (async 안전). exit 0 고정.

: "${HOME:?}"

INPUT=$(cat)

# ---------- 공통 파싱 (jq 1회) ----------
TOOL=""
COMMAND=""
TRANSCRIPT=""
SESSION=""
EXIT_CODE=""
CWD=""
FILE_PATH=""

if command -v jq >/dev/null 2>&1; then
    # 빈 필드 보존 위해 각 필드를 별도 줄로 추출
    TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
    SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null | cut -c1-8)
    EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // ""' 2>/dev/null)
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
fi

# jq 실패 fallback (sed)
if [ -z "$TOOL" ]; then
    TOOL=$(printf '%s' "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -z "$COMMAND" ]; then
    COMMAND=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)
fi
if [ -z "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
if [ -z "$CWD" ]; then
    CWD=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)
fi
if [ -z "$FILE_PATH" ]; then
    FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# ========== 1) tool-trace ==========
case "$TOOL" in
    Bash|Edit|Write|MultiEdit)
        case "$TOOL" in
            Bash)
                # 멀티라인 command → 단일 줄 (JSONL 한 줄 보장)
                TARGET=$(printf '%s' "$COMMAND" | tr '\n' ' ')
                ;;
            Edit|Write|MultiEdit)
                TARGET=$FILE_PATH
                ;;
        esac

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
            except Exception:
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

        TRACE_DIR="$HOME/.claude/cache/md-live"
        mkdir -p "$TRACE_DIR"
        TRACE_FILE="$TRACE_DIR/tool-trace-$(date +%Y-%m-%d).jsonl"
        TS_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        TS_LOCAL=$(date +"%Y-%m-%dT%H:%M:%S")
        TARGET_ESC=$(printf '%s' "$TARGET" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"ts_utc":"%s","ts":"%s","session":"%s","turn_id":"%s","tool":"%s","target":"%s"}\n' \
            "$TS_UTC" "$TS_LOCAL" "$SESSION" "$TURN_ID" "$TOOL" "$TARGET_ESC" >> "$TRACE_FILE"
        ;;
esac

# ========== 2) tool-usage-log (Bash 전용, gemini/codex CLI 감지) ==========
if [ "$TOOL" = "Bash" ] && [ -n "$COMMAND" ]; then
    USAGE_TOOL=""
    USAGE_ACTION=""

    if echo "$COMMAND" | grep -qE '(^(gemini|agy) |/(gemini|agy) )'; then
        # 2026-06-18 이후 agy(Antigravity)가 gemini 후속 — 별도 도구로 카운트
        if echo "$COMMAND" | grep -qE '(^agy |/agy )'; then
            USAGE_TOOL="agy"
        else
            USAGE_TOOL="gemini"
        fi
        if echo "$COMMAND" | grep -qE '\-p|--print|--prompt'; then
            USAGE_ACTION=$(echo "$COMMAND" | sed -n 's/.*-p[[:space:]]*"\?\([^"]*\).*/\1/p' | head -c 50)
        else
            USAGE_ACTION="interactive"
        fi
    elif echo "$COMMAND" | grep -qE '(^codex |/codex )'; then
        USAGE_TOOL="codex"
        if echo "$COMMAND" | grep -q '\-a'; then
            USAGE_ACTION=$(echo "$COMMAND" | sed -n 's/.*-a[[:space:]]*"\?\([^"]*\).*/\1/p' | head -c 50)
        else
            USAGE_ACTION="interactive"
        fi
    fi

    if [ -n "$USAGE_TOOL" ]; then
        USAGE_DIR="$HOME/.claude/cache/usage"
        mkdir -p "$USAGE_DIR"
        USAGE_FILE="$USAGE_DIR/$(date +%Y-%m-%d).log"
        PROJECT=$(basename "${CWD:-unknown}")
        STATUS="ok"
        [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ] && STATUS="fail"
        TS=$(date +"%Y-%m-%d %H:%M:%S")
        echo "${TS}|${USAGE_TOOL}|${PROJECT}|${STATUS}|${USAGE_ACTION}" >> "$USAGE_FILE"
    fi
fi

exit 0
