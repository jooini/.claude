#!/bin/zsh
# PreToolUse: Bash로 코드 파일 직접 생성 시도 차단
# cat <<EOF > file.py, echo "..." > file.ts 등 차단
# exit 2 + stderr = 차단

: "${HOME:?}"

INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

CMD=$(python3 - "$INPUT_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    pass
PYEOF
)

[ -z "$CMD" ] && exit 0

# 코드 파일로 리다이렉트하는 패턴 감지
if echo "$CMD" | grep -qE 'cat[[:space:]]+<<.*[[:space:]]*>[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb|swift|vue|svelte|scala|cs)([[:space:]]|$)'; then
  cat >&2 <<MSGEOF
[차단] Bash로 코드 파일 heredoc 작성 감지

대안:
  1. Write 도구 사용 (적은 변경)
  2. Codex MCP에 구현 위임 (대량 변경): mcp__codex-cli__codex
  3. Skill(ask-codex) 호출

이유: Bash heredoc은 검증/리뷰 우회 + 토큰 비효율
MSGEOF
  exit 2
fi

if echo "$CMD" | grep -qE '(echo|printf)[[:space:]]+["'\''].*["'\''][[:space:]]*>[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb|swift)([[:space:]]|$)'; then
  cat >&2 <<MSGEOF
[차단] echo/printf로 코드 파일 작성 감지

Write 도구 또는 Codex 위임 사용.
MSGEOF
  exit 2
fi

exit 0
