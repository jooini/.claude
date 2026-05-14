#!/bin/zsh
# PostToolUse(Edit|Write): Learning/ 하위 .md 작성 시 RAG 즉시 인덱싱
#
# 동작 요약:
#   1. tool input의 file_path 추출
#   2. Learning/ 하위 .md 파일인지 확인 (그 외는 즉시 종료)
#   3. mcp-local-rag CLI를 backgrounded 로 호출하여 ingest 실행
#   4. 결과는 ~/.claude/cache/learning-rag-ingest.log 에 누적
#
# 설계 결정:
#   - Learning/ 노트는 작고 (수십 KB) 학습 가치가 높아 즉시 인덱싱
#   - 일반 코드 파일은 기존 rag-auto-index.sh 가 큐로 처리 (배치)
#   - hook 자체는 비차단(즉시 exit 0). 실제 ingest 는 백그라운드 nohup
#   - DB/Cache 경로는 ~/.claude/scripts/run-local-rag.sh 와 동일하게 설정
#
# 한계:
#   - npx 가 PATH 에 없으면 동작 안 함 → 절대경로 fallback
#   - 백그라운드 ingest 실패는 로그에만 남음 (사용자에게 알림 X)

: "${HOME:?}"

INPUT=$(cat)

# ── file_path 추출 (jq 우선, sed fallback) ──
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
fi
if [ -z "$FILE_PATH" ]; then
    FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

# ── 필터: Learning/ 하위 .md 만 ──
LEARNING_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Learning"
case "$FILE_PATH" in
    "$LEARNING_DIR"/*.md|"$LEARNING_DIR"/**/*.md)
        ;;
    *)
        exit 0
        ;;
esac

# ── 큐 파일도 무시 (자기 자신을 인덱싱하지 않도록) ──
case "$FILE_PATH" in
    */learning-queue.md|*/dashboard.md)
        exit 0
        ;;
esac

# ── 파일 크기 가드 (1MB 초과 차단) ──
FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -ge 1048576 ] || [ "$FILE_SIZE" -eq 0 ]; then
    exit 0
fi

# ── 로그 디렉토리 ──
LOG_DIR="$HOME/.claude/cache"
LOG_FILE="$LOG_DIR/learning-rag-ingest.log"
mkdir -p "$LOG_DIR"

# ── npx 경로 결정 (PATH fallback) ──
NPX_BIN=""
if command -v npx >/dev/null 2>&1; then
    NPX_BIN=$(command -v npx)
elif [ -x "$HOME/.nvm/versions/node/v22.22.0/bin/npx" ]; then
    NPX_BIN="$HOME/.nvm/versions/node/v22.22.0/bin/npx"
elif [ -x "/opt/homebrew/bin/npx" ]; then
    NPX_BIN="/opt/homebrew/bin/npx"
fi

if [ -z "$NPX_BIN" ]; then
    echo "$(date +%Y-%m-%dT%H:%M:%S) [SKIP] npx not found: $FILE_PATH" >> "$LOG_FILE"
    exit 0
fi

# ── RAG 환경변수 (run-local-rag.sh 와 동일) ──
export BASE_DIR="/Users/leonard/Workspace"
export DB_PATH="/Users/leonard/Workspace/lancedb"
export CACHE_DIR="$HOME/.claude/cache/rag-models"
export MODEL_NAME="Xenova/multilingual-e5-small"

# ── 백그라운드 ingest (블로킹 X) ──
# nohup + & 로 hook 종료 후에도 실행 지속
{
    echo "$(date +%Y-%m-%dT%H:%M:%S) [START] $FILE_PATH"
    nohup "$NPX_BIN" -y mcp-local-rag ingest "$FILE_PATH" >> "$LOG_FILE" 2>&1
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
        echo "$(date +%Y-%m-%dT%H:%M:%S) [OK] $FILE_PATH"
    else
        echo "$(date +%Y-%m-%dT%H:%M:%S) [FAIL exit=$EXIT_CODE] $FILE_PATH"
    fi
} >> "$LOG_FILE" 2>&1 &

# 백그라운드 disown (부모가 죽어도 살아남음)
disown 2>/dev/null || true

# ── 로그 크기 제한 (1MB 초과 시 절반으로 trim) ──
LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
if [ "$LOG_SIZE" -gt 1048576 ]; then
    TMP=$(mktemp)
    tail -n 500 "$LOG_FILE" > "$TMP" && mv "$TMP" "$LOG_FILE"
fi

exit 0
