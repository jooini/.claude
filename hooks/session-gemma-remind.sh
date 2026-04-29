#!/bin/bash
# 세션 시작 시 Gemma(로컬 Ollama) 활용을 강제 리마인드
cat <<'EOF'
[Gemma 활용 규칙 — 무조건 적용]
로컬 Ollama Gemma(leonard.local:11434)를 다음 상황에서 반드시 활용할 것:
- 세컨드 오피니언이 필요한 판단/설계 결정
- 민감 데이터(사내/고객 정보) 포함 질의 — 외부 API 차단 대상
- 간단한 아이디어 발산/브레인스토밍 초기 단계
- 오프라인/프라이빗 질의
- 코드 리뷰 보조 및 설명 생성 (외부 전송 부적합)
호출: /ask-gemma 스킬 또는 Skill(ask-gemma) 직접 사용.
Codex/Gemini와 역할 분담 — Gemma는 프라이빗/로컬/빠른 브레인스토밍 담당.
EOF
