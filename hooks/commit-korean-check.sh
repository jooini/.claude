#!/bin/zsh
# PreToolUse: git commit 시 커밋 메시지가 한글인지 검증

: "${HOME:?}"
source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT=$(cat)

# git commit 명령인지 확인
COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

# git commit이 아니면 패스
if ! echo "$COMMAND" | grep -q 'git commit'; then
  outcome_log "commit-korean-check" "pass" "" "no-match" 2>/dev/null
  exit 0
fi

# 커밋 메시지 추출 (-m 뒤의 내용)
COMMIT_MSG=$(echo "$COMMAND" | python3 -c "
import shlex, sys
command = sys.stdin.read()
try:
    args = shlex.split(command)
except Exception:
    args = []
for index, arg in enumerate(args):
    if arg == '-m' and index + 1 < len(args):
        print(args[index + 1])
        break
    if arg.startswith('-m') and len(arg) > 2:
        print(arg[2:])
        break
" 2>/dev/null | head -1)

# heredoc 패턴도 처리 (cat <<'EOF' ... EOF)
if [ -z "$COMMIT_MSG" ]; then
  COMMIT_MSG=$(echo "$COMMAND" | sed -n 's/.*<<.*EOF[[:space:]]*\(.*\)[[:space:]]*EOF.*/\1/p')
fi

# 메시지 추출 실패하면 패스
if [ -z "$COMMIT_MSG" ]; then
  outcome_log "commit-korean-check" "pass" "" "msg-extract-fail" 2>/dev/null
  exit 0
fi

# Co-Authored-By 제거 후 본문만 검사
MSG_BODY=$(echo "$COMMIT_MSG" | sed '/Co-Authored-By/d' | head -1)

# 한글이 포함되어 있는지 확인
if echo "$MSG_BODY" | grep -q '[가-힣]'; then
  outcome_log "commit-korean-check" "pass" "" "korean-ok" 2>/dev/null
  exit 0
else
  echo '{"error": "커밋 메시지를 한글로 작성해주세요. 현재 메시지: '"$MSG_BODY"'"}' >&2
  outcome_log "commit-korean-check" "block" "한글 미포함" "no-korean" 2>/dev/null
  exit 2
fi
