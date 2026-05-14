#!/bin/zsh
# PostToolUse(Bash): 브랜치 전환 감지 → Gemini 스캔 리마인드
# exit 0 + stdout = 비차단 리마인더

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)

# git checkout / git switch 명령인지 확인
if ! echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)\s+'; then
  exit 0
fi

# 파일 체크아웃은 제외 (git checkout -- file)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+'; then
  exit 0
fi

# -b (새 브랜치 생성)인지 기존 브랜치 전환인지 판별
if echo "$COMMAND" | grep -qE '(-b|--branch|-c|--create)\s+'; then
  SWITCH_TYPE="새 브랜치 생성"
else
  SWITCH_TYPE="브랜치 전환"
fi

# 브랜치명 추출 (마지막 인자)
BRANCH=$(echo "$COMMAND" | awk '{print $NF}')

echo "[${SWITCH_TYPE}] ${BRANCH} — Gemini CLI로 이 브랜치의 코드베이스를 스캔하세요 (Phase 0). code-review-graph:build-graph도 고려하세요."

exit 0
