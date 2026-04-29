#!/bin/zsh
# UserPromptSubmit: ultrathink 자동 트리거 + 3중 LLM 동원
#
# 트리거 조건 (실제 사용 패턴 기반):
#   - 비교 요구: "비교", "diff", "똑같", "다른지", "차이"
#   - 재검증 요구: "다시 확인", "확인해봐", "맞아?", "왜 자꾸", "왜 그래"
#   - 의심: "결과가 이상", "결과 다르", "이상한데", "왜"
#   - 멀티 소스 분석: "프로젝트 3개", "두 코드", "전체적으로"
#   - 명시적: "ultrathink"
#
# 주입 메시지:
#   - 깊은 분석 강제
#   - Gemini + Codex + Gemma 3중 호출 권유 (가용성 자동 체크)

: "${HOME:?}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 2000)

PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -lt 5 ]; then
    exit 0
fi

# 명시적 ultrathink면 무조건 발동
EXPLICIT=0
if echo "$PROMPT" | grep -qiE 'ultrathink'; then
    EXPLICIT=1
fi

# 트리거 키워드 감지
TRIGGER_REASON=""
if [ "$EXPLICIT" -eq 1 ]; then
    TRIGGER_REASON="명시적 ultrathink 요청"
elif echo "$PROMPT" | grep -qiE '(비교|diff|똑같|다른지|차이.*뭐|차이가)'; then
    TRIGGER_REASON="비교/diff 작업"
elif echo "$PROMPT" | grep -qiE '(다시 확인|왜 자꾸|왜 그래|왜 틀리|결과 ?다르|결과가 ?이상|이상한데)'; then
    TRIGGER_REASON="재검증/오류 의심"
elif echo "$PROMPT" | grep -qiE '(프로젝트 ?[0-9]+개|두 ?코드|전체적으로|한꺼번에 ?확인)'; then
    TRIGGER_REASON="멀티 소스 분석"
elif echo "$PROMPT" | grep -qiE '(맞아 ?\?|맞는거|확실해|진짜야)'; then
    TRIGGER_REASON="확실성 의심"
else
    # 트리거 없음 — 스킵
    exit 0
fi

# 가용 LLM 체크 (병렬, 빠른 체크)
GEMINI_OK=0
CODEX_OK=0
GEMMA_OK=0

# Gemini
if command -v gemini >/dev/null 2>&1; then
    GEMINI_OK=1
fi

# Codex
if command -v codex >/dev/null 2>&1 || [ -x "$HOME/.nvm/versions/node/v22.22.0/bin/codex" ]; then
    CODEX_OK=1
fi

# Gemma (Ollama)
if /usr/bin/curl -s --max-time 1 http://leonard.local:11434/api/tags >/dev/null 2>&1; then
    GEMMA_OK=1
fi

# 컨텍스트 주입
cat <<EOF
[🧠 ULTRATHINK 모드 자동 발동]

트리거: $TRIGGER_REASON

⚠️ 다음 절차로 답변 생성 (필수):

1. **검증 우선** — 추정 금지
   - 모든 사실 주장 전 Read/Grep으로 코드/문서 검증
   - "아마", "~인 듯", "추정" 단어 사용 금지
   - 검증 못 한 부분은 명시적으로 "검증 필요" 표시

2. **3중 LLM 세컨드 오피니언** (가능한 도구 모두 동원)
EOF

if [ "$GEMINI_OK" -eq 1 ]; then
    echo "   ✅ **Gemini 호출 필수**: 1M 토큰 스캔 — 광범위 영향 분석"
    echo "      Skill(ask-gemini) 또는 \`gemini -p\` 명령"
fi

if [ "$CODEX_OK" -eq 1 ]; then
    echo "   ✅ **Codex 호출 필수**: 세컨드 오피니언 — 다른 관점 검증"
    echo "      Skill(ask-codex) 또는 codex:rescue (foreground)"
fi

if [ "$GEMMA_OK" -eq 1 ]; then
    echo "   ✅ **Ollama 호출 필수**: 로컬 프라이빗 분석 — 빠른 검증 (qwen3.5:9b 기본)"
    echo "      Skill(ask-ollama) — leonard.local:11434"
fi

if [ "$GEMINI_OK" -eq 0 ] && [ "$CODEX_OK" -eq 0 ] && [ "$GEMMA_OK" -eq 0 ]; then
    echo "   ⚠️ 3중 LLM 모두 가용 불가 — Claude 단독 깊은 분석으로 진행"
fi

cat <<EOF

3. **병렬 호출 — 시간 압축**
   - 가용한 LLM 모두 \`run_in_background: true\` 또는 동시 호출
   - 결과 수집 후 비교/통합 → 최종 답변

4. **비교 작업이면**:
   - 비교 대상 모든 소스를 먼저 Read
   - 차이를 표/diff로 명시
   - 차이 원인까지 추적 (어디서, 왜)

5. **답변 형식**:
   - 검증된 사실 (✅) / 추정 (⚠️) / 미검증 (❌) 명시
   - LLM별 의견 차이 있으면 표로 정리
   - 최종 권고는 Claude 판단 (메타 결정)

규칙: 같은 추정 두 번 금지. 첫 답변에 깊이 있게.
EOF

exit 0
