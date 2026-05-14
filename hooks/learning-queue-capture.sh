#!/bin/zsh
# UserPromptSubmit: 사용자가 모르는 개념 발화 시 학습 큐 자동 캡처
#
# 트리거 (의문/탐색 신호):
#   - "X가 뭐야?", "어떻게 동작?", "왜?", "이해 안 가"
#   - "X 원리", "차이점", "vs"
#   - "처음 봐", "처음 들어"
#
# 효과: 모르는 개념 자동 누적 → 일요일 학습 시간에 정리
# 저장: ~/.claude/learning-queue.md (Obsidian 동기화)

: "${HOME:?}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 2000)

PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -lt 5 ]; then
    exit 0
fi

# 의문/학습 신호 감지
TOPIC=""
if echo "$PROMPT" | grep -qiE '(이게 ?뭐|뭐야 ?\?|뭐임 ?\?|뭐 ?하는|어떻게 ?동작|어떻게 ?돌|어떻게 ?작동)'; then
    TOPIC="개념 의문"
elif echo "$PROMPT" | grep -qiE '(왜 ?이렇|왜 ?그렇|이유 ?뭐|이유가|원리)'; then
    TOPIC="원리/이유"
elif echo "$PROMPT" | grep -qiE '(차이 ?점|vs |비교 ?해줘|다른점)'; then
    TOPIC="비교/차이"
elif echo "$PROMPT" | grep -qiE '(처음 ?봐|처음 ?들|모르겠|이해 ?안)'; then
    TOPIC="신규 개념"
elif echo "$PROMPT" | grep -qiE '(어떻게 ?하|어떻게 ?쓰|어떻게 ?구현)'; then
    TOPIC="how-to"
fi

if [ -z "$TOPIC" ]; then
    exit 0
fi

# 차단 로그 헬퍼
BLOCK_LOG="$HOME/.claude/cache/learning-queue-blocked.log"
/bin/mkdir -p "$(/usr/bin/dirname "$BLOCK_LOG")"
log_block() {
    /bin/echo "$(/bin/date +%Y-%m-%dT%H:%M:%S) [$1] $(echo "$PROMPT" | /usr/bin/head -c 100)" >> "$BLOCK_LOG"
}

# 필터 1: 감정/짜증 표현
if echo "$PROMPT" | /usr/bin/grep -qiE '(ㅡㅡ|ㅠㅠ|ㅜㅜ|뭐하는 ?거냐|멈춰|뭐 ?시켰|니멋대로|아니 ?ㅡ|개같|짜증|화나)'; then
    log_block "EMOTION"
    exit 0
fi

# 필터 2: 너무 짧은 단편 (4단어 미만 + 영문 식별자 없음)
WORD_COUNT=$(echo "$PROMPT" | /usr/bin/wc -w | /usr/bin/tr -d ' ')
if [ "$WORD_COUNT" -lt 4 ] && ! echo "$PROMPT" | /usr/bin/grep -qE '[A-Za-z_]{3,}'; then
    log_block "SHORT_FRAGMENT"
    exit 0
fi

# 필터 3: 작업 지시 (학습 X)
if echo "$PROMPT" | /usr/bin/grep -qiE '(구현해|만들어|처리해|수정해|고쳐|진행해|작성해)'; then
    log_block "TASK_REQUEST"
    exit 0
fi

# 필터 4: 코드 한정 단순 질문 (함수명() + 6단어 미만)
if echo "$PROMPT" | /usr/bin/grep -qE '[a-zA-Z_]+\(\)' && [ "$WORD_COUNT" -lt 6 ]; then
    log_block "CODE_SPECIFIC_FRAGMENT"
    exit 0
fi

# 슬래시 명령은 제외 (이미 알고 호출 중)
if echo "$PROMPT" | grep -qE '^/'; then
    exit 0
fi

# 큐 파일 (Obsidian 직접 저장)
QUEUE="$HOME/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md"
/bin/mkdir -p "$(/usr/bin/dirname "$QUEUE")"

# 헤더 없으면 생성
if [ ! -f "$QUEUE" ]; then
    cat > "$QUEUE" <<HEADER
---
type: learning-queue
created: $(/bin/date +%Y-%m-%d)
---

# 학습 큐 — 모르는 개념 자동 누적

매주 일요일 학습 시간에 정리. \`/deep-learn\` 으로 일괄 분석 가능.

HEADER
fi

# 중복 방지: 직전 1시간 내 같은 프롬프트면 스킵
LAST_LINE=$(/usr/bin/tail -50 "$QUEUE" 2>/dev/null | /usr/bin/grep -F "$(echo "$PROMPT" | /usr/bin/head -c 80)" | /usr/bin/head -1)
if [ -n "$LAST_LINE" ]; then
    exit 0
fi

# 큐에 추가
DATE_NOW=$(/bin/date +%Y-%m-%d)
TIME_NOW=$(/bin/date +%H:%M)
PROMPT_PREVIEW=$(echo "$PROMPT" | /usr/bin/head -c 150 | /usr/bin/tr '\n' ' ')

cat >> "$QUEUE" <<EOF
- [ ] **$DATE_NOW $TIME_NOW** [$TOPIC] $PROMPT_PREVIEW
EOF

# 컨텍스트 주입 — 학습 큐에 추가됐다고 알림 (조용히)
cat <<EOF
[💡 학습 큐 자동 캡처]

이 질문이 학습 큐에 추가됨: \`Learning/learning-queue.md\`
- 카테고리: $TOPIC
- 매주 일요일 \`/deep-learn\` 실행 시 일괄 정리

답변할 때 단순 답만 하지 말고:
- **왜 그렇게 동작하는지 원리** 설명
- **유사 개념과의 차이**
- **함정/주의점**
- 가능하면 **공식 문서 링크** 추가

→ 본인 학습 자료가 자동으로 누적됨
EOF

exit 0
