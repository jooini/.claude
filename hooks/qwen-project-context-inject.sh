#!/bin/zsh
# SessionStart: cwd가 ~/Workspace/<project>/ 패턴이면 그 프로젝트의
# 최근 7일 컨텍스트(결정/학습/세션) 파일 경로를 stdout에 표시.
#
# - additionalContext 주입 안 함 (사용자가 필요할 때만 Read)
# - Ollama 호출 안 함
# - 매칭 0건이면 조용히 exit 0
# - 파일 시스템 접근 실패 시 exit 0

: "${HOME:?}"

CWD="$(pwd 2>/dev/null)"
[ -z "$CWD" ] && exit 0

WORKSPACE="$HOME/Workspace"

# ~/Workspace/<project>/... 형태인지 확인
case "$CWD" in
    "$WORKSPACE"/*) : ;;
    *) exit 0 ;;
esac

# WORKSPACE 바로 아래 첫 번째 디렉토리명 추출
REL="${CWD#$WORKSPACE/}"
PROJECT_NAME="${REL%%/*}"

# 빈 문자열이면 (cwd가 Workspace 자체) 종료
[ -z "$PROJECT_NAME" ] && exit 0

VAULT="$HOME/Workspace/weaversbrain/weaversbrain"

# Vault 접근 불가능하면 종료
[ -d "$VAULT" ] || exit 0

# 7일 이내 파일을 mtime 내림차순으로 정렬해 상위 N개 반환
list_recent() {
    local dir="$1"
    local pattern="$2"
    local limit="$3"

    [ -d "$dir" ] || return 0

    /usr/bin/find "$dir" -type f -name "$pattern" -mtime -7 -print0 2>/dev/null \
        | /usr/bin/xargs -0 /usr/bin/stat -f "%m %N" 2>/dev/null \
        | /usr/bin/sort -rn \
        | /usr/bin/head -n "$limit" \
        | /usr/bin/cut -d' ' -f2-
}

# Learning 폴더에서 PROJECT_NAME 언급된 파일 (grep -l), 7일 이내, 상위 3개
list_learning_mentions() {
    local dir="$VAULT/Learning"
    local proj="$1"
    local limit="$2"

    [ -d "$dir" ] || return 0

    /usr/bin/find "$dir" -type f -name "*.md" -mtime -7 -print0 2>/dev/null \
        | /usr/bin/xargs -0 /usr/bin/grep -l -F "$proj" 2>/dev/null \
        | while IFS= read -r f; do
            /usr/bin/stat -f "%m %N" "$f" 2>/dev/null
          done \
        | /usr/bin/sort -rn \
        | /usr/bin/head -n "$limit" \
        | /usr/bin/cut -d' ' -f2-
}

DECISIONS=$(list_recent "$VAULT/Decisions" "*${PROJECT_NAME}*.md" 3)
LEARNING=$(list_learning_mentions "$PROJECT_NAME" 3)

# Sessions/2026-MM/ 모든 월 폴더 순회 (현재 연도 기준 패턴)
SESSIONS=""
if [ -d "$VAULT/Sessions" ]; then
    SESSIONS=$(/usr/bin/find "$VAULT/Sessions" -type d -name "2026-*" 2>/dev/null \
        | while IFS= read -r d; do
            list_recent "$d" "*${PROJECT_NAME}*.md" 3
          done \
        | while IFS= read -r f; do
            [ -n "$f" ] && /usr/bin/stat -f "%m %N" "$f" 2>/dev/null
          done \
        | /usr/bin/sort -rn \
        | /usr/bin/head -n 3 \
        | /usr/bin/cut -d' ' -f2-)
fi

# 매칭 0건이면 조용히 종료
if [ -z "$DECISIONS" ] && [ -z "$LEARNING" ] && [ -z "$SESSIONS" ]; then
    exit 0
fi

# 파일 한 줄 포맷: "YYYY-MM-DD — basename"
format_line() {
    local f="$1"
    local mtime
    mtime=$(/usr/bin/stat -f "%Sm" -t "%Y-%m-%d" "$f" 2>/dev/null)
    local name
    name=$(/usr/bin/basename "$f")
    if [ -n "$mtime" ]; then
        echo "$mtime — $name"
    else
        echo "$name"
    fi
}

echo "📂 프로젝트 '${PROJECT_NAME}' 최근 컨텍스트 (7일):"

if [ -n "$DECISIONS" ]; then
    echo "$DECISIONS" | while IFS= read -r f; do
        [ -n "$f" ] && echo "  • 결정: $(format_line "$f")"
    done
fi

if [ -n "$LEARNING" ]; then
    echo "$LEARNING" | while IFS= read -r f; do
        [ -n "$f" ] && echo "  • 학습: $(format_line "$f")"
    done
fi

if [ -n "$SESSIONS" ]; then
    echo "$SESSIONS" | while IFS= read -r f; do
        [ -n "$f" ] && echo "  • 세션: $(format_line "$f")"
    done
fi

echo "필요하면 직접 Read로 확인."

exit 0
