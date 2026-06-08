# 공통 — 프로젝트 기본값

> SSOT. AGENTS.md, sync-external 생성본 참조. 프로젝트마다 오버라이드 가능 (각 프로젝트 `.claude/CLAUDE.md` 가 우선).

## 백엔드 신규 스택

- Kotlin Spring Boot 우선
- PostgreSQL (관계형) + Redis (캐시/세션)
- 관측성: Prometheus 메트릭 + 구조화 로그

## SSO 핵심 정책

- 계정 중복 허용: 전화번호/이메일 중복 허용 (레거시 유지)
- SSO 폴백: identity-nginx 에서 502/503/504 시 레거시 폴백
- BFF 패턴: `client_secret` 은 Identity Hub 만 보유
- Keycloak: `getUserByUsername` 에 반드시 `exact=True`

상세: [`workflows/sso.md`](../workflows/sso.md)

## 티켓 규칙

- `EPIC-NNN` 형식, 1~2일 단위
- acceptance criteria 필수
- 알 수 없는 비즈니스 요구사항 환각 금지

## 문서 작성

- Obsidian Vault: `~/Workspace/weaversbrain/weaversbrain/`
- 파일명: `YYYY-MM-DD-HHMM-{파일명}.md` (시분 포함)
- YAML frontmatter 필수
- 프로젝트 내부 `docs/` 금지 → 반드시 Obsidian Vault

상세: [`workflows/docs-convention.md`](../workflows/docs-convention.md)
