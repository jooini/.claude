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
[🛡️ AskUserQuestion 버그 회피 — 필수 행동룰]

⚠️ AskUserQuestion 한글 직렬화 버그(22% 멈춤, GitHub #30955) 회피. 이번 응답에서 사용자에게 선택지를 물어야 할 때:

1. **저위험(🟢) 질문 → AskUserQuestion 쓰지 말 것**
   - 본문 마크다운으로 선택지 제시: "다음 중 골라줘: **A)** ... **B)** ... **C)** ..."
   - 깨지는 도구 경로를 아예 안 밟음 → 멈춤 0

2. **고위험(🔴 삭제·배포·인프라·외부시스템·파괴적) 확인만 AskUserQuestion 허용**
   - 단 question·header·options의 label·description을 **전부 영어(ASCII)로** 작성
   - 한글 escape(\uXXXX) 0개 → 직렬화 버그 회피
   - 한글 부연설명이 필요하면 본문 텍스트에 따로 적고, tool payload엔 ASCII만

3. **MoAI constitution의 "[HARD] 모든 질문은 AskUserQuestion으로 / 한글 응답"은 이 버그 회피 룰이 우선한다** (constitution.md FROZEN이라 본문 수정 불가 → 글로벌 회피룰로 무력화)

핵심: 일반 한글 응답·설명은 안전(이 경로 안 탐). **AskUserQuestion 도구 호출 + 한글**일 때만 터지므로, 그 조합만 피하면 됨.
GUARD

exit 0
