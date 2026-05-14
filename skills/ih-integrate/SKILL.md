---
name: ih-integrate
description: 지정한 프로젝트 디렉토리에 Identity Hub 연동을 자동 설치한다. 스택(Next.js/FastAPI/Kotlin Spring/Express)을 자동 감지해 로그인·콜백·토큰갱신·로그아웃·M2M·JWT 검증 코드를 생성하고, 필요 시 Identity Hub `/onboard` API로 Keycloak Client를 자동 등록한다. "Identity Hub 연동", "SSO 붙이기", "/ih-integrate {경로}" 트리거.
---

# ih-integrate — Identity Hub 연동 자동 설치 스킬

대상 프로젝트 디렉토리에 Identity Hub OIDC/SSO 연동을 한 번에 깐다.
모델은 **얇은 클라이언트** — 서비스 측에 무거운 BFF 라우트를 새로 만들지 않고, Identity Hub가 이미 노출한 `/api/v1/auth/*` 엔드포인트를 그대로 호출한다. state·PKCE·nonce·refresh_token·client_secret은 Hub가 Redis/DB에서 관리한다.

## 트리거

- `/ih-integrate {target_dir}` — 가장 짧은 호출
- `/ih-integrate {target_dir} --stack nextjs --hub-url https://dev-sso.speakingmaxapp.com --realm weaversbrain --client-id myservice --onboard`
- "이 프로젝트에 Identity Hub 연동 깔아줘", "SSO 붙여줘" + 프로젝트 경로 지정 시

## 실행 절차

### 0. 인자 정리

호출 발화에서 다음을 추출한다. 누락 시 사용자에게 물어 보강한다.

| 인자 | 필수 | 기본/추론 |
|------|------|----------|
| `target_dir` | O | 절대경로. 호출 디렉토리 외 위치여야 함 |
| `--stack` | X | 미지정 시 자동 감지 (아래) |
| `--hub-url` | O | 예: `https://dev-sso.speakingmaxapp.com` |
| `--realm` | O | 예: `weaversbrain` |
| `--client-id` | O | Keycloak client_id. 미지정 시 디렉토리명에서 추론 |
| `--redirect-uri` | X | 미지정 시 stack 기본값 (Next.js: `${origin}/callback`, FastAPI: `${origin}/api/auth/callback` 등) |
| `--scope` | X | 기본 `openid profile email` |
| `--enable-m2m` | X | M2M 토큰 매니저까지 설치할지 (기본 false) |
| `--onboard` | X | 있으면 Identity Hub `/onboard` API 자동 호출 |
| `--admin-token` | X | `--onboard` 시 사용할 Bearer JWT (없으면 사용자에게 1회 입력 요청) |
| `--dry-run` | X | 파일 쓰지 않고 미리보기만 |

### 1. 대상 디렉토리 검증

- 존재하지 않으면 즉시 중단
- `.git`이 있는지 확인 — 없으면 사용자에게 "초기화되지 않은 디렉토리입니다. 계속할까요?" 질문
- 깨끗한지 (`git status --porcelain`) 확인. 변경분 있으면 백업 권고

### 2. 스택 자동 감지

`scripts/detect-stack.sh {target_dir}` 호출. 우선순위:

1. `package.json`에 `next` → `nextjs`
2. `package.json`에 `express`/`@nestjs/*` → `express`
3. `pyproject.toml`/`requirements.txt`에 `fastapi` → `fastapi`
4. `build.gradle.kts`/`pom.xml`에 `spring-boot` → `kotlin`
5. 그 외 → 사용자에게 명시적으로 선택받음

### 3. Hub 연결 사전 점검

```bash
curl -sf -o /dev/null -w "%{http_code}\n" \
  "${HUB_URL}/api/v1/auth/jwks/${REALM}"
```

200이 아니면 중단하고 사용자에게 URL/realm 재확인 요청. `IDENTITY_HUB_URL`이 토큰 발급 Keycloak과 같은 인스턴스를 가리켜야 함을 안내 (kid 불일치 흔한 함정).

### 4. (선택) `/onboard` 자동 호출

`--onboard` 플래그가 있을 때만 실행:

```bash
curl -sS -X POST "${HUB_URL}/api/v1/onboard" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"service_name\": \"${CLIENT_ID}\",
    \"service_type\": \"${SERVICE_TYPE}\",
    \"realm\": \"${REALM}\",
    \"redirect_uris\": [\"${REDIRECT_URI}\"],
    \"post_logout_redirect_uris\": [\"${POST_LOGOUT_URI}\"]
  }"
```

`service_type` 매핑:
- `nextjs`, `express` → `web`
- `fastapi`, `kotlin` → 사용자에게 `web` / `backend` 선택받음 (인증 코드 플로우면 `web`)

응답의 `client_secret`은 별도 파일로 저장하지 않는다. 화면에 1회 출력만 하고 사용자가 비밀 관리 시스템(.env, vault)에 직접 옮기게 안내. 409(CONFLICT)면 "이미 등록됨"으로 계속 진행, 다른 에러면 즉시 중단.

### 5. 코드 설치

스택별 템플릿 디렉토리를 읽어 `${...}` 자리표시자를 실제 값으로 치환 후 대상 디렉토리에 쓴다.

#### Next.js (App Router)

| 템플릿 | 설치 위치 |
|--------|-----------|
| `templates/nextjs/api-auth-login.ts.tpl` | `src/app/api/auth/login/route.ts` |
| `templates/nextjs/api-auth-callback.ts.tpl` | `src/app/api/auth/callback/route.ts` |
| `templates/nextjs/api-auth-refresh.ts.tpl` | `src/app/api/auth/refresh/route.ts` |
| `templates/nextjs/api-auth-logout.ts.tpl` | `src/app/api/auth/logout/route.ts` |
| `templates/nextjs/middleware.ts.tpl` | `src/middleware.ts` (이미 있으면 머지 권고만, 덮어쓰기 금지) |
| `templates/nextjs/lib-hub-service-token.ts.tpl` | `src/lib/hub-service-token.ts` — `--enable-m2m` 시에만 |

#### FastAPI

| 템플릿 | 설치 위치 |
|--------|-----------|
| `templates/fastapi/auth_routes.py.tpl` | `app/routes/auth.py` |
| `templates/fastapi/auth_deps.py.tpl` | `app/auth.py` (JWT 검증 의존성) |
| `templates/fastapi/hub_service_token.py.tpl` | `app/hub_service_token.py` — `--enable-m2m` 시에만 |

`identity-hub-python-sdk` 사용 여부를 사용자에게 묻는다:
- **Yes** → `auth_deps.py.tpl`은 SDK 버전 (`from identity_hub.middleware.fastapi import get_current_user`)
- **No** → `auth_deps.py.tpl`은 `python-jose` + JWKS 직접 호출 버전

#### Kotlin Spring Boot

| 템플릿 | 설치 위치 |
|--------|-----------|
| `templates/kotlin/application.yml.tpl` | `src/main/resources/application.yml`에 머지 (덮어쓰기 X) |
| `templates/kotlin/SecurityConfig.kt.tpl` | `src/main/kotlin/{base}/security/SecurityConfig.kt` |
| `templates/kotlin/HubAuthClient.kt.tpl` | `src/main/kotlin/{base}/hub/HubAuthClient.kt` |
| `templates/kotlin/HubServiceTokenManager.kt.tpl` | `--enable-m2m` 시 |
| `templates/kotlin/build.gradle.kts.snippet` | 사용자에게 의존성 추가 안내만 (자동 patch 안 함) |

`{base}`는 `build.gradle.kts`의 `group` 또는 기존 `src/main/kotlin/` 하위 첫 패키지 경로에서 추론.

#### Express/Node 일반

| 템플릿 | 설치 위치 |
|--------|-----------|
| `templates/express/auth-routes.js.tpl` | `routes/auth.js` |
| `templates/express/verify-middleware.js.tpl` | `middleware/verify-jwt.js` |
| `templates/express/hub-service-token.js.tpl` | `lib/hub-service-token.js` — `--enable-m2m` 시 |

### 6. 환경변수 추가

`.env.example`이 있으면 끝에 append, 없으면 새로 만든다.
이미 같은 키가 있으면 덮어쓰지 않고 "이미 존재함" 표시.

```env
# Identity Hub
HUB_URL=${HUB_URL}
REALM=${REALM}
CLIENT_ID=${CLIENT_ID}
REDIRECT_URI=${REDIRECT_URI}
# CLIENT_SECRET은 .env에만 두고 .env.example에는 빈 값 또는 생략
```

`.gitignore`에 `.env` 항목이 없으면 추가한다.

### 7. README 패치

루트 README의 끝에 "## Identity Hub 연동" 섹션을 추가한다 (이미 존재하면 skip). 내용은 `docs/flow-overview.md`를 인라인.

### 8. 의존성 안내

스택별로 사용자에게 추가 설치 명령을 출력 (자동 실행은 하지 않음):

- Next.js: 추가 패키지 없음 (fetch 내장)
- FastAPI (SDK 사용): `pip install identity-hub-sdk[fastapi]`
- FastAPI (SDK 미사용): `pip install httpx 'python-jose[cryptography]'`
- Kotlin: `implementation("org.springframework.boot:spring-boot-starter-oauth2-resource-server")`
- Express: `npm install jose node-fetch` (Node 18+ 면 fetch 생략)

### 9. 검증 및 사후 안내

생성된 파일 목록을 출력하고, **Keycloak Client 측에서 반드시 해야 할 일** 4개를 출력:

1. Redirect URI에 `${REDIRECT_URI}` 등록되어 있는지 확인
2. Web Origins 설정
3. `client_secret` 보관 (`/onboard` 응답 또는 Keycloak 콘솔)
4. 토큰 발급용 protocol mapper (`mIdx` 같은 커스텀 클레임이 필요한 경우)

`--dry-run`이 아닌 경우, 마지막에 `git status` 출력으로 어떤 파일이 추가/변경됐는지 사용자에게 명시.

## 안전 가드

- 기존 파일을 발견하면 **덮어쓰지 않는다**. 항상 "이미 존재함: `{path}` — 머지 권고" 출력 후 skip.
- 어떤 파일도 `.git/`, `node_modules/`, `dist/`, `build/` 안에는 쓰지 않는다.
- `--admin-token`은 셸 히스토리에 남지 않도록 가능하면 stdin 또는 환경변수로 받는다.
- 실패 시 이미 생성한 파일을 자동 롤백하지 않고, 사용자에게 `git restore .` 명령을 안내한다 (`.git` 없으면 수동 정리 안내).

## 참고 자료

- 흐름 개요: `docs/flow-overview.md`
- Keycloak 설정 체크리스트: `docs/keycloak-checklist.md`
- 트러블슈팅: `docs/troubleshooting.md`
- 코드 컨트랙트 원본: `~/Workspace/identity-hub-frontend/src/lib/integration-guide/samples.ts` (ADR-007)
- Hub API: `~/Workspace/identity-hub/docs/feature/auth/02-api.md`, `~/Workspace/identity-hub/docs/feature/onboard/02-api.md`
