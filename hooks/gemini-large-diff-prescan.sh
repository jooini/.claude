#!/bin/zsh
# PreToolUse(Bash): git commit 직전 diff > 200 lines 면 Gemini 전체 분석
# 1M 컨텍스트로 큰 변경의 일관성/누락 검토
# 출력: stdout 비차단 리마인더

: "${HOME:?}"

GEM_CLI="${GEMINI_CLI:-}"
if [ -z "$GEM_CLI" ]; then
    if command -v agy >/dev/null 2>&1; then GEM_CLI=agy
    elif command -v gemini >/dev/null 2>&1; then GEM_CLI=gemini
    else exit 0
    fi
fi
command -v "$GEM_CLI" >/dev/null 2>&1 || exit 0

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

# git commit 명령만
echo "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+(-C[[:space:]]+\S+[[:space:]]+)?commit' || exit 0

# amend / no-op은 패스
echo "$COMMAND" | grep -qE -- '--amend|--allow-empty|-m[[:space:]]+["\x27]wip' && exit 0

CWD=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('cwd', ''))
except Exception:
    pass
" 2>/dev/null)
[ -z "$CWD" ] && CWD=$(pwd)

git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null || exit 0

# staged diff 우선, 없으면 working tree
DIFF=$(git -C "$CWD" diff --cached 2>/dev/null)
[ -z "$DIFF" ] && DIFF=$(git -C "$CWD" diff HEAD 2>/dev/null)
[ -z "$DIFF" ] && exit 0

DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')
[ "$DIFF_LINES" -lt 200 ] && exit 0

PROJECT_NAME=$(basename "$(git -C "$CWD" rev-parse --show-toplevel)")
CACHE_DIR="$HOME/.claude/cache/gemini"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-large-diff-prescan.md"

DIFF_HASH=$(echo "$DIFF" | shasum | cut -c1-12)
HASH_FILE="${OUTPUT_FILE}.hash"
if [ -f "$HASH_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
    PREV_HASH=$(cat "$HASH_FILE" 2>/dev/null)
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
    if [ "$PREV_HASH" = "$DIFF_HASH" ] && [ "$FILE_AGE" -lt 600 ]; then
        echo "[Gemini 대형 diff 분석 (캐시, ${DIFF_LINES} lines)] — ${OUTPUT_FILE}"
        cat "$OUTPUT_FILE"
        exit 0
    fi
fi

echo "[Gemini 대형 diff 분석 시작 — ${DIFF_LINES} lines, 백그라운드]"

# 큰 diff는 동기 실행하면 commit이 막힘 → 백그라운드
DIFF_TRUNCATED=$(echo "$DIFF" | head -2000)

(
    PROMPT="다음 git diff 전체를 1M 컨텍스트로 검토. 한국어로 답변.

체크 항목:
1. 변경 일관성: 같은 패턴이 일부 파일에만 적용되어 누락된 곳
2. 의도 추정: 무엇을 하려는 변경인지 한 줄
3. 위험 신호: 누락된 테스트, 타입 불일치, 에러 핸들링 빠진 곳
4. 영향 범위: 이 변경이 건드릴 다른 모듈/팀

출력 형식:
**의도**: ...
**일관성**: ...
**위험 신호**: ...
**영향 범위**: ...

diff:
$DIFF_TRUNCATED"

    echo "$PROMPT" | "$GEM_CLI" -p "$(cat)" > "$OUTPUT_FILE" 2>/dev/null
    echo "$DIFF_HASH" > "$HASH_FILE"
) &

exit 0
