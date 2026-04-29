#!/bin/zsh
# PreToolUse: git commit에 Co-Authored-By가 포함되면 차단

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')

# git commit이 아니면 패스
if ! echo "$COMMAND" | grep -q 'git commit'; then
  exit 0
fi

# Co-Authored-By 포함 여부 확인
if echo "$COMMAND" | grep -qi 'Co-Authored-By'; then
  echo '{"error": "Co-Authored-By를 포함하지 마세요. CLAUDE.md 커밋 규칙 위반."}' >&2
  exit 2
fi

exit 0
