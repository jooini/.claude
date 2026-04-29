#!/bin/zsh
# Stop: 세션 종료 시 코드 변경이 있는데 테스트/리뷰 안 했으면 경고

# git 저장소인지 확인
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

# 스테이징 안 된 코드 변경 확인
CODE_CHANGES=$(git diff --name-only 2>/dev/null | grep -E '\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb)$' | grep -vcE '(test_|_test\.|spec\.|\.spec\.)' 2>/dev/null)
STAGED_CHANGES=$(git diff --cached --name-only 2>/dev/null | grep -E '\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb)$' | grep -vcE '(test_|_test\.|spec\.|\.spec\.)' 2>/dev/null)

TOTAL=$((CODE_CHANGES + STAGED_CHANGES))

if [ "$TOTAL" -gt 0 ]; then
  say -v Yuna "커밋되지 않은 코드 변경이 있습니다. 파이프라인 확인하세요." < /dev/null &
  echo "⚠️ 커밋되지 않은 코드 변경 ${TOTAL}개 감지. 파이프라인(developer → codex-review → tester) 완료했는지 확인하세요."
fi

exit 0
