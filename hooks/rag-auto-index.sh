#!/bin/zsh
# PostToolUse(Edit|Write): 편집/작성 파일을 local-rag 인덱싱 큐에 적재
#
# 동작 요약:
#   1. tool input의 file_path 추출
#   2. 확장자/경로/크기/제외패턴 필터
#   3. ~/.claude/cache/rag-index-queue.txt 에 절대경로 append (중복 제거)
#   4. 1000줄 초과 시 오래된 것 trim
#
# 한계:
#   - hook은 MCP를 직접 호출 못함 → Claude 세션이 큐를 소비해야 함
#   - 큐 처리 예: cat ~/.claude/cache/rag-index-queue.txt | xargs ...
#   - 본 hook은 비차단(exit 0). additionalContext 출력 없음

: "${HOME:?}"

INPUT=$(cat)

# file_path 추출 (jq 우선, 실패 시 sed fallback — 다른 hook 패턴과 동일)
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
fi
if [ -z "$FILE_PATH" ]; then
    FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# 빈 file_path 무시
[ -z "$FILE_PATH" ] && exit 0

# 실제 파일 존재 확인 (Write 직후엔 존재해야 함)
[ -f "$FILE_PATH" ] || exit 0

# ── 필터 1: 확장자 ─────────────────────────────────────────
case "$FILE_PATH" in
    *.md|*.rs|*.py|*.ts|*.go|*.kt|*.java)
        ;;
    *)
        exit 0
        ;;
esac

# ── 필터 2: 경로 (~/Workspace 또는 ~/.claude 하위만) ─────────
case "$FILE_PATH" in
    "$HOME/Workspace"/*|"$HOME/.claude"/*)
        ;;
    *)
        exit 0
        ;;
esac

# ── 필터 3: 제외 패턴 (.gitignore 관례) ────────────────────
case "$FILE_PATH" in
    */node_modules/*|*/target/*|*/dist/*|*/build/*|*/.venv/*|*/venv/*|*/__pycache__/*|*/.next/*|*/.nuxt/*|*/.cache/*|*/.git/*|*/coverage/*|*/.pytest_cache/*|*/.mypy_cache/*|*/out/*|*/bin/*|*/obj/*)
        exit 0
        ;;
esac

# ── 필터 4: 파일 크기 < 100KB ──────────────────────────────
FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -ge 102400 ]; then
    exit 0
fi
[ "$FILE_SIZE" -eq 0 ] && exit 0

# ── 큐 파일 준비 ──────────────────────────────────────────
QUEUE_DIR="$HOME/.claude/cache"
QUEUE_FILE="$QUEUE_DIR/rag-index-queue.txt"
mkdir -p "$QUEUE_DIR"
[ -f "$QUEUE_FILE" ] || : > "$QUEUE_FILE"

# ── 중복 제거 ─────────────────────────────────────────────
if grep -Fxq "$FILE_PATH" "$QUEUE_FILE" 2>/dev/null; then
    exit 0
fi

# ── 큐에 추가 ─────────────────────────────────────────────
echo "$FILE_PATH" >> "$QUEUE_FILE"

# ── 큐 크기 제한: 1000줄 초과 시 오래된 것 trim ─────────────
LINE_COUNT=$(wc -l < "$QUEUE_FILE" 2>/dev/null | tr -d ' ')
if [ -n "$LINE_COUNT" ] && [ "$LINE_COUNT" -gt 1000 ]; then
    TMP=$(mktemp)
    tail -n 1000 "$QUEUE_FILE" > "$TMP" && mv "$TMP" "$QUEUE_FILE"
fi

exit 0
