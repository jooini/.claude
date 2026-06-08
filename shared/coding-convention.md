# 공통 — 코딩 컨벤션

> SSOT. CLAUDE.md, AGENTS.md, sync-external 생성본 모두 이 파일 참조.

## 공백 / 들여쓰기

- 공백 4칸 기본 (Makefile, Go 제외)
- 파일 상단 수정이력 주석 금지 — git log 가 정본

## 네이밍

- 약어/줄임 네이밍 금지 → 풀네임 사용
- 클래스 리네이밍 시 파일명도 함께 변경

## 프레임워크별

- **FastAPI**: `Depends()` 직접 사용 금지 → `Annotated` 앨리어스 사용
- **Kotlin**: Spring Boot 신규 백엔드 우선
- **DB**: PostgreSQL(관계형), Redis(캐시/세션)

## 관측성

- Prometheus 메트릭 + 구조화 로그 (운영성 코드 필수)

## 티켓 / 인수기준

- 티켓 형식: `EPIC-NNN`
- 단위: 1~2일
- acceptance criteria 필수
- 알 수 없는 비즈니스 요구사항 만들어내지 말 것 (환각 금지)

상세: [`workflows/coding-convention.md`](../workflows/coding-convention.md)
