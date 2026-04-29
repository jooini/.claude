# SSO 핵심 정책

> CLAUDE.md에서 `@~/.claude/workflows/sso.md` 로 참조됨.

## 원칙

- **계정 중복 허용**: 전화번호/이메일 중복 허용 (레거시 유지)
- **SSO 폴백**: identity-nginx에서 502/503/504 시 레거시 폴백
- **BFF 패턴**: client_secret은 Identity Hub만 보유. refresh_token도 identity-hub가 관리 (Redis/DB)
- **Keycloak**: `getUserByUsername`에 반드시 `exact=True`
- **토큰 갱신**: B2C 백엔드는 access_token만 보유. 갱신 시 `POST {hub}/api/v1/auth/refresh` (body: `{access_token}`) 경유. PHP 세션/쿠키에 refresh_token 저장 금지

## ADR-007 Bearer 인증

- B2C 백엔드의 admin API 호출 시 identity-hub `service-token` 대리 발급 사용
- `IdentityHub_lib::getServiceToken()` + `setAdminCurlOptions()` 패턴
- Keycloak 직접 호출 금지 — identity-hub 경유만

## 인증 모드 전환

- `auth_mode=sso|legacy` (config/keycloak.php)
- LOCAL/DEV/QA/PP/LIVE 모두 `sso` (2026-04-17 기준)
- SSO 모드 시 `hooks/Auth_middleware.php`가 `webapp/JUMP/*` 보호
- `public` 라우트는 SSO 엔드포인트 + 소셜 로그인 콜백
