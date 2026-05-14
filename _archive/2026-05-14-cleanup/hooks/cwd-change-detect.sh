#!/bin/zsh
# PostToolUse(Bash): cd 명령 실행 후 CWD 변경 감지 → 언어 재감지 + 에이전트 빌드 전환
# exit 0 + stdout = 비차단 리마인더

: "${HOME:?}"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)

if ! echo "$COMMAND" | grep -qE '(^cd |[;&|]\s*cd )'; then
    exit 0
fi

CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)
[ -z "$CWD" ] && exit 0

# 중복 출력 방지
STATE_FILE="/tmp/.claude-cwd-lang-$$"
LAST_CWD=""
[ -f "$STATE_FILE" ] && LAST_CWD=$(cat "$STATE_FILE")

if [ "$CWD" = "$LAST_CWD" ]; then
    exit 0
fi
echo "$CWD" > "$STATE_FILE"

source "$(dirname "$0")/lib-detect-language.sh"
detect_language "$CWD"

PROJECT_NAME=$(basename "$CWD")

AGENTS_DIR="$HOME/.claude/agents"
BUILD_SCRIPT="$AGENTS_DIR/build-agents.sh"

# 현재 활성 빌드 확인 (공통)
get_current_build() {
    for f in "$AGENTS_DIR"/*.md; do
        [ -L "$f" ] || continue
        readlink "$f" | sed -n 's|.*/builds/\([^/]*\)/.*|\1|p'
        return
    done
}

if [ -n "$DETECTED" ]; then
    if [ -n "$FRAMEWORK" ]; then
        echo "[프로젝트 전환] ${PROJECT_NAME}: ${DETECTED} (${FRAMEWORK})${DOCKER} — 스킬/knowledge를 이 스택 기준으로 전환"
    else
        echo "[프로젝트 전환] ${PROJECT_NAME}: ${DETECTED}${DOCKER} — 스킬/knowledge를 이 스택 기준으로 전환"
    fi

    # 언어→빌드명 매핑
    LANG_MAP=""
    case "$DETECTED" in
        Python)     LANG_MAP="python" ;;
        Kotlin|Java) LANG_MAP="kotlin" ;;
        PHP)        LANG_MAP="php" ;;
        TypeScript|JavaScript) LANG_MAP="nodejs" ;;
    esac

    # 해당 언어 빌드가 있으면 전환
    if [ -n "$LANG_MAP" ] && [ -d "$AGENTS_DIR/builds/$LANG_MAP" ] && [ -x "$BUILD_SCRIPT" ]; then
        CURRENT_BUILD=$(get_current_build)
        if [ "$CURRENT_BUILD" != "$LANG_MAP" ]; then
            "$BUILD_SCRIPT" --use "$LANG_MAP" > /dev/null 2>&1
            echo "[에이전트 빌드 전환] ${CURRENT_BUILD:-root} → ${LANG_MAP} (${DETECTED} knowledge 포함)"
        fi
    fi
else
    # 언어 미감지 (Workspace 루트 등) → root 빌드로 복원
    if [ -x "$BUILD_SCRIPT" ] && [ -d "$AGENTS_DIR/builds/root" ]; then
        CURRENT_BUILD=$(get_current_build)
        if [ "$CURRENT_BUILD" != "root" ]; then
            "$BUILD_SCRIPT" --use root > /dev/null 2>&1
            echo "[에이전트 빌드 복원] ${CURRENT_BUILD} → root"
        fi
    fi
fi

exit 0
