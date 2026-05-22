#!/bin/zsh
# PreToolUse(Edit/Write): 의존성 파일 변경 감지 → Gemini 비동기 영향 분석
# 사용자 즉시 응답 (대기 X). 결과는 백그라운드로 ~/.claude/cache/gemini/{project}-deps.md 에 저장.
#
# 변경 이력:
#   2026-05-09: 동기 90초 대기 → 비동기 백그라운드 (사용자 체감 0ms)
#     이유: Gemini API 응답 90초가 사용자 PreToolUse 대기를 그대로 막음

: "${HOME:?}"

GEM_CLI="${GEMINI_CLI:-}"
if [ -z "$GEM_CLI" ]; then
    if command -v agy >/dev/null 2>&1; then GEM_CLI=agy
    elif command -v gemini >/dev/null 2>&1; then GEM_CLI=gemini
    else exit 0
    fi
fi

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

FILENAME=$(basename "$FILE_PATH")
PROJECT_DIR=$(dirname "$FILE_PATH")
IS_DEPENDENCY=0
DEP_TYPE=""

case "$FILENAME" in
  requirements.txt|requirements-*.txt|constraints.txt)
    IS_DEPENDENCY=1; DEP_TYPE="Python 의존성";;
  pyproject.toml)
    IS_DEPENDENCY=1; DEP_TYPE="Python 프로젝트 설정/의존성";;
  package.json)
    IS_DEPENDENCY=1; DEP_TYPE="Node.js 의존성";;
  package-lock.json|yarn.lock|pnpm-lock.yaml)
    IS_DEPENDENCY=1; DEP_TYPE="Node.js lock 파일";;
  composer.json|composer.lock)
    IS_DEPENDENCY=1; DEP_TYPE="PHP 의존성";;
  build.gradle|build.gradle.kts)
    IS_DEPENDENCY=1; DEP_TYPE="Gradle 의존성";;
  pom.xml)
    IS_DEPENDENCY=1; DEP_TYPE="Maven 의존성";;
  go.mod|go.sum)
    IS_DEPENDENCY=1; DEP_TYPE="Go 의존성";;
  Cargo.toml|Cargo.lock)
    IS_DEPENDENCY=1; DEP_TYPE="Rust 의존성";;
  Gemfile|Gemfile.lock)
    IS_DEPENDENCY=1; DEP_TYPE="Ruby 의존성";;
esac

if [ "$IS_DEPENDENCY" -eq 0 ]; then
  exit 0
fi

# 프로젝트 루트 탐색
SEARCH_DIR="$PROJECT_DIR"
for i in 1 2 3; do
  if [ -f "$SEARCH_DIR/.git/config" ] || [ -f "$SEARCH_DIR/pyproject.toml" ] || [ -f "$SEARCH_DIR/package.json" ]; then
    break
  fi
  SEARCH_DIR=$(dirname "$SEARCH_DIR")
done

PROJECT_NAME=$(basename "$SEARCH_DIR")
mkdir -p "$HOME/.claude/cache/gemini"
OUTPUT_FILE="$HOME/.claude/cache/gemini/${PROJECT_NAME}-deps.md"

# 사용자 즉시 알림 (백그라운드 분석 시작)
echo "[Gemini 의존성 분석 백그라운드 시작] ${DEP_TYPE} 변경: ${FILENAME}"
echo "  결과: ${OUTPUT_FILE}"
echo "  완료 후 \`/usage\` 또는 직접 Read 로 확인"

# Gemini 백그라운드 실행 (timeout 30초, fire-and-forget)
# 30초 안에 안 끝나면 분석 가치 없음 + 백그라운드 점유 방지
(
  cd "$SEARCH_DIR" 2>/dev/null || cd "$PROJECT_DIR"
  RESULT=$(timeout 30 "$GEM_CLI" -p "의존성 파일 '${FILENAME}'이 변경되었다. 이 변경이 프로젝트에 미치는 영향을 분석해줘: 1) 추가/제거/변경된 패키지 2) 영향받는 import/코드 3) 잠재적 호환성 이슈. 한글로 답변." 2>/dev/null)

  if [ -n "$RESULT" ]; then
    {
      echo "# Gemini 의존성 분석: ${FILENAME}"
      echo ""
      echo "- 분석 시각: $(date '+%Y-%m-%d %H:%M:%S')"
      echo "- 의존성 타입: ${DEP_TYPE}"
      echo "- 프로젝트: ${PROJECT_NAME}"
      echo ""
      echo "---"
      echo ""
      echo "$RESULT"
    } > "$OUTPUT_FILE"

    # macOS 알림 (선택)
    osascript -e "display notification \"${FILENAME} 영향 분석 완료\" with title \"📦 Gemini 의존성 분석\"" 2>/dev/null
  else
    echo "[Gemini 분석 실패/타임아웃] $(date '+%Y-%m-%d %H:%M:%S') ${FILENAME}" > "$OUTPUT_FILE"
  fi
) &
disown 2>/dev/null

exit 0
