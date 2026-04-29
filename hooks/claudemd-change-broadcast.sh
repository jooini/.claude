#!/bin/zsh
# PostToolUse(Edit/Write): Claude 설정 파일 변경 감지 → 다른 세션 알림
# CLAUDE.md / AGENT.md / settings.json / hooks/ / skills/ / agents/ 변경 시
# stdout 비차단 알림 + cache 로그 append

: "${HOME:?}"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

MATCHED=0
SCOPE=""
PATTERN=""

# 1) CLAUDE.md / AGENT.md / AGENTS.md (전역+프로젝트)
case "$FILE_PATH" in
  */CLAUDE.md)
    MATCHED=1; PATTERN="CLAUDE.md"
    case "$FILE_PATH" in
      "$HOME/.claude/"*) SCOPE="전역" ;;
      *) SCOPE="프로젝트" ;;
    esac
    ;;
  */AGENT.md|*/AGENTS.md)
    MATCHED=1; PATTERN="AGENT(S).md"
    case "$FILE_PATH" in
      "$HOME/.claude/"*) SCOPE="전역" ;;
      *) SCOPE="프로젝트" ;;
    esac
    ;;
esac

# 2) ~/.claude/settings.json (전역)
if [ "$MATCHED" -eq 0 ] && [ "$FILE_PATH" = "$HOME/.claude/settings.json" ]; then
  MATCHED=1; PATTERN="settings.json"; SCOPE="전역"
fi

# 3) ~/.claude/hooks/*.sh (전역)
if [ "$MATCHED" -eq 0 ]; then
  case "$FILE_PATH" in
    "$HOME/.claude/hooks/"*.sh)
      MATCHED=1; PATTERN="hooks/*.sh"; SCOPE="전역"
      ;;
  esac
fi

# 4) ~/.claude/skills/**/*.md (전역)
if [ "$MATCHED" -eq 0 ]; then
  case "$FILE_PATH" in
    "$HOME/.claude/skills/"*.md)
      MATCHED=1; PATTERN="skills/**/*.md"; SCOPE="전역"
      ;;
  esac
fi

# 5) ~/.claude/agents/*.md (전역)
if [ "$MATCHED" -eq 0 ]; then
  case "$FILE_PATH" in
    "$HOME/.claude/agents/"*.md)
      MATCHED=1; PATTERN="agents/*.md"; SCOPE="전역"
      ;;
  esac
fi

if [ "$MATCHED" -eq 0 ]; then
  exit 0
fi

# stdout 알림 (비차단)
echo "⚠ Claude 설정 변경: ${FILE_PATH}"
echo "  영향 범위: ${SCOPE}"
echo "  다른 활성 세션은 /reload 또는 재시작 시 반영됩니다."

# cache 로그 append
LOG_DIR="$HOME/.claude/cache"
LOG_FILE="$LOG_DIR/config-changes.log"
mkdir -p "$LOG_DIR"
TS=$(date '+%Y-%m-%d %H:%M:%S')
echo "${TS} | ${PATTERN} | ${SCOPE} | ${FILE_PATH}" >> "$LOG_FILE"

exit 0
