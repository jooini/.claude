#!/bin/zsh
# PostToolUse(Bash): Gemini/Codex 사용 로그 기록
# async로 실행 (비차단)

: "${HOME:?}"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)
EXIT_CODE=$(echo "$INPUT" | sed -n 's/.*"exit_code"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)

LOG_DIR="$HOME/.claude/cache/usage"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
DATE=$(date +"%Y-%m-%d")
LOG_FILE="$LOG_DIR/${DATE}.log"

TOOL=""
ACTION=""

# Gemini 사용 감지
if echo "$COMMAND" | grep -qE '(^gemini |/gemini )'; then
    TOOL="gemini"
    if echo "$COMMAND" | grep -q '\-p'; then
        # -p 뒤의 첫 단어들로 액션 추출
        ACTION=$(echo "$COMMAND" | sed -n 's/.*-p[[:space:]]*"\?\([^"]*\).*/\1/p' | head -c 50)
    else
        ACTION="interactive"
    fi
fi

# Codex 사용 감지
if echo "$COMMAND" | grep -qE '(^codex |/codex )'; then
    TOOL="codex"
    if echo "$COMMAND" | grep -q '\-a'; then
        ACTION=$(echo "$COMMAND" | sed -n 's/.*-a[[:space:]]*"\?\([^"]*\).*/\1/p' | head -c 50)
    else
        ACTION="interactive"
    fi
fi

# 로그 기록
if [ -n "$TOOL" ]; then
    PROJECT=$(basename "${CWD:-unknown}")
    STATUS="ok"
    [ "$EXIT_CODE" != "0" ] && [ -n "$EXIT_CODE" ] && STATUS="fail"
    echo "${TIMESTAMP}|${TOOL}|${PROJECT}|${STATUS}|${ACTION}" >> "$LOG_FILE"
fi

exit 0
