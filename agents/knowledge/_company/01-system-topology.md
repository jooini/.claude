# 스피킹맥스/맥스AI 시스템 토폴로지

> 사내 컴포넌트 흐름 — Claude가 절대 알 수 없는 내부 아키텍처.

## 컴포넌트 표

| 컴포넌트 | 역할 | 호스트/도메인 | 의존 | 스택 |
|---------|------|---------------|------|------|
| B2C 백엔드 (레거시) | 사용자 앱 API | `b2c.maxaiapp.com` | Identity Hub, MySQL | PHP CodeIgniter |
| B2C 백엔드 (신규) | 점진적 마이그레이션 대상 | (마이그레이션 중) | Identity Hub | NestJS/TypeScript |
| Identity Hub | SSO 중앙 인증 + Keycloak BFF | `identity-hub.weaversbrain.com` | Keycloak, Redis, RDS | Python/FastAPI |
| Identity Nginx | SSO 게이트웨이/폴백 라우팅 | (인프라) | Identity Hub, B2C 백엔드 | Nginx |
| Keycloak | OIDC IdP | (Identity Hub 내부 경유만) | RDS | Keycloak 24.x |
| Identity Hub Frontend | SSO 관리 콘솔 | (관리자용) | Identity Hub API | Next.js |
| ClickHouse | 분석/이벤트 로그 DB | `{env}-wb-clickhouse` | - | ClickHouse |
| Speech Hub Admin | STT 모니터링/대시보드 | (사내) | ClickHouse | - |

## 호출 흐름 — 사용자 인증 (SSO 모드)

```
[사용자 앱 (iOS/Android/Web)]
        │ HTTPS
        ▼
[B2C 백엔드 (PHP)]
        │ access_token 보유 (refresh_token 보유 금지)
        │
        │ 토큰 갱신 시:
        │ POST {hub}/api/v1/auth/refresh  body: {access_token}
        ▼
[Identity Hub (Python)]
        │ refresh_token 보관 (Redis + RDS)
        │ Keycloak Admin API 호출
        ▼
[Keycloak 24.x]
        │ OIDC token endpoint
        ▼
   (RDS — 사용자 DB)
```

## 호출 흐름 — admin API (B2C → Hub → Keycloak)

```
[B2C 백엔드]
   │ IdentityHub_lib::getServiceToken()  → Redis 캐시 (4분 TTL)
   │ setAdminCurlOptions($token)
   ▼
[Identity Hub admin API]
   │ Keycloak Admin REST 래핑 (Bearer service-token)
   ▼
[Keycloak]
```

## 폴백 (SSO 장애 시)

```
[사용자]
   ▼
[Identity Nginx]
   │ Identity Hub 502/503/504 감지
   ▼
[레거시 인증 (B2C 직접)]
```

## 핵심 결정 (ADR 매핑)

- **ADR-007**: Keycloak 직접 호출 금지 → identity-hub 경유 (`IdentityHub_lib::getServiceToken()`)
- **BFF 패턴**: `client_secret`은 Identity Hub만 보유. refresh_token도 Hub에서만 관리.
- **인증 모드**: `auth_mode=sso|legacy` (config/keycloak.php). LOCAL/DEV/QA/PP/LIVE 모두 `sso` (2026-04-17 기준).
- **계정 중복 허용**: 전화번호/이메일 중복 허용 (레거시 유지)
- **`getUserByUsername`**: 반드시 `exact=True`
- **보호 라우트**: SSO 모드 시 `hooks/Auth_middleware.php` 가 `webapp/JUMP/*` 보호. `public` 라우트는 SSO 엔드포인트 + 소셜 로그인 콜백.

## 운영 메모

- 502 발생 시: identity-nginx 로그 → upstream timeout 인지 확인 → Identity Hub 헬스체크
- access_token 만료 시: 자동 갱신 — 클라이언트는 재시도만
- service-token TTL 5분 / Redis 캐시 4분 (4:30 시점 호출 fail 위험)
- 사내 cert: `verify_peer=false` 필요 — 운영에서 켜면 다운

## 환경

| 환경 | B2C | Identity Hub | Keycloak | ClickHouse DB |
|------|-----|--------------|----------|---------------|
| LOCAL | localhost | localhost | localhost | dev_speakingmax |
| DEV | dev.* | dev.* | dev.* | dev_speakingmax |
| QA | qa.* | qa.* | qa.* | qa_speakingmax |
| PP | pp.* | pp.* | pp.* | (?) |
| LIVE | b2c.maxaiapp.com | identity-hub.weaversbrain.com | (Hub 내부) | speakingmax |

❓ PP 환경 ClickHouse DB명 — 미확인
