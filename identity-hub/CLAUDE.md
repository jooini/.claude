# Identity Hub 프로젝트 컨텍스트

## 프로젝트 개요

| 항목 | 내용 |
|------|------|
| **프레임워크** | FastAPI + Python 3.11 |
| **역할** | OAuth2/OIDC BFF (Backend For Frontend) |
| **DB** | PostgreSQL (SQLAlchemy async) + Redis |
| **인증** | Keycloak 연동 |
| **경로** | `/Users/leonard/Workspace/identity-hub` |

---

## 보안 정책 및 인증 구조

### 엔드포인트 인증 구분

| 엔드포인트 | 인증 | 비고 |
|-----------|------|------|
| `/auth/*` (대부분) | 없음 | 공개 API (로그인, 콜백, 토큰 등) |
| `/auth/userinfo` | Bearer 토큰 자체 파싱 | OIDC UserInfo |
| `/users/*` | **Bearer JWT + require_role("admin")** | Admin Dashboard 전용 |
| `/clients/*` | **Bearer JWT + require_role("admin")** | Admin Dashboard 전용 |
| `/client-configs/*` | **Bearer JWT + require_role("admin")** | Admin Dashboard 전용 |
| `/admin/*` | **Bearer JWT + require_role("admin")** | Admin Dashboard 전용 |
| `/onboard` | **Bearer JWT + require_role("admin")** | Admin Dashboard 전용 |
| `/internal/*` | 없음 | 서버 간 내부 API (B2C → Identity Hub) |

### JWT 서명 검증 (security.py)

`verify_bearer_token()`은 JWKS 기반 RS256 서명 검증을 완전히 구현:

1. 토큰 헤더에서 `kid` 추출
2. 페이로드에서 `iss` 추출 → `KEYCLOAK_SERVER_URL/realms/ADMIN_REALM`과 비교
3. JWKS에서 signing key 조회 (캐시 TTL 1시간, asyncio.Lock + double-check 패턴. kid 불일치 시 즉시 재조회. Keycloak 장애 시 stale 캐시 fallback)
4. `python-jose`로 서명 + iss + aud + exp 검증 (RS256)
5. `realm_access.roles`에서 required role 확인

`require_role(role)` — dependency factory로, `verify_bearer_token` 결과에서 `realm_access.roles`에 해당 role이 있는지 확인. 없으면 403.

### JWT aud 검증 특이사항

Keycloak 설정에 따라 access token에 `aud` 대신 `azp`(authorized party)만 포함될 수 있음. `verify_jwt_token()`은 aud 검증 실패 시 azp로 대체 검증 수행.

### 라우터 인증 적용 방식

`router.py`에서 `dependencies=[Depends(require_role("admin"))]`로 라우터 레벨에 일괄 적용:

```python
_auth = [Depends(require_role("admin"))]
api_router.include_router(users.router, prefix="/users", dependencies=_auth)
api_router.include_router(clients.router, prefix="/clients", dependencies=_auth)
api_router.include_router(client_config.router, prefix="/client-configs", dependencies=_auth)
api_router.include_router(admin.router, prefix="/admin", dependencies=_auth)
api_router.include_router(onboard.router, prefix="/onboard", dependencies=_auth)

# Internal endpoints (인증 불필요, 서버 간 통신)
api_router.include_router(internal.router, prefix="/internal")
```

---

## 디렉토리 구조

```
identity-hub/
├── app/
│   ├── main.py                            # FastAPI 진입점, lifespan, 미들웨어 등록
│   ├── api/v1/
│   │   ├── router.py                      # API 라우터 통합 + 인증 정책 적용
│   │   └── endpoints/
│   │       ├── oauth.py                   # OAuth 리다이렉트 (login, register, social-login)
│   │       ├── callback.py                # OAuth 콜백 (/callback/{type})
│   │       ├── token.py                   # 토큰 관리 (refresh, validate, verify-password, token, exchange, introspect, jwks)
│   │       ├── session.py                 # 로그아웃 (POST, GET)
│   │       ├── oidc.py                    # OIDC Discovery, UserInfo, check-connection
│   │       ├── users.py                   # 사용자 관리 (CRUD, 역할, 세션, Federated Identity, 탈퇴)
│   │       ├── clients.py                 # Keycloak 클라이언트 관리 (CRUD)
│   │       ├── client_config.py           # DB 클라이언트 설정 CRUD
│   │       ├── admin.py                   # 관리자 (Realm, Role, Client 조회, 사용자 수)
│   │       ├── onboard.py                 # 클라이언트 온보딩
│   │       └── internal.py                # 내부 API (서버 간 탈퇴 등)
│   ├── core/
│   │   ├── config.py                      # Pydantic Settings 환경설정
│   │   ├── security.py                    # Bearer JWT 인증 (JWKS 서명 검증 + role 확인)
│   │   ├── middleware.py                  # RequestIdMiddleware (request_id, timing, JSON 로그)
│   │   ├── exceptions.py                  # 커스텀 예외 + 글로벌 핸들러 (AppException, RateLimitExceeded, KeycloakError)
│   │   ├── audit.py                       # AuditContext 의존성 (yield 패턴)
│   │   ├── dependencies.py                # DI 팩토리 (lru_cache 싱글턴 + Depends 래퍼)
│   │   ├── constants.py                   # 상수 (TTL, 타임아웃, 로그 설정)
│   │   ├── rate_limiter.py                # Redis Fixed Window Rate Limiter (Lua 스크립트)
│   │   ├── request_context.py             # ContextVar 기반 request_id 관리
│   │   └── logging.py                     # JSONFormatter + setup_logging
│   ├── db/
│   │   ├── base.py                        # Base, TimestampMixin
│   │   ├── models.py                      # ORM (UserAuthentication, KeycloakClient, UserWithdrawalArchive)
│   │   ├── session.py                     # 엔진, get_db(), init_db()
│   │   ├── user_auth_repository.py        # UserAuthentication CRUD
│   │   ├── keycloak_client_repository.py  # KeycloakClient CRUD
│   │   └── withdrawal_repository.py       # UserWithdrawalArchive CRUD
│   ├── services/
│   │   ├── auth_service.py                # 인증 오케스트레이션 (DB+KC+Redis)
│   │   ├── keycloak_service.py            # 하위호환 리다이렉트 모듈 (합성 클래스)
│   │   ├── keycloak_oidc_service.py       # Keycloak OIDC (httpx 기반)
│   │   ├── oauth_service.py               # OAuth 콜백 처리
│   │   ├── session_service.py             # Redis 세션 관리
│   │   ├── client_config_service.py       # DB 클라이언트 설정 관리
│   │   ├── user_service.py                # 사용자 관리 서비스
│   │   ├── onboard_service.py             # 클라이언트 온보딩 서비스
│   │   ├── withdrawal_service.py          # 회원 탈퇴 서비스
│   │   ├── audit_service.py               # 감사 로그
│   │   ├── cache_service.py               # Redis 캐시 래퍼
│   │   ├── session_cleanup_service.py     # 백그라운드 세션 정리 (lifespan에서 시작)
│   │   └── keycloak/                      # Keycloak Admin API 도메인별 분리
│   │       ├── base.py                    # KeycloakBaseService (공통: admin/openid client 관리)
│   │       ├── user_keycloak_service.py   # 사용자 CRUD, Federated Identity
│   │       ├── admin_keycloak_service.py  # Realm, Client 관리
│   │       └── role_keycloak_service.py   # 역할 관리
│   ├── schemas/                           # Pydantic 스키마
│   │   ├── auth.py                        # OAuth/토큰 요청/응답
│   │   ├── user.py                        # 사용자, 역할, Federated Identity
│   │   ├── client.py                      # Keycloak 클라이언트
│   │   ├── admin.py                       # Realm, Role, Client 관리
│   │   ├── onboard.py                     # 온보딩 요청/응답
│   │   └── withdrawal.py                  # 탈퇴 관련
│   └── utils/
│       ├── jwt.py                         # JWKSCache, verify_jwt_token, parse_jwt_payload
│       ├── redirect.py                    # redirect_uri 화이트리스트 검증
│       ├── http.py                        # HTTP 유틸리티
│       └── masking.py                     # PII 마스킹
├── tests/
│   ├── conftest.py                        # 테스트 설정 (mock DB, client fixture)
│   ├── unit/                              # 단위 테스트 (27개 파일)
│   └── integration/                       # 통합 테스트 (12개 파일)
├── alembic/                               # DB 마이그레이션 (7개 버전)
└── docker-compose.yml
```

---

## 레이어 아키텍처

```
Controller (endpoints/)  →  Service (services/)  →  Repository (db/)
    요청 파싱                  비즈니스 로직           DB 쿼리
    응답 반환                  외부 API 호출
```

**규칙:** 서비스 레이어에서 `select`, `db.execute`, `db.add` 직접 사용 금지. 반드시 repository 메서드를 통해 DB 접근.

---

## 엔드포인트 (총 59개)

### 루트 레벨 (3개)
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/` | GET | 서비스 정보 |
| `/health` | GET | 헬스체크 (Keycloak 연결 확인) |
| `/.well-known/openid-configuration` | GET | OIDC Discovery 메타데이터 |

### OAuth & 인증 (/api/v1/auth) - 16개, 인증 없음
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/login` | GET | Keycloak 로그인 리다이렉트 |
| `/register` | GET | Keycloak 회원가입 리다이렉트 |
| `/social-login` | GET | Keycloak 소셜 로그인 (kc_idp_hint) |
| `/callback/{type}` | GET | OAuth 콜백 (login/register/social) |
| `/refresh` | POST | 토큰 갱신 |
| `/validate` | POST | 토큰 검증 (Keycloak introspection) |
| `/verify-password` | POST | 비밀번호 확인 (ROPC) |
| `/token` | POST | OAuth2 토큰 엔드포인트 (RFC 6749) |
| `/exchange` | POST | 일회용 코드 → 토큰 교환 |
| `/token-password` | POST | 비밀번호 grant (deprecated) |
| `/introspect` | POST | 토큰 인트로스펙션 |
| `/jwks/{realm}` | GET | JWKS 프록시 |
| `/userinfo` | GET | OIDC UserInfo (Bearer 토큰 자체 파싱) |
| `/check-connection` | GET | Keycloak 연결 확인 |
| `/logout` | POST | 로그아웃 |
| `/logout` | GET | 로그아웃 (GET 지원, post_logout_redirect_uri 파라미터) |

### 사용자 관리 (/api/v1/users) - 17개, admin role 필수
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/` | POST | 사용자 생성 |
| `/{realm}` | GET | 사용자 목록 조회 |
| `/{realm}/username/{username}` | GET | username으로 조회 (exact matching) |
| `/{realm}/search` | GET | 사용자 검색 |
| `/{realm}/by-midx/{midx}` | GET | m_idx로 조회 |
| `/{realm}/{user_id}` | GET | 사용자 조회 |
| `/{realm}/{user_id}` | PUT | 사용자 수정 |
| `/{realm}/{user_id}` | DELETE | 사용자 삭제 (탈퇴) |
| `/{realm}/{user_id}/password` | POST | 비밀번호 설정 |
| `/{realm}/{user_id}/roles` | POST | 역할 할당 |
| `/{realm}/{user_id}/roles/{role_name}` | DELETE | 역할 해제 |
| `/{realm}/{user_id}/roles` | GET | 역할 조회 |
| `/{realm}/{user_id}/sessions` | GET | 세션 목록 조회 |
| `/{realm}/{user_id}/sessions/{session_id}` | DELETE | 세션 강제 종료 |
| `/{realm}/{user_id}/federated-identity` | POST | Federated Identity 추가 |
| `/{realm}/{user_id}/federated-identity` | GET | Federated Identity 목록 |
| `/{realm}/{user_id}/federated-identity/{provider_id}` | DELETE | Federated Identity 삭제 |

### Keycloak 클라이언트 (/api/v1/clients) - 6개, admin role 필수
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/` | POST | Keycloak 클라이언트 생성 |
| `/{realm}/{client_id}` | GET | 클라이언트 조회 |
| `/{realm}/{client_id}/secret` | GET | client_secret 조회 |
| `/{realm}/{client_id}` | PUT | 클라이언트 수정 |
| `/{realm}/{client_id}` | DELETE | 클라이언트 삭제 |
| `/{realm}/{client_id}/test-legacy-api` | POST | 레거시 API 연결 테스트 |

### DB 클라이언트 설정 (/api/v1/client-configs) - 5개, admin role 필수
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/` | POST | 설정 생성 |
| `/` | GET | 설정 목록 |
| `/{realm}/{client_id}` | GET | 설정 조회 |
| `/{realm}/{client_id}` | PUT | 설정 수정 |
| `/{realm}/{client_id}` | DELETE | 설정 삭제 |

### 관리 (/api/v1/admin) - 9개, admin role 필수
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/realms` | GET | Realm 목록 |
| `/realms/{realm}` | GET | Realm 조회 |
| `/realms` | POST | Realm 생성 |
| `/realms/{realm}/roles` | GET | Realm 역할 목록 |
| `/realms/{realm}/roles` | POST | Realm 역할 생성 |
| `/realms/{realm}/roles/{role_name}` | DELETE | Realm 역할 삭제 |
| `/realms/{realm}/roles/{role_name}/users` | GET | 역할별 사용자 목록 |
| `/realms/{realm}/clients` | GET | Realm 클라이언트 목록 |
| `/realms/{realm}/users/count` | GET | Realm 사용자 수 |

### 온보딩 (/api/v1/onboard) - 1개, admin role 필수
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/` | POST | 클라이언트 온보딩 (Keycloak + DB 동시 등록) |

### 내부 API (/api/v1/internal) - 1개, 인증 없음
| 경로 | 메서드 | 역할 |
|------|--------|------|
| `/users/{realm}/by-midx/{midx}` | DELETE | m_idx 기반 사용자 탈퇴 (idempotent, B2C→Hub 서버 간 호출) |

---

## 서비스 계층 (16개)

### 의존성 계층 (dependencies.py 기준)

```
Level 0 (의존 없음):
  CacheService, AuditService, KeycloakOIDCService, KeycloakService

Level 1 (Level 0 의존):
  SessionService(CacheService)
  ClientConfigService(CacheService, KeycloakClientRepository)

Level 2 (Level 0~1 의존):
  UserService(KeycloakService)
  WithdrawalService(KeycloakService, WithdrawalRepository)
  AuthService(CacheService, ClientConfigService, KeycloakOIDCService, KeycloakService, SessionService, UserAuthRepository)

Level 3 (Level 2 의존):
  OAuthService(AuthService, ClientConfigService, KeycloakOIDCService, SessionService)
  OnboardService(AuditService, ClientConfigService, KeycloakService)

백그라운드:
  SessionCleanupService(CacheService) — lifespan에서 시작
```

### 서비스 역할

| 서비스 | 역할 |
|--------|------|
| `auth_service.py` | **인증 오케스트레이션** — logout, cleanup, refresh, validate, verify-password, token request, save auth |
| `keycloak_service.py` | **Keycloak Admin API 합성 클래스** — UserKeycloakService + AdminKeycloakService + RoleKeycloakService |
| `keycloak_oidc_service.py` | **Keycloak OIDC** — token, refresh, logout, verify-password, JWKS (httpx 기반) |
| `oauth_service.py` | **OAuth 콜백** — code→token 교환, 세션 생성, DB 저장 |
| `session_service.py` | **Redis 세션** — CRUD, 일회용 코드 발급/교환 |
| `client_config_service.py` | **DB 클라이언트 설정** — client_secret 조회, 캐시 |
| `user_service.py` | **사용자 관리** — Keycloak 사용자 CRUD 래핑 |
| `onboard_service.py` | **클라이언트 온보딩** — Keycloak + DB 동시 등록, check-connection |
| `withdrawal_service.py` | **회원 탈퇴** — Keycloak 삭제 + 아카이브 저장, PII 만료 관리 |
| `audit_service.py` | **감사 로그** — 파일 기반 JSONL 기록 |
| `cache_service.py` | **Redis 캐시** — 연결 관리, get/set/delete |
| `withdrawal_service.py` | **회원 탈퇴** — Keycloak 삭제 + 아카이브 저장, 재가입 차단 확인 |
| `session_cleanup_service.py` | **백그라운드 세션 정리** — 만료/로그아웃 세션 주기적 삭제 |

### Keycloak 서비스 패키지 (keycloak/)

| 서비스 | 역할 |
|--------|------|
| `base.py` | **KeycloakBaseService** — admin/openid client 생성/관리, asyncio.to_thread 래핑 |
| `user_keycloak_service.py` | 사용자 CRUD, 비밀번호, Federated Identity |
| `admin_keycloak_service.py` | Realm, Client 관리 |
| `role_keycloak_service.py` | 역할 관리 |

`keycloak_service.py`는 위 3개를 다중 상속한 합성 클래스로, 기존 import 경로 및 `@patch` 호환을 위해 유지.

---

## DI 구조 (dependencies.py)

- `lru_cache` 기반 싱글턴 팩토리 (get_xxx_service). 단, `get_keycloak_service()`는 `@patch` 테스트 호환을 위해 `@lru_cache` 미적용 (모듈 레벨 싱글턴 반환)
- 11개 Depends 래퍼 (xxx_dep) — 테스트에서 `app.dependency_overrides[xxx_dep] = lambda: mock_svc`로 교체
- Repository → Level 0 → Level 1 → Level 2 → Level 3 계층적 의존성

---

## DB 모델

### user_authentications (ORM: UserAuthentication)
| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | int | PK |
| keycloak_user_id | str(255), nullable | Keycloak 사용자 ID |
| m_idx | int, nullable | 사용자 ID (T_Member), nullable |
| session_state | str(255), unique | Keycloak 세션 ID |
| realm | str(255) | Realm |
| client_id | str(255) | 클라이언트 ID |
| refresh_token | text, nullable | 리프레시 토큰 |
| rt_expires_at | datetime(tz), nullable | 리프레시 토큰 만료 시각 |
| device_info | str(500), nullable | 디바이스 정보 |
| ip_address | str(45), nullable | IP 주소 |
| logged_out_at | datetime(tz), nullable | 로그아웃 시각 (NULL=활성) |
| created_at / updated_at | | TimestampMixin |

### keycloak_clients (ORM: KeycloakClient)
| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | int | PK |
| client_id | str(100) | Keycloak client_id |
| client_secret | str(255) | client_secret |
| realm | str(100) | Realm |
| description | str(500), nullable | 설명 |
| is_active | bool, default=True | 활성 여부 (soft delete) |
| allowed_redirect_patterns | JSON, nullable | 허용 redirect_uri 패턴 |
| error_redirect_url | str(500), nullable | 에러 리다이렉트 URL |
| session_ttl | int, nullable | 세션 TTL (초) |
| allowed_cors_origins | JSON, nullable | 허용 CORS 오리진 |
| default_scope | str(500), nullable | 기본 OAuth scope |
| session_policy | str(50), nullable | 세션 정책 |
| | | UNIQUE(client_id, realm) |

### user_withdrawal_archives (ORM: UserWithdrawalArchive)
| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | int | PK |
| keycloak_user_id | str(255) | Keycloak 사용자 ID |
| realm | str(100) | Realm |
| username | str(255), nullable | 사용자명 |
| email | str(255), nullable, indexed | 이메일 |
| user_type | str(20) | 사용자 유형 |
| social_provider | str(50), nullable | 소셜 프로바이더 |
| social_provider_id | str(255), nullable | 소셜 프로바이더 ID |
| user_attributes | JSON, nullable | Keycloak 속성 |
| roles | JSON, nullable | 역할 목록 |
| withdrawal_reason | str(500), nullable | 탈퇴 사유 |
| pii_expires_at | datetime(tz), nullable | PII 만료 시각 |
| pii_purged | bool, default=False | PII 삭제 여부 |
| | | INDEX(social_provider, social_provider_id) |
| | | INDEX(pii_expires_at) WHERE NOT pii_purged |

### 마이그레이션 전용 테이블 (ORM 없음)
- **audit_logs** — 감사 로그 (마이그레이션 001)
- **service_api_keys** — API 키 (마이그레이션 006, 현재 미사용)

---

## 레포지토리

| 레포지토리 | 테이블 | 역할 |
|-----------|--------|------|
| `user_auth_repository.py` | `user_authentications` | 인증 세션 CRUD (session_state 기준) |
| `keycloak_client_repository.py` | `keycloak_clients` | 클라이언트 설정 CRUD (client_id+realm 기준) |
| `withdrawal_repository.py` | `user_withdrawal_archives` | 탈퇴 아카이브 CRUD |

---

## 환경변수

```bash
# Application
APP_NAME=identity-hub
APP_ENV=development
DEBUG=true
API_V1_PREFIX=/api/v1
CORS_ORIGINS=["*"]

# Keycloak
KEYCLOAK_SERVER_URL=https://sso.example.com      # 브라우저 리다이렉트용 (외부 URL)
KEYCLOAK_INTERNAL_URL=http://keycloak:8080        # 서버간 통신용 (없으면 SERVER_URL 사용)
KEYCLOAK_MANAGEMENT_URL=                          # 관리 URL (없으면 INTERNAL_URL:9000)
KEYCLOAK_ADMIN_USERNAME=admin
KEYCLOAK_ADMIN_PASSWORD=admin
ADMIN_REALM=master                                # JWT 검증 대상 realm
ADMIN_CLIENT_ID=identity-hub-admin                # JWT 검증 대상 audience
JWKS_CACHE_TTL=3600                               # JWKS 캐시 TTL (초)

# Identity Hub
HUB_URL=https://dev-sso.speakingmaxapp.com        # 외부 URL

# Database
DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/db
DB_POOL_SIZE=5
DB_MAX_OVERFLOW=10

# Redis
REDIS_URL=redis://:password@host:6379/0
REDIS_CLUSTER=false                               # true면 Redis Cluster 모드
SESSION_TTL=86400                                 # 24시간 (초)

# Authorization Code Flow
DEFAULT_ERROR_REDIRECT_URL=http://localhost:3000/error
DEFAULT_OAUTH_SCOPE=openid profile email
ALLOWED_REDIRECT_URI_PATTERNS=["https://*.speakingmaxapp.com/*"]

# Session Cleanup
SESSION_CLEANUP_INTERVAL=3600                     # 1시간마다
SESSION_EXPIRED_RETENTION_DAYS=7
SESSION_LOGGED_OUT_RETENTION_DAYS=30
SESSION_CLEANUP_BATCH_SIZE=500

# Rate Limiting
TRUSTED_PROXY_IPS=[]                              # 신뢰 프록시 IP 대역

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json                                   # json 또는 text
AUDIT_LOG_PATH=/var/log/identity/audit.jsonl
API_REQUEST_LOG_PATH=/var/log/identity/api-requests.log
```

---

## 미들웨어 및 예외 처리

### RequestIdMiddleware (middleware.py)
- 모든 요청에 `X-Request-ID` 부여 (클라이언트 제공 시 검증 후 사용)
- 처리 시간 측정 → `X-Response-Time` 헤더
- Vector/ClickHouse용 JSON 로그 (`api-requests.log`) — QueueHandler로 비동기 기록

### JSONFormatter (logging.py)
- 구조화된 JSON 로그: timestamp, level, logger, message, request_id, service, environment
- extra 필드 자동 병합

### 글로벌 예외 핸들러 (exceptions.py)
- `RateLimitExceeded` → 429 + Retry-After
- `AppException` → 커스텀 에러 코드/메시지 (OAuth token endpoint는 RFC 6749 형식)
- `KeycloakError` → 상태 코드 추출 후 변환
- `Exception` → 500 Internal Server Error

### Rate Limiter (rate_limiter.py)
- Redis Fixed Window Counter (Lua 스크립트로 INCR+EXPIRE 원자적 실행)
- 비밀번호 검증 경로 자동 그룹화
- Redis 장애 시 rate limit 스킵 (가용성 우선)
- **현재 상태: 전체 엔드포인트에서 rate limit 제거됨 (인프라만 존재, 적용 없음). 향후 필요 시 재적용**

### 보안 추가 메커니즘
- **PKCE (S256)**: oauth.py의 login/register/social-login에서 자동 생성, Keycloak에 전달
- **Nonce**: 서버에서 `secrets.token_urlsafe(32)`로 생성, ID Token replay 방지
- **세션 토큰 검증**: refresh/logout 요청 시 access_token 서명 검증 (exp 미검증, session_state 추출용)
- **JWKS Stale Fallback**: Keycloak 장애 시 기존 캐시로 인증 유지 (fetch 실패 → stale 캐시 반환)

### 클라이언트 커스텀 속성
- `legacyApiUrl`: 레거시 API 서버 URL
- `legacyApiPath`: 레거시 API 경로 (기본: `/maxAi/Member`)
- `legacyPKey`: 레거시 API 인증 키
- `post_logout_redirect_uris`: 로그아웃 후 리다이렉트 URI 목록 (Keycloak attributes에 `##` 구분자로 저장)

---

## 테스트

```bash
pytest tests/ -v --cov=app
```

- 총 39개 테스트 파일, ~416개 테스트 함수

---

## Claude Code 규칙

### 문서 생성 규칙
- 경로: `~/Workspace/weaversbrain/weaversbrain/Projects/identity-hub/YYYY-MM/YYYY-MM-DD-파일명.md`

### 커밋 규칙
- Co-Authored-By 포함하지 않음
- 커밋 메시지는 한글로 작성

---

## 최근 변경 이력

### 2026-04: 세션 보안 강화 + Internal API + 클라이언트 속성 확장
- refresh/logout 요청 시 access_token 서명 검증 추가 (`verify_session_access_token`)
- JWKS stale fallback 구현 — Keycloak 장애 시 기존 캐시로 인증 유지
- Internal API (`/internal/users/{realm}/by-midx/{midx}` DELETE) — B2C→Hub 서버 간 탈퇴
- 클라이언트 커스텀 속성 지원 (legacyApiUrl, legacyApiPath, legacyPKey)
- 레거시 API 연결 테스트 엔드포인트 (`/clients/{realm}/{client_id}/test-legacy-api`)
- post_logout_redirect_uris 지원 추가
- 전체 엔드포인트 rate limit 제거 (인프라만 유지)

### 2026-03-17: SSO 성숙도 리뷰
- SSO 성숙도 리뷰 문서 작성

### 2026-03-10: 회원 탈퇴 시스템 + Rate Limiter
- `WithdrawalService` + `user_withdrawal_archives` 테이블
- `withdrawal_repository.py` 추가
- Redis Fixed Window Rate Limiter (Lua 스크립트)
- 비밀번호 검증 경로 자동 그룹화

### 2026-02-20: 로깅 시스템 개선 + 클라이언트 온보딩
- `RequestIdMiddleware` — request_id 부여, 처리 시간 측정
- `JSONFormatter` — 구조화된 JSON 로그
- Vector/ClickHouse용 api-requests JSON 로그
- `OnboardService` — Keycloak + DB 동시 등록
- `check-connection` 엔드포인트

### 2026-02-19: DB 스키마 확장
- `keycloak_user_id` 추가, `m_idx` nullable 변경
- `keycloak_clients` 확장 (allowed_redirect_patterns, allowed_cors_origins, session_ttl, default_scope, session_policy)
- `service_api_keys` 마이그레이션 (현재 미사용)

### 2026-02-04: Superset SSO 연동
- `/token` OAuth2 표준 준수 (form-urlencoded, Basic Auth)
- One-time code TTL 300초
- OIDC Discovery 엔드포인트 추가
- OAuth state 파라미터 지원

### 2026-02-03: 레포지토리 레이어 분리
- `user_auth_repository.py`, `keycloak_client_repository.py` 신규
- 서비스에서 SQLAlchemy 직접 쿼리 제거

### 2026-02-02: 코드 리뷰 수정
- redirect_uri 화이트리스트 검증
- KeycloakService `asyncio.to_thread` 래핑
- `auth_service.py` 인증 오케스트레이션 분리
- 콜백 엔드포인트 통합 `/callback/{type}`

### 2026-01-26: auth.py 기능별 분리
- `oauth.py`, `callback.py`, `token.py`, `session.py`

### 2026-01-25: 에러 핸들링 및 Admin 인증
- `exceptions.py` 커스텀 예외
- `security.py` JWT 인증
