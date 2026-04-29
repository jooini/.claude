#!/bin/zsh
# PreToolUse(Edit/Write): 의존성 파일 변경 감지 → Gemini 동기 영향 분석
# Gemini 완료까지 대기 → 결과를 stdout으로 Claude Code에 전달

: "${HOME:?}"

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

echo "[Gemini 의존성 분석 중] ${DEP_TYPE} 변경: ${FILENAME} — 완료까지 대기..."

# Gemini 동기 실행 (타임아웃 90초)
cd "$SEARCH_DIR" 2>/dev/null || cd "$PROJECT_DIR"
RESULT=$(timeout 90 gemini -p "의존성 파일 '${FILENAME}'이 변경되었다. 이 변경이 프로젝트에 미치는 영향을 분석해줘: 1) 추가/제거/변경된 패키지 2) 영향받는 import/코드 3) 잠재적 호환성 이슈. 한글로 답변." 2>/dev/null)

if [ -n "$RESULT" ]; then
  echo "$RESULT" > "$OUTPUT_FILE"
  echo "[Gemini 의존성 분석 완료] ${DEP_TYPE}: ${FILENAME}"
  echo "---"
  echo "$RESULT"
else
  echo "[Gemini 의존성 분석 실패/타임아웃] ${FILENAME} — 수동 확인 필요"
fi

exit 0
