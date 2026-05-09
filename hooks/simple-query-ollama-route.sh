#!/bin/zsh
# UserPromptSubmit: 단순 질의 감지 시 Ollama 라우팅 권장
# 비차단. 사용자 발화에서 "번역/요약/뜻/설명/짧은 코드 질문" 패턴 잡히면
# /ask-ollama 사용 권장 메시지 출력 (토큰 절약)
#
# 최적화: stdin 한 번만 변수에 적재 → bash regex 1차 필터로 95% 즉시 종료.
# python3는 매칭 후보일 때만 1회 호출. 평균 200ms+ → 목표 <50ms

: "${HOME:?}"

INPUT="$(cat)"
LEN=${#INPUT}

# 1차 필터: 빈 입력 또는 너무 큼 (긴 발화는 단순 질의 아님)
[ "$LEN" -eq 0 ] && exit 0
[ "$LEN" -gt 800 ] && exit 0

# 2차 필터: bash regex로 단순 질의 시그널이 있는지 빠르게 판별
# (python3 import json 콜드스타트 회피 — 95% 케이스에서 여기서 종료)
SIMPLE_RE='(번역|요약|뜻이|뜻은|뭐야|무슨 뜻|설명해|설명 좀|이거 뭐|이게 뭐|이름이 뭐|차이가 뭐|차이는|줄여줘|짧게|간단히|syntax|문법|에러 *뜻|이거 *되나|동작하나|쓸 수 *있어)'
EXPLICIT_RE='(/ask-|@dev|gemini|codex|gemma|ollama)'

# INPUT은 JSON 전체 — 우선 prompt 필드 외 잡음 줄이려고 INPUT 자체에 정규식 매칭
# (prompt 필드 뽑기 전 빠른 게이트)
if ! echo "$INPUT" | grep -qE "$SIMPLE_RE"; then
    exit 0
fi
if echo "$INPUT" | grep -qE "$EXPLICIT_RE"; then
    exit 0
fi

# 3차 단계: 실제 prompt 필드 추출 (여기 도달은 5% 미만)
PROMPT=$(echo "$INPUT" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(data.get("prompt", ""))
except Exception:
    pass
' 2>/dev/null)

[ -z "$PROMPT" ] && exit 0

PLEN=${#PROMPT}
[ "$PLEN" -gt 200 ] && exit 0

# prompt 본문에서 다시 한 번 패턴 검사 (JSON 잡음 제거 후 정확도 ↑)
SIMPLE_PATTERN='(번역|요약|뜻이|뜻은|뭐야|무슨 뜻|설명해|설명 좀|이거 뭐|이게 뭐|이름이 뭐|차이가 뭐|차이는|줄여줘|짧게|간단히)'
CODE_SIMPLE='(syntax|문법|에러[[:space:]]*뜻|이거[[:space:]]*되나|동작하나|쓸 수[[:space:]]*있어)'

if echo "$PROMPT" | grep -qiE "$EXPLICIT_RE"; then
    exit 0
fi

if echo "$PROMPT" | grep -qE "$SIMPLE_PATTERN"; then
    cat <<MSGEOF
[Ollama 라우팅 권장] 단순 질의 감지 (${PLEN}자)

토큰 절약을 위해 로컬 Ollama 사용 검토:
  - /ask-ollama "${PROMPT:0:60}..."
  - 한국어 요약/번역/단순 설명: qwen3.5:9b
  - 빠른 단답: gemma4:e4b

판단/설계가 필요한 질의면 무시하고 진행.
MSGEOF
    exit 0
fi

if echo "$PROMPT" | grep -qiE "$CODE_SIMPLE"; then
    cat <<MSGEOF
[Ollama 라우팅 권장] 코드 단순 질의 감지

  - /ask-ollama (qwen2.5-coder:14b)
  - 코드 컨벤션/문법 질문은 로컬에서 충분
MSGEOF
    exit 0
fi

exit 0
