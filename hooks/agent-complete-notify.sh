#!/bin/zsh
# PostToolUse: 에이전트 완료 알림

INPUT=$(cat)

# 백그라운드 에이전트는 제외 (PostToolUse가 launch 시점에 트리거되므로)
if echo "$INPUT" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# subagent_type 추출
AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# 오케스트레이터는 제외
if [ "$AGENT_TYPE" = "__implicit_orchestrator__" ]; then
  exit 0
fi

# 에이전트 타입 한글 변환
case "$AGENT_TYPE" in
  Explore) MSG="탐색" ;;
  Plan) MSG="계획" ;;
  Bash) MSG="배시" ;;
  general-purpose) MSG="범용" ;;
  backend-developer) MSG="백엔드" ;;
  code-reviewer) MSG="코드 리뷰" ;;
  code-tester) MSG="테스트" ;;
  frontend-developer) MSG="프론트엔드" ;;
  prompt-engineer) MSG="프롬프트" ;;
  designer) MSG="디자이너" ;;
  qa) MSG="큐에이" ;;
  data-analyst) MSG="데이터" ;;
  *) MSG="서브" ;;
esac

say -v Yuna "${MSG} 에이전트 완료" < /dev/null &
