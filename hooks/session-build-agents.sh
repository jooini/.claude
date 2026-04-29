#!/bin/zsh
# SessionStart: root 빌드가 활성 상태인지 확인하고, 없으면 빌드
# 런타임 언어 감지 도입으로 root 빌드만 유지하면 됨

AGENTS_DIR="$HOME/.claude/agents"
BUILD_SCRIPT="$AGENTS_DIR/build-agents.sh"
ROOT_BUILD="$AGENTS_DIR/builds/root"

[ -x "$BUILD_SCRIPT" ] || exit 0

# root 빌드가 없으면 빌드
if [ ! -d "$ROOT_BUILD" ] || [ -z "$(ls "$ROOT_BUILD"/*.md 2>/dev/null)" ]; then
  "$BUILD_SCRIPT" > /dev/null 2>&1
  exit 0
fi

# symlink가 root를 가리키는지 확인
for f in "$AGENTS_DIR"/*.md; do
  [ -L "$f" ] || continue
  TARGET=$(readlink "$f")
  if echo "$TARGET" | grep -q "builds/root/"; then
    exit 0  # root 활성 상태
  fi
  break
done

# root가 아니면 전환
"$BUILD_SCRIPT" --use root > /dev/null 2>&1
exit 0
