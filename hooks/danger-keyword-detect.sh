#!/bin/zsh
# PreToolUse(Bash): 위험 명령 키워드 사전 감지
# 정규식 매칭만 — Ollama 호출 안 함, 차단 안 함 (exit 0)
# stdout 경고 출력으로 사용자 인지 유도

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

WARN=""
LEVEL=""

# 🔴 시스템/홈 디렉토리 삭제
if echo "$CMD" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)[[:space:]]+(/|~|\$HOME)([[:space:]]|$|/[[:space:]]*$)'; then
  LEVEL="🔴"
  WARN="시스템/홈 디렉토리 삭제 — 시스템 파괴 위험. 경로 다시 확인."

# 🔴 디스크 디바이스 직접 쓰기 (dd of=/dev/...)
elif echo "$CMD" | grep -qE 'dd[[:space:]]+.*of=/dev/'; then
  LEVEL="🔴"
  WARN="dd로 디스크 직접 쓰기 — 데이터 손실 위험. 디바이스 경로 확인."

# 🔴 디스크 디바이스 리다이렉트 (> /dev/sd[a-z])
elif echo "$CMD" | grep -qE '>[[:space:]]*/dev/sd[a-z]'; then
  LEVEL="🔴"
  WARN="디스크 디바이스 직접 쓰기 — 데이터 손실 위험."

# 🔴 main/master 강제 푸시
elif echo "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$)).*[[:space:]](main|master)([[:space:]]|$|:)'; then
  LEVEL="🔴"
  WARN="main/master force push — 다른 사람 작업을 덮어씁니다."
elif echo "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(main|master).*(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$))'; then
  LEVEL="🔴"
  WARN="main/master force push — 다른 사람 작업을 덮어씁니다."

# 🔴 SQL 데이터 삭제
elif echo "$CMD" | grep -qiE '(DROP[[:space:]]+(DATABASE|TABLE)|TRUNCATE[[:space:]]+TABLE)'; then
  LEVEL="🔴"
  WARN="SQL 데이터 삭제 명령 — 복구 불가. 환경(prod/stage) 확인 필수."

# 🟡 git reset --hard (commit/branch 인자 없음)
elif echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard[[:space:]]*$'; then
  LEVEL="🟡"
  WARN="git reset --hard (인자 없음) — 모든 unstaged/staged 변경 폐기. 의도 확인."

# 🟡 git checkout . (전체 폐기)
elif echo "$CMD" | grep -qE 'git[[:space:]]+checkout[[:space:]]+\.[[:space:]]*$'; then
  LEVEL="🟡"
  WARN="git checkout . — 모든 unstaged 변경 폐기. 의도 확인."

# 🟡 chmod -R 777
elif echo "$CMD" | grep -qE 'chmod[[:space:]]+(-R[[:space:]]+777|777[[:space:]]+-R)'; then
  LEVEL="🟡"
  WARN="chmod -R 777 — 보안 위험. 실제 필요 권한만 부여."

# 🟡 curl | sh|bash (인터넷 스크립트 실행)
elif echo "$CMD" | grep -qE '(curl|wget)[[:space:]]+.*\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)'; then
  LEVEL="🟡"
  WARN="인터넷 스크립트를 직접 실행 — 출처 신뢰 가능한지 확인."

# 🟡 sudo rm
elif echo "$CMD" | grep -qE 'sudo[[:space:]]+rm[[:space:]]'; then
  LEVEL="🟡"
  WARN="sudo rm — 권한 상승 삭제. 경로 다시 확인."
fi

if [ -n "$WARN" ]; then
  cat <<EOF
[$LEVEL 위험 명령 감지] $CMD
  → $WARN
  의도가 맞다면 진행. 의도와 다르면 중단(Ctrl+C).
EOF
fi

exit 0
