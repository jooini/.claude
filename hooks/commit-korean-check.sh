#!/bin/zsh
# PreToolUse: git commit 시 커밋 메시지가 한글인지 검증

INPUT=$(cat)

# git commit 명령인지 확인
COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')

# git commit이 아니면 패스
if ! echo "$COMMAND" | grep -q 'git commit'; then
  exit 0
fi

# 커밋 메시지 추출 (-m 뒤의 내용)
COMMIT_MSG=$(echo "$COMMAND" | sed -n 's/.*-m[[:space:]]*["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/p')

# heredoc 패턴도 처리 (cat <<'EOF' ... EOF)
if [ -z "$COMMIT_MSG" ]; then
  COMMIT_MSG=$(echo "$COMMAND" | sed -n 's/.*<<.*EOF[[:space:]]*\(.*\)[[:space:]]*EOF.*/\1/p')
fi

# 메시지 추출 실패하면 패스
if [ -z "$COMMIT_MSG" ]; then
  exit 0
fi

# Co-Authored-By 제거 후 본문만 검사
MSG_BODY=$(echo "$COMMIT_MSG" | sed '/Co-Authored-By/d' | head -1)

# 한글이 포함되어 있는지 확인
if echo "$MSG_BODY" | grep -q '[가-힣]'; then
  exit 0
else
  echo '{"error": "커밋 메시지를 한글로 작성해주세요. 현재 메시지: '"$MSG_BODY"'"}' >&2
  exit 2
fi
