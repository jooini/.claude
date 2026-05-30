#!/bin/zsh
# PreToolUse: Bash로 코드 파일 직접 생성 시도 차단
# cat <<EOF > file.py, echo "..." > file.ts 등 차단
# exit 2 + stderr = 차단

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

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

# 근본 차단: heredoc(<<) 이 든 멀티라인 명령은 tool call JSON 을 깨뜨려
# "The model's tool call could not be parsed" 에러를 유발한다.
# here-string(<<<) 은 허용. heredoc 마커 <<EOF / << 'EOF' / <<-EOF 만 감지.
#
# [중요] 진짜 heredoc 은 본질적으로 멀티라인이다(마커 뒤 줄바꿈 + 종료마커 줄).
# 단일라인 명령은 <<EOF 글자가 있어도 heredoc 일 수 없다(그냥 문자열).
# 따라서 "명령에 실제 줄바꿈이 있을 때만" 차단해 false positive 를 막는다.
# 예: git commit -m "use <<HEREDOC" (단일라인) → 통과. 문자열 속 마커일 뿐.
LINE_COUNT=$(printf '%s' "$CMD" | wc -l | tr -d ' ')
if [ "$LINE_COUNT" -ge 1 ] \
   && echo "$CMD" | grep -qE '<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*' \
   && ! echo "$CMD" | grep -qE '<<<'; then
  cat >&2 <<MSGEOF
[차단] Bash heredoc(<<) 명령 감지

heredoc + 멀티라인 + 중첩 따옴표는 tool call JSON 을 깨뜨려
"The model's tool call could not be parsed" 에러를 유발한다.

대안:
  1. 코드/스크립트는 Write 도구로 파일 생성 후, 실행은 한 줄 명령으로
  2. 컨테이너 실행: Write 로 .py 작성 -> docker cp -> docker exec python3 file.py
  3. 인라인 코드가 꼭 필요하면 python3 -c "..." (줄바꿈 없는 한 줄)

이유: heredoc 자체가 파싱 불가 에러의 근본 원인.
MSGEOF
  outcome_log "bash-codegen-block" "block" "heredoc-any" "heredoc-marker"
  exit 2
fi

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
  outcome_log "bash-codegen-block" "block" "heredoc" "heredoc-redirect"
  exit 2
fi

if echo "$CMD" | grep -qE '(echo|printf)[[:space:]]+["'\''].*["'\''][[:space:]]*>[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb|swift)([[:space:]]|$)'; then
  cat >&2 <<MSGEOF
[차단] echo/printf로 코드 파일 작성 감지

Write 도구 또는 Codex 위임 사용.
MSGEOF
  outcome_log "bash-codegen-block" "block" "echo-printf" "echo-redirect"
  exit 2
fi

outcome_log "bash-codegen-block" "pass" "" "no-match"
exit 0
