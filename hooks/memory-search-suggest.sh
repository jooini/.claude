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

# 너무 짧으면 단순 대화 — 스킵 (임계값 낮춤: 15→8)
PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -lt 8 ]; then
    exit 0
fi

# 이미 검색 명시 — 스킵
if echo "$PROMPT" | grep -qiE '(mem.search|local.rag|이전에.*풀|예전에.*해|과거.*솔루션)'; then
    exit 0
fi

# 단순 인사/짧은 응답 화이트리스트 — 스킵
if echo "$PROMPT" | grep -qiE '^(안녕|네|넵|응|어|ㅇㅇ|ㄴㄴ|ok|okay|yes|no|알았|고마워|감사)[[:space:]\.\!\?]*$'; then
    exit 0
fi

# 작업 키워드 — 메모리 검색 가치 있는 경우 우선 매칭
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
elif echo "$PROMPT" | grep -qiE '(설명|분석|조사|진단|이해|도식|문서|원인|이유|왜|어떻게|뭐야|뭐임|어디|어느|어떡|어떻|뭐지|뭔|뭣|확인|체크|점검|찾아|봐줘|알려|보여|어떤|얼마|언제|누가)'; then
    TRIGGER="조사/분석"
elif echo "$PROMPT" | grep -qiE '(이거|이게|이건|저거|저게|그거|그게|그래서|그럼|그러면|그리고|아니|맞아|맞지|되나|되는|안되|안돼|할까|하면|할래|해줘|해라|해보|문제|상관|관련|차이|영향|결과|상태|현재|지금)'; then
    TRIGGER="후속/확인"
else
    # 키워드 미매칭 → 단순 대화/진행, 스킵 (폴백 제거: 노이즈 감축)
    exit 0
fi

# 검색 키워드 후보 추출 (한글/영문 명사형 단어 4글자+)
KEYWORDS=$(echo "$PROMPT" | grep -oE '[가-힣A-Za-z][가-힣A-Za-z_]{3,}' | head -5 | tr '\n' ' ')

# 작업 유형별 도구 라우팅
# - local-rag = 코드/문서 의미론 검색 (현재 코드베이스)
# - claude-mem = 과거 세션 결정/실패 패턴 (시간축)
# - 둘 다 = 디버깅/아키텍처/고위험 변경
case "$TRIGGER" in
    "기능/구현"|"리팩터"|"쿼리/성능"|"배포/인프라")
        ROUTING="local-rag"
        ;;
    "설계/아키텍처"|"버그/에러")
        ROUTING="both"
        ;;
    "조사/분석"|"후속/확인"|"일반작업(15자+ 폴백)")
        ROUTING="claude-mem"
        ;;
    *)
        ROUTING="both"
        ;;
esac

case "$ROUTING" in
    "local-rag")
        cat <<EOF
[지식 검색 권고] 작업 유형: $TRIGGER → local-rag 우선

⚠️ 답변 시작 전 **mcp__local-rag__query_documents** 호출 권고:
  - query: "$KEYWORDS"
  - 4324 docs / 56036 chunks 에서 의미론적 코드/문서 검색

규칙:
- 결과 있으면 → "이전에 [요약] 처리한 기록 있음" 명시 후 진행
- 결과 없으면 → "검색 결과 없음, 신규 작업" 명시 후 진행
- 호출 자체 생략 시 "같은 추정 두 번 금지" 규칙 위반
EOF
        ;;
    "claude-mem")
        cat <<EOF
[지식 검색 권고] 작업 유형: $TRIGGER → claude-mem 우선

⚠️ 답변 시작 전 **mcp__plugin_claude-mem_mcp-search__search** 호출 권고:
  - query: "$KEYWORDS"
  - 과거 세션 결정/실패 패턴/유사 처리 기록 검색

규칙:
- 결과 있으면 → "이전에 [요약] 처리한 기록 있음" 명시 후 진행
- 결과 없으면 → "검색 결과 없음, 신규 작업" 명시 후 진행
- 호출 자체 생략 시 "같은 추정 두 번 금지" 규칙 위반
EOF
        ;;
    "both")
        cat <<EOF
[지식 검색 필수] 작업 유형: $TRIGGER → 둘 다 호출 (디버깅/설계 — 고위험)

⚠️ 답변 시작 전 다음 2개 **반드시** 호출:

1. **mcp__plugin_claude-mem_mcp-search__search**
   - query: "$KEYWORDS"
   - 과거 세션 결정/실패 패턴

2. **mcp__local-rag__query_documents**
   - query: "$KEYWORDS"
   - 현재 코드/문서 의미 검색

규칙:
- 결과 있으면 → "이전에 [요약] 처리한 기록 있음" 명시 후 진행
- 결과 없으면 → "검색 결과 없음, 신규 작업" 명시 후 진행
- 호출 생략 시 "같은 추정 두 번 금지" 규칙 위반
EOF
        ;;
esac

exit 0
