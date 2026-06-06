#!/bin/zsh
# PreToolUse(Bash): gh pr create 감지 → Codex 동기 diff 요약
# PR 생성 전에 Codex가 요약을 완성해서 전달

: "${HOME:?}"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)

if ! echo "$COMMAND" | grep -qE 'gh\s+pr\s+create'; then
  exit 0
fi

CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)
PROJECT_NAME=$(basename "${CWD:-unknown}")
mkdir -p "$HOME/.claude/cache/codex"
OUTPUT_FILE="$HOME/.claude/cache/codex/${PROJECT_NAME}-pr-summary.md"

cd "${CWD:-.}"
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
DIFF_STAT=$(git diff "${BASE_BRANCH}...HEAD" --stat 2>/dev/null | tail -20)
COMMIT_LOG=$(git log "${BASE_BRANCH}...HEAD" --oneline 2>/dev/null | head -20)

# 변경사항이 없으면 스킵
if [ -z "$COMMIT_LOG" ]; then
  exit 0
fi

echo "[Codex PR 요약 생성 중] 완료까지 대기..."

RESULT=$("$HOME/.claude/scripts/llm-call.sh" codex \
  --caller pr-create-codex-remind \
  --timeout 90 \
  --prompt "이 브랜치의 PR 설명을 작성해줘.

커밋 로그:
${COMMIT_LOG}

변경 통계:
${DIFF_STAT}

## Summary 형식으로 주요 변경사항 3줄 이내 요약, ## Test plan으로 테스트 체크리스트 작성. 한글로." \
  2>/dev/null)

if [ -n "$RESULT" ]; then
  echo "$RESULT" > "$OUTPUT_FILE"
  echo "[Codex PR 요약 완료] PR 설명에 아래 내용을 반영하세요:"
  echo "---"
  echo "$RESULT"
else
  echo "[Codex PR 요약 실패/타임아웃] — PR 설명을 직접 작성하세요"
fi

exit 0
