# SDD / TDD / 컨텍스트 관리

## SDD (Spec-Driven Development)

M/L 규모 태스크는 구현 전 스펙 파일 선행 **필수**.

순서: `active/{태스크}.md` 에 WHAT/WHY/수용기준 → Plan Mode 로 HOW 설계 → 태스크 분해 → 구현.

S 규모는 스펙 생략 가능.

## TDD 순서 (신규 기능)

feature 태스크 → qa (테스트 케이스 설계) → **사용자 확인** → developer (Green 구현) → reviewer + codex.

버그픽스/리팩터는 기존 순서 유지. `"TDD로"` 키워드로 명시 트리거.

## 컨텍스트 관리

- **1 태스크 = 1 세션 원칙**. 태스크 완료 후 같은 세션에서 다음 태스크 시작 금지 → `/session-handoff` 후 새 세션
- Gemini Phase 0 결과는 파일 저장 후 요약만 메인에 전달 (전문 주입 금지)
- 리뷰 → 재수정 루프 최대 3회. 초과 시 사용자에게 판단 요청
- 수정 후 반드시 테스트 실행. 테스트 안 돌리고 완료 선언 금지
