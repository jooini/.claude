#!/bin/zsh
# Claude Code statusline - 활성 에이전트 표시 + MoAI statusline 통합
# 출력 구조: [에이전트 라벨] <moai statusline 본문>
# moai 가 없거나 .moai 가 없는 프로젝트는 기존 단순 라인으로 폴백.

INPUT=$(cat)

# jq 경로 (한번만 탐색)
JQ=$(command -v jq)
if [ -z "$JQ" ]; then exit 0; fi

# ANSI 색상 코드
RESET='\033[0m'
BOLD='\033[1m'

# 에이전트별 색상 매핑
agent_color() {
  case "$1" in
    backend-developer)   printf '\033[34m'   ;;  # blue
    frontend-developer)  printf '\033[33m'   ;;  # yellow
    ai-engineer)         printf '\033[32m'   ;;  # green
    code-tester)         printf '\033[36m'   ;;  # cyan
    code-reviewer)       printf '\033[35m'   ;;  # purple
    qa)                  printf '\033[95m'   ;;  # magenta
    designer)            printf '\033[91m'   ;;  # pink
    po)                  printf '\033[96m'   ;;  # teal
    data-analyst)        printf '\033[93m'   ;;  # orange
    ops-lead)            printf '\033[31m'   ;;  # red
    prompt-engineer)     printf '\033[97m'   ;;  # white
    *)                   printf '\033[0m'    ;;  # default
  esac
}

# 에이전트 이름을 한글 표시명으로 변환
agent_label() {
  case "$1" in
    backend-developer)   echo "백엔드" ;;
    frontend-developer)  echo "프론트" ;;
    ai-engineer)         echo "AI엔지니어" ;;
    code-tester)         echo "코드테스터" ;;
    code-reviewer)       echo "코드리뷰어" ;;
    qa)                  echo "큐에이" ;;
    designer)            echo "디자이너" ;;
    po)                  echo "피오" ;;
    data-analyst)        echo "데이터분석가" ;;
    ops-lead)            echo "옵스리드" ;;
    prompt-engineer)     echo "프롬프트엔지니어" ;;
    general-purpose)     echo "범용" ;;
    Explore)             echo "탐색" ;;
    Plan)                echo "계획" ;;
    *)                   echo "$1" ;;
  esac
}

# 기본 정보 추출
CWD=$(echo "$INPUT" | $JQ -r '.workspace.current_dir // .cwd // ""')
MODEL=$(echo "$INPUT" | $JQ -r '.model.display_name // ""')
TRANSCRIPT=$(echo "$INPUT" | $JQ -r '.transcript_path // ""')
USED_PCT=$(echo "$INPUT" | $JQ -r '.context_window.used_percentage // empty')
AGENT_NAME=$(echo "$INPUT" | $JQ -r '.agent.name // ""')

# 트랜스크립트에서 최근 활성 에이전트 목록 추출
ACTIVE_AGENTS_RAW=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  ACTIVE_AGENTS_RAW=$(tail -n 100 "$TRANSCRIPT" 2>/dev/null | \
    $JQ -r '
      select(.type == "assistant") |
      .message.content[]? |
      select(.type == "tool_use" and (.name == "Agent" or .name == "Task")) |
      .input.subagent_type // ""
    ' 2>/dev/null | \
    grep -v '^$' | \
    grep -v '__implicit_orchestrator__' | \
    tail -n 5 | \
    awk '!seen[$0]++')
fi

# --agent 플래그로 시작된 경우 단일 에이전트로 덮어씀
if [ -n "$AGENT_NAME" ]; then
  ACTIVE_AGENTS_RAW="$AGENT_NAME"
fi

# 에이전트 표시 문자열 조합
AGENT_PART=""
if [ -n "$ACTIVE_AGENTS_RAW" ]; then
  COLORED_LABELS=""
  FIRST_AGENT=$(echo "$ACTIVE_AGENTS_RAW" | head -n 1)
  MAIN_COLOR=$(agent_color "$FIRST_AGENT")

  while IFS= read -r agent; do
    color=$(agent_color "$agent")
    label=$(agent_label "$agent")
    if [ -n "$COLORED_LABELS" ]; then
      COLORED_LABELS="${COLORED_LABELS}\033[0m,"
    fi
    COLORED_LABELS="${COLORED_LABELS}${color}${BOLD}${label}"
  done <<< "$ACTIVE_AGENTS_RAW"

  AGENT_PART="${MAIN_COLOR}[${COLORED_LABELS}\033[0m${MAIN_COLOR}]\033[0m "
fi

# 디렉토리 축약
BASENAME_DIR=$(basename "$CWD")

# 컨텍스트 사용량
CTX_PART=""
if [ -n "$USED_PCT" ]; then
  PCT_INT=$(printf "%.0f" "$USED_PCT")
  if [ "$PCT_INT" -ge 80 ]; then
    CTX_PART=" \033[31mctx:${PCT_INT}%\033[0m"
  elif [ "$PCT_INT" -ge 50 ]; then
    CTX_PART=" \033[33mctx:${PCT_INT}%\033[0m"
  else
    CTX_PART=" ctx:${PCT_INT}%"
  fi
fi

# 모델 축약 (폴백 출력용)
SHORT_MODEL=$(echo "$MODEL" | sed \
  -e 's/Claude //' \
  -e 's/Opus \([0-9.]*\).*/O\1/' \
  -e 's/Sonnet \([0-9.]*\).*/S\1/' \
  -e 's/Haiku \([0-9.]*\).*/H\1/')

# MoAI statusline 위임 시도 — 프로젝트 루트에서 .moai 디렉토리 또는 status_line.sh 가 있고
# moai CLI 가 존재하면 풍부한 MoAI statusline 을 본문으로 사용.
MOAI_BODY=""
MOAI_BIN=$(command -v moai 2>/dev/null)
if [ -z "$MOAI_BIN" ] && [ -x "$HOME/go/bin/moai" ]; then
  MOAI_BIN="$HOME/go/bin/moai"
fi
if [ -z "$MOAI_BIN" ] && [ -x "$HOME/.local/bin/moai" ]; then
  MOAI_BIN="$HOME/.local/bin/moai"
fi

# .moai 디렉토리 탐색 (cwd 에서 상위로 거슬러 올라가며)
HAS_MOAI=0
SEARCH_DIR="$CWD"
while [ -n "$SEARCH_DIR" ] && [ "$SEARCH_DIR" != "/" ]; do
  if [ -d "$SEARCH_DIR/.moai" ]; then
    HAS_MOAI=1
    break
  fi
  SEARCH_DIR=$(dirname "$SEARCH_DIR")
done

if [ -n "$MOAI_BIN" ] && [ "$HAS_MOAI" -eq 1 ]; then
  MOAI_BODY=$(printf '%s' "$INPUT" | "$MOAI_BIN" statusline 2>/dev/null)
fi

# 최종 출력
if [ -n "$MOAI_BODY" ]; then
  # 에이전트 prefix 가 있으면 첫 줄 앞에 붙임. moai 출력은 다중 라인이므로 줄단위 처리 X — 통째로 출력.
  printf "%b%s" "${AGENT_PART}" "${MOAI_BODY}"
else
  # 폴백: 기존 단순 라인
  printf "%b%s" "${AGENT_PART}" "${BASENAME_DIR}"
  if [ -n "$SHORT_MODEL" ]; then
    printf " | %s" "$SHORT_MODEL"
  fi
  printf "%b" "${CTX_PART}"
fi
