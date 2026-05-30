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

# [설계 결정 2026-05-30] heredoc 전면차단 제거.
# 근거:
#   - PreToolUse 훅이 CMD 를 받았다는 것 자체가 tool call JSON 파싱 성공의 증거다.
#     파싱 에러가 날 명령은 훅에 도달하기 전 harness 단계에서 실패한다.
#     따라서 "파싱 에러 방지" 목적의 heredoc 전면차단은 논리적으로 무효였다.
#   - 실측: 전체 5751회 중 heredoc-marker 차단 18건이 거의 전부 분석/검증 명령 오탐.
#   - 진짜 막을 대상(코드 파일 heredoc 생성)은 아래 redirect/echo 룰이 담당.
#   - 코드 생성 유도는 Edit|Write 매처의 delegation-enforcer 가 별도 방어.
# 따라서 "코드 파일로 리다이렉트하는 heredoc" 만 차단한다.

# 코드 파일로 리다이렉트하는 패턴 감지
if echo "$CMD" | grep -qE 'cat[[:space:]]+<<.*[[:space:]]*>[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb|swift|vue|svelte|scala|cs)([[:space:]]|$)'; then
  cat >&2 <<MSGEOF
[차단] Bash로 코드 파일 heredoc 작성 감지

대안:
  1. Write 도구 사용 (적은 변경)
  2. Codex에 구현 위임 (대량 변경): Skill(ask-codex) 또는 codex exec / codex:rescue
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
