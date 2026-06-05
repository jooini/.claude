#!/bin/zsh
# PostToolUse(Edit|Write): 의존성 파일 변경 시 Gemini로 영향 분석 (1M 컨텍스트)
# Gemma는 4줄 요약, Gemini는 코드베이스 영향 범위 포함 5-7줄 분석
# 출력: hookSpecificOutput.additionalContext

: "${HOME:?}"

. "$HOME/.claude/scripts/_nvm-path.sh"  # nvm PATH 보강
source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

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
    data = json.load(sys.stdin)
    resp = data.get('tool_response', {})
    fp = resp.get('filePath') or resp.get('file_path')
    if not fp:
        fp = data.get('tool_input', {}).get('file_path', '')
    print(fp)
except Exception:
    pass
" 2>/dev/null)

[ -z "$FILE_PATH" ] && exit 0

case "$(basename "$FILE_PATH")" in
    package.json|requirements.txt|requirements-*.txt|Pipfile|pyproject.toml|composer.json|build.gradle|build.gradle.kts|pom.xml|Cargo.toml|Gemfile|go.mod)
        ;;
    *)
        exit 0
        ;;
esac

PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
[ -z "$PROJECT_ROOT" ] && exit 0

DIFF=$(git -C "$PROJECT_ROOT" diff -- "$FILE_PATH" 2>/dev/null)
[ -z "$DIFF" ] && DIFF=$(git -C "$PROJECT_ROOT" diff --cached -- "$FILE_PATH" 2>/dev/null)
[ -z "$DIFF" ] && exit 0

PROJECT_NAME=$(basename "$PROJECT_ROOT")
CACHE_DIR="$HOME/.claude/cache/gemini"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-dependency-impact.md"

# 같은 diff 해시면 캐시 재사용 (5분 이내)
DIFF_HASH=$(echo "$DIFF" | shasum | cut -c1-12)
HASH_FILE="${OUTPUT_FILE}.hash"
if [ -f "$HASH_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
    PREV_HASH=$(cat "$HASH_FILE" 2>/dev/null)
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
    if [ "$PREV_HASH" = "$DIFF_HASH" ] && [ "$FILE_AGE" -lt 300 ]; then
        RESULT=$(cat "$OUTPUT_FILE")
        export GEMINI_RESULT="$RESULT" PROJECT_NAME
        python3 -c "
import json, os
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': '[Gemini 의존성 영향 분석 (캐시) — ' + os.environ['PROJECT_NAME'] + ']\n' + os.environ['GEMINI_RESULT']
    }
}))
"
        outcome_log "gemini-dependency-impact" "trigger" "${PROJECT_NAME}:${FILE_PATH##*/}" "gemini-impact-cached"
        exit 0
    fi
fi

DIFF_TRUNCATED=$(echo "$DIFF" | head -200)

PROMPT=$(printf '의존성 파일 변경 영향 분석. 프로젝트 루트: %s\n\ndiff:\n%s\n\n다음 형식으로 한국어 5-7줄:\n**변경**: 추가/제거/업그레이드 패키지 (한 줄)\n**호환성 위험**: major version 점프, breaking change, deprecated API\n**보안**: 알려진 CVE 또는 신뢰성 이슈\n**코드베이스 영향**: 이 패키지를 import/사용하는 추정 파일 수 또는 모듈\n**권장 조치**: 추가 검증/테스트 필요한 부분 (없으면 "없음")\n\n장식/인사 금지. 모르면 "확인 필요" 표기.\n' "$PROJECT_NAME" "$DIFF_TRUNCATED")

# agy는 $(cat)이 stdin 선소비 → EOF만 받는 이중 stdin 패턴 사용 금지.
# 프롬프트를 단일 -p 인자로 직접 전달.
RESULT=$("$GEM_CLI" -p "$PROMPT" 2>/dev/null | tail -50)

if [ -z "$RESULT" ]; then
    outcome_log "gemini-dependency-impact" "warn" "${PROJECT_NAME}:${FILE_PATH##*/}:empty" "gemini-impact-noresult"
    exit 0
fi

echo "$RESULT" > "$OUTPUT_FILE"
echo "$DIFF_HASH" > "$HASH_FILE"
outcome_log "gemini-dependency-impact" "trigger" "${PROJECT_NAME}:${FILE_PATH##*/}:${GEM_CLI}" "gemini-impact-fired"

export GEMINI_RESULT="$RESULT" PROJECT_NAME
python3 -c "
import json, os
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': '[Gemini 의존성 영향 분석 — ' + os.environ['PROJECT_NAME'] + ']\n' + os.environ['GEMINI_RESULT']
    }
}))
"

exit 0
