#!/bin/zsh
# PostToolUse: 위험 명령 실행 감지 및 알림

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')

# 위험 패턴 목록
DANGEROUS=0
WARN_MSG=""
TRIGGER=""

if echo "$COMMAND" | grep -qE 'rm\s+(-rf|-fr|--recursive)'; then
  DANGEROUS=1; WARN_MSG="파일 삭제"; TRIGGER="rm-recursive"
elif echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force'; then
  DANGEROUS=1; WARN_MSG="강제 푸시"; TRIGGER="git-push-force"
elif echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  DANGEROUS=1; WARN_MSG="하드 리셋"; TRIGGER="git-reset-hard"
elif echo "$COMMAND" | grep -qE 'git\s+clean\s+-f'; then
  DANGEROUS=1; WARN_MSG="깃 클린"; TRIGGER="git-clean-force"
elif echo "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE|INDEX)'; then
  DANGEROUS=1; WARN_MSG="디비 삭제"; TRIGGER="sql-drop"
elif echo "$COMMAND" | grep -qiE 'TRUNCATE\s+TABLE'; then
  DANGEROUS=1; WARN_MSG="테이블 초기화"; TRIGGER="sql-truncate"
elif echo "$COMMAND" | grep -qE 'git\s+branch\s+-D'; then
  DANGEROUS=1; WARN_MSG="브랜치 강제 삭제"; TRIGGER="git-branch-force-delete"
elif echo "$COMMAND" | grep -qE 'docker\s+(system\s+prune|rm\s+-f|rmi\s+-f)'; then
  DANGEROUS=1; WARN_MSG="도커 정리"; TRIGGER="docker-prune"
fi

if [ "$DANGEROUS" -eq 1 ]; then
  say -v Yuna "주의! ${WARN_MSG} 명령이 실행되었습니다" < /dev/null &
  outcome_log "dangerous-command-detect" "warn" "$WARN_MSG" "$TRIGGER"
else
  outcome_log "dangerous-command-detect" "pass" "" "no-match"
fi
