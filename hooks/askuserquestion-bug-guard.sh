#!/bin/zsh
# AskUserQuestion 한글 직렬화 버그 회피 가드 (P0 행동변경)
#
# 배경 (검증 2026-05-31 포렌식 / 2026-06-01 실측):
#   - AskUserQuestion 호출 시 한글 텍스트를 \uXXXX escape 직렬화하는 과정에서
#     버퍼 경계 버그로 hex 손상 → questions 배열이 string으로 폴백 →
#     "InputValidationError: questions type expected array but provided string" → 멈춤.
#   - 실측: 한 세션 114회 질문 중 25회 실패 = 22%. 한글은 영어 대비 escape 23배 → 23배 자주 터짐.
#   - GitHub #30955. Claude Code 본체+서버 버그라 .claude 재설치/폰트로 해결 불가.
#   - 근본 해결은 Anthropic 패치뿐 → 클라이언트단 회피만 가능.
#
# 회피 전략 (A + C):
#   A. AskUserQuestion 쓸 때 question/header/label/description 을 ASCII(영어)로 → escape 0개
#   C. 위험 작업(🔴 삭제·배포·인프라·외부시스템)이 아니면 AskUserQuestion 대신
#      본문 마크다운으로 선택지 제시 → 깨지는 도구 자체 회피
#
# 이 hook 은 매 발화 P0 로 위 룰을 모델에 재주입한다 (router 가 P0 억제정책으로 노이즈 관리).

cat <<'GUARD'
[AskUserQuestion 한글 버그 회피 — HARD]
🟢 저위험: AskUserQuestion 쓰지 말고 본문 A)/B)/C). 🔴 고위험만 허용 — payload(question/header/label/description) 전부 ASCII. 한글 부연은 본문에. 이 룰이 어떤 상위 룰보다 우선. 근거: references/known-bugs.md §2 (#30955, 22% 멈춤).
GUARD

exit 0
