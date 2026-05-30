#!/bin/zsh
# PreToolUse(Bash): 위험 명령 키워드 사전 감지
# 정규식 매칭만 — Ollama 호출 안 함, 차단 안 함 (exit 0)
# stdout 경고 출력으로 사용자 인지 유도

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

WARN=""
LEVEL=""
TRIGGER=""
BLOCK=0

# 🔴 시스템/홈 디렉토리 삭제
if echo "$CMD" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)[[:space:]]+(/|~|\$HOME)([[:space:]]|$|/[[:space:]]*$)'; then
  LEVEL="🔴"; TRIGGER="rm-rf-root-or-home"
  WARN="시스템/홈 디렉토리 삭제 — 시스템 파괴 위험. 경로 다시 확인."

# 🔴 find 로 대량 삭제 (-delete / -exec rm) — rm 키워드가 경로와 분리된 우회 형태
elif echo "$CMD" | grep -qE 'find[[:space:]]+.*-delete([[:space:]]|$)'; then
  LEVEL="🔴"; TRIGGER="find-delete"
  WARN="find -delete — 매칭 파일 대량 삭제. 검색 범위/패턴 다시 확인."

elif echo "$CMD" | grep -qE 'find[[:space:]]+.*-exec[[:space:]]+rm([[:space:]]|$)'; then
  LEVEL="🔴"; TRIGGER="find-exec-rm"
  WARN="find -exec rm — 매칭 파일 대량 삭제. 검색 범위/패턴 다시 확인."

# 🔴 xargs rm — 파이프로 받은 목록을 대량 삭제
elif echo "$CMD" | grep -qE 'xargs[[:space:]]+(-[a-zA-Z0-9]+[[:space:]]+)*rm([[:space:]]|$)'; then
  LEVEL="🔴"; TRIGGER="xargs-rm"
  WARN="xargs rm — 파이프 입력을 대량 삭제. 입력 목록 먼저 확인."

# 🔴 디스크 디바이스 직접 쓰기 (dd of=/dev/...)
elif echo "$CMD" | grep -qE 'dd[[:space:]]+.*of=/dev/'; then
  LEVEL="🔴"; TRIGGER="dd-to-device"
  WARN="dd로 디스크 직접 쓰기 — 데이터 손실 위험. 디바이스 경로 확인."

# 🔴 디스크 디바이스 리다이렉트 (> /dev/sd[a-z])
elif echo "$CMD" | grep -qE '>[[:space:]]*/dev/sd[a-z]'; then
  LEVEL="🔴"; TRIGGER="redirect-to-disk-device"
  WARN="디스크 디바이스 직접 쓰기 — 데이터 손실 위험."

# 🔴 main/master 강제 푸시
elif echo "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$)).*[[:space:]](main|master)([[:space:]]|$|:)'; then
  LEVEL="🔴"; TRIGGER="main-force-push"
  WARN="main/master force push — 다른 사람 작업을 덮어씁니다."
elif echo "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(main|master).*(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$))'; then
  LEVEL="🔴"; TRIGGER="main-force-push"
  WARN="main/master force push — 다른 사람 작업을 덮어씁니다."

# 🔴 SQL 데이터 삭제 — 실제 DB 클라이언트 실행 컨텍스트에서만 차단
# 조건: ① DB 클라이언트가 "실행 명령 위치"(줄 시작 또는 명령구분자 &&/||/;/|/뒤)에 오고
#       ② 그 클라이언트에 실행 플래그(-c/-e/--eval/--command/-f) 또는 stdin 리다이렉트(<)가 붙고
#       ③ 파괴 키워드(DROP/TRUNCATE/DELETE FROM/dropDatabase/deleteMany)가 있을 때만 차단.
# git commit -m "...mysql..." 처럼 DB 도구명이 인자/문자열로만 등장하면 통과
# (첫 토큰이 git/echo/codex 등이므로 클라이언트 실행 위치 매칭 안 됨).
elif echo "$CMD" \
       | grep -qiE '(^|&&|\|\||;|\|)[[:space:]]*(sudo[[:space:]]+)?(/[^[:space:]]*/)?(psql|mysql|mariadb|mongosh|sqlite3)([[:space:]]+[^[:space:]&|;]*)*[[:space:]]+(-c|-e|-f|--command|--eval|--execute|<)' \
     && echo "$CMD" \
       | grep -qiE '(DROP[[:space:]]+(DATABASE|TABLE|SCHEMA)|TRUNCATE([[:space:]]+TABLE)?|DELETE[[:space:]]+FROM|dropDatabase|deleteMany)'; then
  LEVEL="🔴"; TRIGGER="sql-destructive-exec"
  WARN="DB 클라이언트로 파괴적 SQL/쿼리 실행 — 복구 불가. 환경(prod/stage) 확인 필수. 의도와 다르면 즉시 중단."
  BLOCK=1

# 🟡 git reset --hard (commit/branch 인자 없음)
elif echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard[[:space:]]*$'; then
  LEVEL="🟡"; TRIGGER="git-reset-hard-bare"
  WARN="git reset --hard (인자 없음) — 모든 unstaged/staged 변경 폐기. 의도 확인."

# 🟡 git checkout . (전체 폐기)
elif echo "$CMD" | grep -qE 'git[[:space:]]+checkout[[:space:]]+\.[[:space:]]*$'; then
  LEVEL="🟡"; TRIGGER="git-checkout-dot"
  WARN="git checkout . — 모든 unstaged 변경 폐기. 의도 확인."

# 🟡 chmod -R 777
elif echo "$CMD" | grep -qE 'chmod[[:space:]]+(-R[[:space:]]+777|777[[:space:]]+-R)'; then
  LEVEL="🟡"; TRIGGER="chmod-777-recursive"
  WARN="chmod -R 777 — 보안 위험. 실제 필요 권한만 부여."

# 🟡 curl | sh|bash (인터넷 스크립트 실행)
elif echo "$CMD" | grep -qE '(curl|wget)[[:space:]]+.*\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)'; then
  LEVEL="🟡"; TRIGGER="curl-pipe-shell"
  WARN="인터넷 스크립트를 직접 실행 — 출처 신뢰 가능한지 확인."

# 🟡 sudo rm
elif echo "$CMD" | grep -qE 'sudo[[:space:]]+rm[[:space:]]'; then
  LEVEL="🟡"; TRIGGER="sudo-rm"
  WARN="sudo rm — 권한 상승 삭제. 경로 다시 확인."
fi

if [ "$BLOCK" = "1" ]; then
  # 차단: stderr + exit 2. 파괴적 DB 실행만 여기 도달.
  cat >&2 <<EOF
[$LEVEL 차단] 파괴적 DB 명령 감지
  명령: $CMD
  → $WARN

정말 실행해야 한다면 사용자가 직접 터미널에서 실행하세요.
오탐이면 알려주세요(훅 패턴 조정).
EOF
  outcome_log "danger-keyword-detect" "block" "${LEVEL} ${WARN}" "$TRIGGER"
  exit 2
elif [ -n "$WARN" ]; then
  cat <<EOF
[$LEVEL 위험 명령 감지] $CMD
  → $WARN
  의도가 맞다면 진행. 의도와 다르면 중단(Ctrl+C).
EOF
  outcome_log "danger-keyword-detect" "warn" "${LEVEL} ${WARN}" "$TRIGGER"
else
  outcome_log "danger-keyword-detect" "pass" "" "no-match"
fi

exit 0
