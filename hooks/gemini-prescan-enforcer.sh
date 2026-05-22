#!/bin/zsh
# PreToolUse(Edit|Write): 같은 세션에서 3파일 이상 코드 수정 시 Gemini Phase 0 스캔 강제
# Phase 0 스캔 결과 캐시 없으면 비차단 경고 + 백그라운드 스캔 시작
# CLAUDE.md L65 룰을 자동화

: "${HOME:?}"

# CLI 선택: $GEMINI_CLI 우선, 없으면 agy(2026-06-18 이후 기본) → gemini 폴백
GEM_CLI="${GEMINI_CLI:-}"
if [ -z "$GEM_CLI" ]; then
    if command -v agy >/dev/null 2>&1; then GEM_CLI=agy
    elif command -v gemini >/dev/null 2>&1; then GEM_CLI=gemini
    else exit 0
    fi
fi
command -v "$GEM_CLI" >/dev/null 2>&1 || exit 0

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('file_path', ''))
except Exception:
    pass
" 2>/dev/null)

[ -z "$FILE_PATH" ] && exit 0

# 코드 파일만
case "$FILE_PATH" in
    *.py|*.ts|*.tsx|*.js|*.jsx|*.kt|*.kts|*.java|*.go|*.rs|*.php|*.rb|*.swift|*.cs)
        ;;
    *)
        exit 0
        ;;
esac

# 설정/문서 디렉토리 제외
case "$FILE_PATH" in
    */node_modules/*|*/.git/*|*/.venv/*|*/venv/*|*/dist/*|*/build/*|*/__pycache__/*)
        exit 0
        ;;
esac

# 프로젝트 루트
PROJECT_ROOT=""
DIR=$(dirname "$FILE_PATH")
while [ "$DIR" != "/" ] && [ "$DIR" != "$HOME" ]; do
    if [ -f "$DIR/package.json" ] || [ -f "$DIR/pyproject.toml" ] || [ -f "$DIR/build.gradle" ] || [ -f "$DIR/build.gradle.kts" ] || [ -f "$DIR/composer.json" ] || [ -f "$DIR/Cargo.toml" ] || [ -f "$DIR/go.mod" ]; then
        PROJECT_ROOT="$DIR"
        break
    fi
    DIR=$(dirname "$DIR")
done
[ -z "$PROJECT_ROOT" ] && exit 0

PROJECT_NAME=$(basename "$PROJECT_ROOT")

# 세션별 수정 카운터
COUNTER_DIR="$HOME/.claude/cache/edit-tracker"
mkdir -p "$COUNTER_DIR"
SESSION_ID=${CLAUDE_SESSION_ID:-$$}
COUNTER_FILE="$COUNTER_DIR/${PROJECT_NAME}-${SESSION_ID}.files"

# 새 파일이면 추가
grep -qxF "$FILE_PATH" "$COUNTER_FILE" 2>/dev/null || echo "$FILE_PATH" >> "$COUNTER_FILE"

FILE_COUNT=$(wc -l < "$COUNTER_FILE" 2>/dev/null | tr -d ' ')
[ "$FILE_COUNT" -lt 3 ] && exit 0

# Phase 0 스캔 캐시 확인
SCAN_CACHE="$HOME/.claude/cache/gemini/${PROJECT_NAME}-scan.md"
if [ -f "$SCAN_CACHE" ]; then
    SCAN_AGE=$(( $(date +%s) - $(stat -f %m "$SCAN_CACHE" 2>/dev/null || echo 0) ))
    if [ "$SCAN_AGE" -lt 1800 ]; then
        # 30분 이내 스캔 있으면 침묵 (이미 컨텍스트 보유)
        exit 0
    fi
fi

# Phase 0 스캔 없거나 오래됨 → 경고 + 백그라운드 시작
ENFORCER_FLAG="$COUNTER_DIR/${PROJECT_NAME}-${SESSION_ID}.warned"
if [ ! -f "$ENFORCER_FLAG" ]; then
    touch "$ENFORCER_FLAG"
    echo "[⚠️ Gemini Phase 0 미실행 — ${FILE_COUNT}개 파일 수정 중] CLAUDE.md L65 룰: 3파일+ 수정 시 Gemini 스캔 선행 권장"
    echo "[백그라운드 Phase 0 스캔 시작 → cat ${SCAN_CACHE}]"

    (
        cd "$PROJECT_ROOT"
        "$GEM_CLI" -p "이 프로젝트의 구조, 주요 파일, 기술 스택, 아키텍처를 요약. 핵심 엔트리포인트와 의존성 관계 중심. 한국어." \
            > "$SCAN_CACHE" 2>/dev/null
    ) &
fi

exit 0
