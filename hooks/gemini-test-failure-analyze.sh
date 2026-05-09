#!/bin/zsh
# PostToolUse(Bash): 테스트 실패 카운터 추적, 3회 이상 실패 시 Gemini 영향 분석
# Codex rescue (3회 실패) 직전 단계 — 영향 범위 먼저 파악 후 Codex가 수정
# 출력: stdout 비차단

: "${HOME:?}"

command -v gemini >/dev/null 2>&1 || exit 0

INPUT=$(cat)

# 빠른 사전 필터: JSON 본문에 테스트 키워드가 없으면 python 파싱 자체를 스킵
# (PostToolUse 발동 268회/일 중 95%가 테스트 명령 아님 — 콜드스타트 비용 회피)
TEST_RE='(pytest|jest|vitest|npm test|npm run test|gradle test|mvn test|go test|cargo test|phpunit|rspec)'
echo "$INPUT" | grep -qE "$TEST_RE" || exit 0

# 여기 도달했으면 후보 — 정확한 파싱 필요
EXIT_CODE=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    resp = data.get('tool_response', {})
    print(resp.get('exit_code', 0))
except Exception:
    print(0)
" 2>/dev/null)

COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

# command 필드 자체에 테스트 키워드 있는지 정확 재검 (JSON 잡음 후 확정)
echo "$COMMAND" | grep -qE "$TEST_RE" || exit 0

CWD=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('cwd', ''))
except Exception:
    pass
" 2>/dev/null)
[ -z "$CWD" ] && CWD=$(pwd)

PROJECT_NAME=$(basename "$CWD")
COUNTER_DIR="$HOME/.claude/cache/test-failure"
mkdir -p "$COUNTER_DIR"
COUNTER_FILE="$COUNTER_DIR/${PROJECT_NAME}.count"

if [ "$EXIT_CODE" = "0" ] || [ "$EXIT_CODE" = "" ]; then
    rm -f "$COUNTER_FILE"
    exit 0
fi

COUNT=0
[ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# 3회 실패 시점에만 Gemini 분석 (그 다음은 Codex rescue 단계)
[ "$COUNT" -ne 3 ] && exit 0

git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null || exit 0

CACHE_DIR="$HOME/.claude/cache/gemini"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-test-failure-analysis.md"

DIFF=$(git -C "$CWD" diff HEAD 2>/dev/null | head -500)
RECENT_LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null)

echo "[Gemini 테스트 3회 실패 영향 분석 — ${PROJECT_NAME}, 백그라운드]"
echo "[다음 실패 시 codex:rescue로 자동 위임 권장]"

(
    PROMPT="프로젝트 ${PROJECT_NAME} 테스트가 3회 연속 실패. 영향 범위와 가설을 분석.

최근 변경:
${DIFF}

최근 커밋:
${RECENT_LOG}

다음을 한국어로:
**가능성 높은 원인** (3개 가설, 각 한 줄):
**영향 받는 모듈** (변경된 파일이 의존하는 곳):
**Codex에 위임 시 우선 보여줄 파일**:
**자가 수정 시도 가치** (high/medium/low + 이유):

장식/인사 금지."

    echo "$PROMPT" | gemini -p "$(cat)" > "$OUTPUT_FILE" 2>/dev/null
) &

exit 0
