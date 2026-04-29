# /sso-flow - SSO 작업 통합 컨텍스트 로드

SSO/인증 관련 작업 시작할 때 **3개 프로젝트 + 호환성 + 영향 범위** 한 번에 로드하는 통합 명령.

## 사용법

- `/sso-flow` — 전체 SSO 컨텍스트 로드 + 호환성 체크
- `/sso-flow {태스크 설명}` — 특정 태스크 컨텍스트로 진행

## 수행 작업 (병렬)

### 1단계: 프로젝트 컨텍스트 로드 (병렬)

다음 4개 프로젝트의 핵심 정보를 동시에 로드:

| 프로젝트 | 경로 | 로드할 것 |
|---------|------|----------|
| identity-hub | `~/Workspace/identity-hub` | `.claude/CLAUDE.md` + `docs/feature/auth/01-overview.md` |
| identity-keycloak | `~/Workspace/identity-keycloak` | `.claude/CLAUDE.md` + Realm 설정 |
| maxai-b2c-backend | `~/Workspace/maxai-b2c-backend` | `.claude/CLAUDE.md` + AUTH_MODE 분기 |
| identity-hub-frontend | `~/Workspace/identity-hub-frontend` | `.claude/CLAUDE.md` |

### 2단계: SSO 호환성 체크

`Skill(check-sso-compat)` 호출 — B2C 코드 변경이 SSO 호환성 깨지지 않는지 검증.

### 3단계: 크로스 프로젝트 영향 분석

`Skill(cross-check)` 호출 — Identity Hub API 변경 시 B2C/Keycloak/Frontend 영향 검사.

### 4단계: 메모리 검색 (자동)

UserPromptSubmit hook이 mem-search/local-rag 권유 — 과거 SSO 작업 기록 확인.

### 5단계: 핵심 정책 안내

다음 사항 자동 안내:
- **AUTH_MODE 분기**: SSO (Keycloak 경유) vs Legacy (PHP 직접)
- **JIT 마이그레이션**: Legacy DB → Keycloak 자동 계정 생성
- **Identity Hub OAuth 엔드포인트**: `/login`, `/callback/{type}`, `/token/refresh`, `/session/logout`
- **JWT 화이트리스트**: 회원가입/로그인/비밀번호 찾기는 SSO 검증 제외
- **Federated Identity**: 소셜 계정 연결 (Naver/Kakao/Apple)

### 6단계: 권장 워크플로우 안내

SSO 작업 시 표준 워크플로우 (standard-routines.md TYPE-A 기반):
1. po (PRD 작성, 변경 정책 정의)
2. Plan (구현 전략)
3. backend-developer (식별된 프로젝트별 구현)
4. **3중 리뷰 병렬**: code-reviewer + codex:review + Gemini 심층
5. **추가**: codex:adversarial-review (보안 변경 시 필수)
6. tester (각 프로젝트 테스트)

## 주의

- **🔴 Realm 설정 변경**: identity-keycloak `realm-config/backup/` JSON 직접 수정 금지 → Admin Console 또는 SPI로
- **🔴 JWT 검증 로직 변경**: identity-hub `core/security.py` 변경 시 모든 Bearer 토큰 영향
- **🔴 AUTH_MODE 분기 변경**: B2C `Auth_middleware.php` 변경 시 모든 인증 흐름 영향
- 보안/인증 변경은 자동으로 `codex:adversarial-review` 격상 (글로벌 라우팅)

## 호출 예시

```
/sso-flow 토큰 만료 24h → 1h 단축, refresh_token 회전 추가
```

→ 4개 프로젝트 컨텍스트 로드 + 호환성 체크 + 메모리 검색 + 영향 분석 → 작업 진행

## 관련 자료

- `~/.claude/workflows/sso.md` — SSO 핵심 정책
- `~/Workspace/weaversbrain/weaversbrain/Projects/sso-architecture/` — 아키텍처 문서
- `~/.claude/workflows/team-templates.md` "sso-core" — 멀티 프로젝트 팀 spawn
