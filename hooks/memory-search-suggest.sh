#!/bin/zsh
# UserPromptSubmit: 작업 키워드 감지 시 메모리/RAG 검색 제안 컨텍스트 주입
#
# 목적: claude-mem (과거 세션) + local-rag (코드/문서) 검색을 작업 시작 전 자동 권유
# 효과: "이전에 같은 문제 풀었나?" 자동 체크 → 같은 추정 두 번 금지 규칙 강제
#
# 동작 조건:
#   1. 작업 키워드 감지 (구현/버그/리팩터/디자인/배포/문서)
#   2. 너무 짧은 프롬프트(질문/대화) 스킵
#   3. 이미 mem-search/RAG 호출 명시한 경우 스킵

: "${HOME:?}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 2000)

# 너무 짧으면 단순 대화 — 스킵
PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -lt 15 ]; then
    exit 0
fi

# 이미 검색 명시 — 스킵
if echo "$PROMPT" | grep -qiE '(mem.search|local.rag|이전에.*풀|예전에.*해|과거.*솔루션)'; then
    exit 0
fi

# 작업 키워드 — 메모리 검색 가치 있는 경우만
TRIGGER=""
if echo "$PROMPT" | grep -qiE '(구현|만들어|추가|기능|feature)'; then
    TRIGGER="기능/구현"
elif echo "$PROMPT" | grep -qiE '(버그|에러|오류|bug|fix|안 ?돼|작동 ?안)'; then
    TRIGGER="버그/에러"
elif echo "$PROMPT" | grep -qiE '(리팩터|정리|개선|refactor)'; then
    TRIGGER="리팩터"
elif echo "$PROMPT" | grep -qiE '(설계|아키텍처|architecture|마이그레이션|migration)'; then
    TRIGGER="설계/아키텍처"
elif echo "$PROMPT" | grep -qiE '(쿼리|query|SQL|성능|performance|optim)'; then
    TRIGGER="쿼리/성능"
elif echo "$PROMPT" | grep -qiE '(배포|deploy|Docker|Terraform|infra)'; then
    TRIGGER="배포/인프라"
else
    # 작업 키워드 없음 — 단순 대화/질문, 스킵
    exit 0
fi

# 검색 키워드 후보 추출 (한글/영문 명사형 단어 4글자+)
KEYWORDS=$(echo "$PROMPT" | grep -oE '[가-힣A-Za-z][가-힣A-Za-z_]{3,}' | head -5 | tr '\n' ' ')

cat <<EOF
[메모리 검색 필수] 작업 유형: $TRIGGER

⚠️ 답변 시작 전 다음 2개 검색을 **반드시** 실행한 후 진행:

1. **mcp__plugin_claude-mem_mcp-search__search** 호출
   - query: "$KEYWORDS"
   - 과거 세션에서 같은/유사 작업 처리 기록 확인

2. **mcp__local-rag__query_documents** 호출
   - query: "$KEYWORDS"
   - 1549개 문서/13594 청크에서 관련 코드/문서 의미 검색

규칙:
- 검색 결과 있으면 → 첫 응답에 "이전에 [요약] 처리한 기록 있음" 명시 후 진행
- 검색 결과 없으면 → "메모리 검색 결과 없음, 신규 작업으로 시작" 명시 후 진행
- 검색 호출 자체를 생략하고 답변하면 "같은 추정 두 번 금지" 규칙 위반

키워드만 봐서 무관한 작업이면 검색 후 "결과 무관, 스킵" 명시하고 진행.
EOF

exit 0
