#!/bin/zsh
# SessionStart: 위임 우선 원칙 컨텍스트 주입
# 매 세션 시작에 "직접 구현 금지, 위임 우선" 룰 강제

: "${HOME:?}"

cat <<'MSGEOF'
[위임 우선 원칙 — 토큰 효율]

이번 세션에서 Claude(나)는 오케스트레이터 역할.
직접 구현은 최소화하고 다음 룰에 따라 위임 우선:

| 작업 유형 | 위임 대상 | 트리거 |
|----------|----------|--------|
| 100줄+ 코드 구현 | Codex CLI (Skill ask-codex / codex exec / codex:rescue) | 대량 보일러플레이트, 신규 파일 |
| 1M 토큰 스캔 | Gemini (Skill ask-gemini) | 코드베이스 전체 분석, 영향도 |
| 단순 질의 (번역/요약/문법) | Ollama (Skill ask-ollama) | 200자 이하 발화 |
| 한국어 요약/번역 | Ollama qwen3.5:9b | 무료, 로컬 |
| 백그라운드 테스트/문서 | Jules | 시간 소요 작업 |
| 판단/리뷰/통합 | Claude (나) | 컨텍스트 유지 필요 |

직접 Edit/Write로 30줄+ 작성 = delegation-enforcer.sh 가 위임 권장 메시지 출력.
Bash heredoc으로 코드 파일 작성 = bash-codegen-block.sh 가 차단.

병렬 가능하면 반드시 병렬 (Codex + Gemini 동시 호출 등).
사용자가 "직접 구현해" 명시할 때만 위임 생략.
MSGEOF

exit 0
