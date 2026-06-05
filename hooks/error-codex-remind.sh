#!/bin/zsh
# PostToolUse(Bash): 테스트/빌드 연속 실패 시 Codex 동기 실행
# 2회: 경고, 3회: Codex 동기 실행 후 결과 전달

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)

IS_TEST_BUILD=0
CMD_TYPE=""
if echo "$COMMAND" | grep -qE '(pytest|python -m pytest|npm test|npm run test|npx jest|yarn test|phpunit|gradle test|mvn test|cargo test|go test|make test)'; then
  IS_TEST_BUILD=1
  CMD_TYPE="테스트"
elif echo "$COMMAND" | grep -qE '(npm run build|yarn build|gradle build|mvn compile|cargo build|go build|make build|tsc|npx tsc)'; then
  IS_TEST_BUILD=1
  CMD_TYPE="빌드"
elif echo "$COMMAND" | grep -qE '(npm run lint|npx eslint|flake8|ruff|mypy|pylint)'; then
  IS_TEST_BUILD=1
  CMD_TYPE="린트"
fi

if [ "$IS_TEST_BUILD" -eq 0 ]; then
  exit 0
fi

EXIT_CODE=$(echo "$INPUT" | sed -n 's/.*"exit_code"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')

mkdir -p "$HOME/.claude/cache/codex"
STATE_FILE="$HOME/.claude/cache/.error-count-$$"
ERROR_LOG="$HOME/.claude/cache/.last-error-$$"

if [ "$EXIT_CODE" = "0" ] || [ -z "$EXIT_CODE" ]; then
  echo "0" > "$STATE_FILE"
  exit 0
fi

# 에러 출력 저장
STDOUT=$(echo "$INPUT" | sed -n 's/.*"stdout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -c 2000)
STDERR=$(echo "$INPUT" | sed -n 's/.*"stderr"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -c 2000)
echo "${STDOUT}\n${STDERR}" > "$ERROR_LOG"

CURRENT_COUNT=0
[ -f "$STATE_FILE" ] && CURRENT_COUNT=$(cat "$STATE_FILE")
CURRENT_COUNT=$((CURRENT_COUNT + 1))
echo "$CURRENT_COUNT" > "$STATE_FILE"

CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)
PROJECT_NAME=$(basename "${CWD:-unknown}")
OUTPUT_FILE="$HOME/.claude/cache/codex/${PROJECT_NAME}-rescue.md"

if [ "$CURRENT_COUNT" -ge 3 ]; then
  echo "[Codex rescue 실행 중] ${CMD_TYPE} ${CURRENT_COUNT}회 연속 실패 — Codex가 분석 중..."

  # Codex 동기 실행 (타임아웃 120초)
  # codex exec 사용 — 'codex -a' 는 --ask-for-approval 로 오해석되는 버그였음.
  # PATH 에 codex 없을 수 있어 절대경로 폴백. 비-git 디렉토리 대비 --skip-git-repo-check.
  cd "${CWD:-.}"
  ERROR_CONTEXT=$(cat "$ERROR_LOG" 2>/dev/null | head -50)
  CODEX_BIN="codex"
  command -v codex >/dev/null 2>&1 || CODEX_BIN="$HOME/.nvm/versions/node/v22.22.0/bin/codex"
  RESULT=$(timeout 120 "$CODEX_BIN" exec --skip-git-repo-check "다음 ${CMD_TYPE} 명령이 3회 연속 실패했다: ${COMMAND}

에러:
${ERROR_CONTEXT}

근본 원인을 분석하고 수정 방안을 제시해줘." 2>/dev/null)

  if [ -n "$RESULT" ]; then
    echo "$RESULT" > "$OUTPUT_FILE"
    echo "[Codex rescue 완료] 분석 결과:"
    echo "---"
    echo "$RESULT"
    outcome_log "error-codex-remind" "trigger" "${PROJECT_NAME}:${CMD_TYPE}:${CURRENT_COUNT}fail" "codex-rescue-fired"
  else
    echo "[Codex rescue 실패/타임아웃] — codex:codex-rescue 스킬을 수동 실행하세요"
    outcome_log "error-codex-remind" "warn" "${PROJECT_NAME}:${CMD_TYPE}:timeout" "codex-rescue-failed"
  fi
  echo "0" > "$STATE_FILE"
elif [ "$CURRENT_COUNT" -ge 2 ]; then
  echo "[${CMD_TYPE} ${CURRENT_COUNT}회 연속 실패] 다음 실패 시 Codex rescue 자동 실행"
  outcome_log "error-codex-remind" "warn" "${PROJECT_NAME}:${CMD_TYPE}:2fail" "test-fail-2"
fi

exit 0
