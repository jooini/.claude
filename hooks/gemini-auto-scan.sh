#!/bin/zsh
# PostToolUse(Bash): 프로젝트 디렉토리 변경 시 Gemini 자동 스캔
# 백그라운드로 Gemini 실행 → 결과를 캐시에 저장 → Claude Code가 읽어서 활용

: "${HOME:?}"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)

if ! echo "$COMMAND" | grep -qE '(^cd |[;&|]\s*cd )'; then
  exit 0
fi

CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)
[ -z "$CWD" ] && exit 0

if ! echo "$CWD" | grep -q '/Workspace/'; then
  exit 0
fi

# 코드 프로젝트 판별
IS_PROJECT=0
for f in pyproject.toml requirements.txt package.json composer.json build.gradle build.gradle.kts pom.xml go.mod Cargo.toml; do
  if [ -f "$CWD/$f" ]; then
    IS_PROJECT=1
    break
  fi
done

if [ "$IS_PROJECT" -eq 0 ]; then
  exit 0
fi

# 세션당 프로젝트별 1회만 실행
STATE_FILE="$HOME/.claude/cache/.gemini-scan-state-$$"
mkdir -p "$HOME/.claude/cache"
LAST_SCANNED=""
[ -f "$STATE_FILE" ] && LAST_SCANNED=$(cat "$STATE_FILE")

if [ "$CWD" = "$LAST_SCANNED" ]; then
  exit 0
fi
echo "$CWD" > "$STATE_FILE"

PROJECT_NAME=$(basename "$CWD")
CACHE_DIR="$HOME/.claude/cache/gemini"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-scan.md"

# 이미 최근 스캔 결과가 있으면 (30분 이내) 재사용
if [ -f "$OUTPUT_FILE" ]; then
  FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
  if [ "$FILE_AGE" -lt 1800 ]; then
    echo "[Gemini] ${PROJECT_NAME} 스캔 결과 캐시됨 → cat ${OUTPUT_FILE}"
    exit 0
  fi
fi

# Gemini 백그라운드 실행
(
  cd "$CWD"
  gemini -p "이 프로젝트의 구조, 주요 파일, 기술 스택, 아키텍처를 요약해줘. 핵심 엔트리포인트와 의존성 관계 중심으로. 한글로 답변." \
    > "$OUTPUT_FILE" 2>/dev/null
) &

echo "[Gemini 스캔 시작] ${PROJECT_NAME} — 백그라운드 실행 중 → 결과: cat ${OUTPUT_FILE}"

exit 0
