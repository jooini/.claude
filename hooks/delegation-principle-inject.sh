#!/bin/zsh
# SessionStart: 위임 우선 원칙 컨텍스트 주입
# 매 세션 시작에 "직접 구현 금지, 위임 우선" 룰 강제

: "${HOME:?}"

cat <<'MSGEOF'
[위임 우선] Claude=오케스트레이터. 100줄+/신규파일→Codex(ask-codex), 코드베이스 스캔→Gemini(ask-gemini), 짧은 질의→Ollama(ask-ollama), 판단/통합→Claude. 50줄+ Edit/Write는 delegation-enforcer.sh 차단(exit 2). 우회: "직접 구현해". 병렬 가능시 반드시 병렬. 상세 트리거표: CLAUDE.md §7.
MSGEOF

exit 0
