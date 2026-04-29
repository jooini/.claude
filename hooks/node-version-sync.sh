#!/bin/zsh
# SessionStart: nvm default Node 버전과 settings.json PATH 동기화

: "${HOME:?}"

SETTINGS="$HOME/.claude/settings.json"

# nvm default 버전 경로 가져오기
NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] || exit 0

DEFAULT_VERSION=$(cat "$NVM_DIR/alias/default" 2>/dev/null)
[ -z "$DEFAULT_VERSION" ] && exit 0

# 실제 버전 디렉토리 찾기 (alias가 "22" 같은 단축형일 수 있음)
RESOLVED=$(ls -d "$NVM_DIR/versions/node/v${DEFAULT_VERSION}"* 2>/dev/null | sort -V | tail -1)
[ -z "$RESOLVED" ] && exit 0

NODE_BIN="$RESOLVED/bin"
CURRENT_IN_SETTINGS=$(sed -n 's/.*"PATH"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SETTINGS")

# settings.json에 이미 올바른 경로면 스킵
if echo "$CURRENT_IN_SETTINGS" | grep -q "$NODE_BIN"; then
    exit 0
fi

# PATH 값 교체 (기존 nvm 경로를 새 경로로)
NEW_PATH="$NODE_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ -n "$CURRENT_IN_SETTINGS" ]; then
    # 기존 PATH 업데이트
    sed -i '' "s|\"PATH\":.*|\"PATH\": \"$NEW_PATH\"|" "$SETTINGS"
    echo "[Node 동기화] PATH 업데이트: $(basename "$RESOLVED")"
fi

exit 0
