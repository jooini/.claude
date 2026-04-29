#!/bin/zsh
# 에이전트 시작 시 음성 알림

# stdin에서 JSON 읽기
INPUT=$(cat)

# subagent_type 추출
AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# 오케스트레이터는 알림 제외
if [ "$AGENT_TYPE" = "__implicit_orchestrator__" ]; then
  exit 0
fi

# 에이전트 타입을 한글로 변환
case "$AGENT_TYPE" in
  Explore) MSG="탐색" ;;
  Plan) MSG="계획" ;;
  Bash) MSG="배시" ;;
  general-purpose) MSG="범용" ;;
  backend-developer) MSG="백엔드" ;;
  code-reviewer) MSG="코드 리뷰" ;;
  frontend-developer) MSG="프론트엔드" ;;
  *) MSG="서브" ;;
esac

say -v Yuna "${MSG} 에이전트 실행" < /dev/null &
