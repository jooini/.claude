#!/bin/zsh
# UserPromptSubmit: 사용자가 직전 답변에 추정/오류 정정하면 다음 답변에 검증 강화 메시지 주입
#
# 트리거 (사용자 발화에서 정정 신호 감지):
#   - "아니야", "아니 ", "아니지" — 부정/정정
#   - "틀렸어", "잘못", "왜 자꾸" — 오류 지적
#   - "검증해", "확인해봐", "다시" — 재검증 요구
#   - "확실해?", "맞아?", "맞는거" — 확실성 의심
#   - "추측", "추정" — 메타 지적
#
# 효과: 직전 응답에 추정 있었음 → 다음 응답은 검증 우선

: "${HOME:?}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 2000)

PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -lt 3 ]; then
    exit 0
fi

# 정정 신호 감지
SIGNAL=""
if echo "$PROMPT" | grep -qiE '(^아니야|^아니지|^아니 |\s아니야|\s아니지)'; then
    SIGNAL="부정/정정"
elif echo "$PROMPT" | grep -qiE '(틀렸|잘못|왜 자꾸|왜 그래|왜 또)'; then
    SIGNAL="오류 지적"
elif echo "$PROMPT" | grep -qiE '(추정|추측|가정)'; then
    SIGNAL="추정 메타 지적"
elif echo "$PROMPT" | grep -qiE '(확실 ?\?|확실해 ?\?|진짜 ?\?|맞 ?아 ?\?)'; then
    SIGNAL="확실성 의심"
elif echo "$PROMPT" | grep -qiE '(다시 ?확인|확인해봐|확인 ?좀|검증해)'; then
    SIGNAL="재검증 요구"
fi

if [ -z "$SIGNAL" ]; then
    exit 0
fi

cat <<EOF
[⚠️ 검증 강화 모드 — 직전 응답에 정정 신호 감지]

신호: $SIGNAL

다음 응답은 반드시:

1. **검증 먼저, 답변 나중**
   - 모든 사실 주장 전 Read/Grep/Bash로 코드/시스템 직접 확인
   - 검증 안 한 것은 "검증 못 함" 명시
   - "아마/추정/같은데/인 듯" 단어 사용 금지

2. **정정 사유 명확히**
   - 직전 답변 어디가 틀렸는지 사용자 발화에서 추출
   - 정정된 사실로 다시 답변

3. **이전 추정 두 번 금지** (CLAUDE.md 룰)
   - 이번에 다시 추정하면 사용자 신뢰 손상
   - 검증 도구 모두 동원: Read, Grep, mcp__local-rag, mcp__plugin_claude-mem_mcp-search

4. **이번 정정 후 같은 패턴 발생 시**:
   - hook 감지 → ultrathink 모드 자동 발동
   - Gemini/Codex/Gemma 3중 호출 권장

이번 답변에 "검증 결과:" 섹션 명시적으로 포함할 것.
EOF

exit 0
