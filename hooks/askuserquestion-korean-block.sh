#!/bin/zsh
# PreToolUse(AskUserQuestion): 한글(non-ASCII) AskUserQuestion 호출 물리 차단
#
# 배경 (검증 2026-06-01 포렌식):
#   - AskUserQuestion 호출 시 한글 텍스트를 \uXXXX escape 직렬화하는 과정의
#     버퍼 경계 버그로 questions 배열이 string으로 폴백 →
#     "InputValidationError: questions type expected array but provided string" → 멈춤.
#   - GitHub #30955. Claude Code 본체+서버 버그라 클라이언트단 회피만 가능.
#
# 왜 텍스트 권고 hook(askuserquestion-bug-guard.sh)으로 불충분했나:
#   - 그 hook 은 UserPromptSubmit 단계에서 "한글 AskUserQuestion 쓰지 마"를 텍스트로 권고만 함.
#   - 권고는 강제가 아니라 MoAI constitution [HARD]("무조건 AskUserQuestion + 한글")가 이김.
#   - 실측: 회피 hook 커밋(KST 20:26) 이후에도 같은 세션에서 AskUserQuestion 에러 신규 발생
#     (latest 21:42). → 텍스트 권고형 회피 실패 확정.
#
# 동작 (물리 차단):
#   - tool_name == AskUserQuestion 이고 payload 에 non-ASCII(한글 등) 가 있으면 exit 2 차단.
#   - stderr 피드백으로 "본문 마크다운 A)/B)/C) 로 다시 물어라" 지시.
#   - ASCII-only payload(고위험 영어 질문)는 통과 → escape 0개라 버그 안 터짐.
#
# fail-open 안전장치:
#   - tool_name 못 읽으면 통과
#   - AskUserQuestion 아니면 통과
#   - payload 파싱 실패하면 통과 (막다가 정상 작업 깨뜨리지 않음)

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

# tool_name 추출 — AskUserQuestion 아니면 관심 없음
TOOL=$(python3 - "$INPUT_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("tool_name", ""))
except Exception:
    pass
PYEOF
)

[ "$TOOL" != "AskUserQuestion" ] && exit 0

# payload 전체 문자열에서 non-ASCII 존재 여부 판정.
# questions[].question / header / options[].label / options[].description 를 모두 훑는다.
HAS_NONASCII=$(python3 - "$INPUT_FILE" <<'PYEOF'
import sys, json

def collect_text(ti):
    parts = []
    for q in ti.get("questions", []) or []:
        if not isinstance(q, dict):
            # questions 가 이미 string 으로 깨진 경우 등 — 방어적으로 통째로 검사
            parts.append(str(q))
            continue
        parts.append(str(q.get("question", "")))
        parts.append(str(q.get("header", "")))
        for opt in q.get("options", []) or []:
            if isinstance(opt, dict):
                parts.append(str(opt.get("label", "")))
                parts.append(str(opt.get("description", "")))
            else:
                parts.append(str(opt))
    return "".join(parts)

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    ti = data.get("tool_input", {})
    if not isinstance(ti, dict):
        ti = {}
    text = collect_text(ti)
    # non-ASCII(코드포인트 > 127) 한 글자라도 있으면 1
    nonascii = any(ord(c) > 127 for c in text)
    print("1" if nonascii else "0")
except Exception:
    # 파싱 실패 → fail-open
    print("0")
PYEOF
)

if [ "$HAS_NONASCII" = "1" ]; then
  cat >&2 <<'MSGEOF'
[차단] 한글이 포함된 AskUserQuestion 호출 감지

이유: AskUserQuestion 에 한글(non-ASCII)이 들어가면 \uXXXX escape 직렬화
      버퍼 경계 버그로 22% 확률 멈춤(InputValidationError, GitHub #30955).
      텍스트 권고만으로 못 막아서 이 PreToolUse 훅이 물리 차단함.

대안 (둘 중 하나로 다시):
  1. 저위험 질문 → AskUserQuestion 쓰지 말고 응답 본문 마크다운으로:
       "다음 중 골라줘: **A)** ... **B)** ... **C)** ..."
  2. 고위험(삭제·배포·인프라·외부시스템·파괴적) 확인만 AskUserQuestion 허용하되
       question·header·label·description 을 전부 영어(ASCII)로 작성.
       한글 부연설명은 응답 본문 텍스트에 따로.
MSGEOF
  type outcome_log >/dev/null 2>&1 && outcome_log "askuserquestion-korean-block" "block" "AskUserQuestion" "nonascii-payload"
  exit 2
fi

type outcome_log >/dev/null 2>&1 && outcome_log "askuserquestion-korean-block" "pass" "AskUserQuestion" "ascii-only"
exit 0
