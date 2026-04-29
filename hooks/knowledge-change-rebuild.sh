#!/bin/zsh
# PostToolUse(Edit/Write): knowledge 파일 변경 감지 → 에이전트 빌드 자동 갱신
# exit 0 + stdout = 비차단 리마인더

: "${HOME:?}"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$FILE_PATH" ] && exit 0

# knowledge 디렉토리 내 파일인지 확인
if ! echo "$FILE_PATH" | grep -q "$HOME/.claude/agents/knowledge/"; then
    exit 0
fi

# 현재 활성 빌드 확인
AGENTS_DIR="$HOME/.claude/agents"
BUILD_SCRIPT="$AGENTS_DIR/build-agents.sh"
[ -x "$BUILD_SCRIPT" ] || exit 0

CURRENT_BUILD=""
for f in "$AGENTS_DIR"/*.md; do
    [ -L "$f" ] || continue
    CURRENT_BUILD=$(readlink "$f" | sed -n 's|.*/builds/\([^/]*\)/.*|\1|p')
    break
done

# 변경된 에이전트명 추출 (knowledge/{agent}/...)
CHANGED_AGENT=$(echo "$FILE_PATH" | sed -n "s|.*knowledge/\([^/]*\)/.*|\1|p")

# 리빌드
"$BUILD_SCRIPT" "$CHANGED_AGENT" > /dev/null 2>&1
"$BUILD_SCRIPT" --use "${CURRENT_BUILD:-root}" > /dev/null 2>&1

echo "[Knowledge 리빌드] ${CHANGED_AGENT} knowledge 변경 → ${CURRENT_BUILD:-root} 빌드 갱신됨"

exit 0
