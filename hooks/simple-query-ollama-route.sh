#!/bin/zsh
# UserPromptSubmit: 단순 질의 감지 시 Ollama 라우팅 권장
# 비차단. 사용자 발화에서 "번역/요약/뜻/설명/짧은 코드 질문" 패턴 잡히면
# /ask-ollama 사용 권장 메시지 출력 (토큰 절약)

: "${HOME:?}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c '
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(data.get("prompt", ""))
except Exception:
    pass
' 2>/dev/null)

[ -z "$PROMPT" ] && exit 0

# 짧은 발화만 대상 (200자 이하)
LEN=${#PROMPT}
[ "$LEN" -gt 200 ] && exit 0

# 단순 질의 패턴 (한글)
SIMPLE_PATTERN='(번역|요약|뜻이|뜻은|뭐야|무슨 뜻|설명해|설명 좀|이거 뭐|이게 뭐|이름이 뭐|차이가 뭐|차이는|줄여줘|짧게|간단히)'
# 코드 단순 질의
CODE_SIMPLE='(syntax|문법|에러[[:space:]]*뜻|이거[[:space:]]*되나|동작하나|쓸 수[[:space:]]*있어)'

# 명시적 위임 키워드는 hook 작동 안 함 (이미 사용자가 라우팅 의도)
EXPLICIT='(/ask-|@dev|gemini|codex|gemma|ollama)'

if echo "$PROMPT" | grep -qiE "$EXPLICIT"; then
  exit 0
fi

if echo "$PROMPT" | grep -qE "$SIMPLE_PATTERN"; then
  cat <<MSGEOF
[Ollama 라우팅 권장] 단순 질의 감지 (${LEN}자)

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
