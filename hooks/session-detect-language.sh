#!/bin/zsh
# SessionStart: CWD의 프로젝트 언어/스택을 감지하여 컨텍스트로 출력 + 빌드 전환
# exit 0 + stdout = 비차단 리마인더

: "${HOME:?}"

source "$(dirname "$0")/lib-detect-language.sh"

CWD="$(pwd)"
detect_language "$CWD"

PROJECT_NAME=$(basename "$CWD")
AGENTS_DIR="$HOME/.claude/agents"
BUILD_SCRIPT="$AGENTS_DIR/build-agents.sh"

if [ -n "$DETECTED" ]; then
    if [ -n "$FRAMEWORK" ]; then
        echo "[프로젝트 감지] ${PROJECT_NAME}: ${DETECTED} (${FRAMEWORK})${DOCKER} — 에이전트 스킬/knowledge 참조 시 이 스택 기준으로 선택할 것"
    else
        echo "[프로젝트 감지] ${PROJECT_NAME}: ${DETECTED}${DOCKER} — 에이전트 스킬/knowledge 참조 시 이 스택 기준으로 선택할 것"
    fi

    # 언어→빌드명 매핑 → 빌드 전환
    LANG_MAP=""
    case "$DETECTED" in
        Python)     LANG_MAP="python" ;;
        Kotlin|Java) LANG_MAP="kotlin" ;;
        PHP)        LANG_MAP="php" ;;
        TypeScript|JavaScript) LANG_MAP="nodejs" ;;
    esac

    if [ -n "$LANG_MAP" ] && [ -d "$AGENTS_DIR/builds/$LANG_MAP" ] && [ -x "$BUILD_SCRIPT" ]; then
        CURRENT_BUILD=""
        for f in "$AGENTS_DIR"/*.md; do
            [ -L "$f" ] || continue
            CURRENT_BUILD=$(readlink "$f" | sed -n 's|.*/builds/\([^/]*\)/.*|\1|p')
            break
        done
        if [ "$CURRENT_BUILD" != "$LANG_MAP" ]; then
            "$BUILD_SCRIPT" --use "$LANG_MAP" > /dev/null 2>&1
        fi
    fi
else
    if [ -d "$CWD" ] && find "$CWD" -maxdepth 2 \( -name "pyproject.toml" -o -name "package.json" -o -name "composer.json" -o -name "build.gradle*" -o -name "settings.gradle*" \) 2>/dev/null | head -1 | grep -q .; then
        echo "[프로젝트 감지] ${PROJECT_NAME}: 다중 프로젝트 워크스페이스 — 하위 프로젝트 진입 시 해당 스택 기준 적용"
    fi
fi

exit 0
