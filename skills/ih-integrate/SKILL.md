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
| `--overlay-existing-oidc` | X | 기존 OIDC 자체 구현이 감지돼도 강제로 진행 (§1.5 abort 우회). 별칭 `--force` |
| `--app-dir` | X | Next.js 라우트 베이스 강제 지정 (`src/app` 또는 `app`). 미지정 시 §5에서 자동 감지 |
| `--env-prefix` | X | 환경변수 키 접두 (예: `IDENTITY_HUB_`). 미지정 시 §6에서 기존 `.env.example` 스캔으로 자동 감지, 없으면 접두 없음 |
| `--reveal-secret-to` | X | `--onboard` 응답의 `client_secret` 전달 방식 (`stdout`/`clipboard`/`file:<path>`). 미지정 시 stdout 출력 차단(§4) |

### 1. 대상 디렉토리 검증

- 존재하지 않으면 즉시 중단
- `.git`이 있는지 확인 — 없으면 사용자에게 "초기화되지 않은 디렉토리입니다. 계속할까요?" 질문
- 깨끗한지 (`git status --porcelain`) 확인. 변경분 있으면 백업 권고

### 1.5 기존 OIDC 자체 구현 감지 (abort 가드)

이 스킬은 **얇은 클라이언트**를 설치한다. 대상 프로젝트에 이미 자체 OIDC 구현(PKCE/state 헬퍼 + 인증 라우트 일습)이 있으면, 그 위에 스킬 산출물을 얹는 순간 **라우트·미들웨어 2벌이 공존하는 잘못된 통합**이 된다. 따라서 설치 전 다음 시그니처를 스캔한다.

```bash
# 헬퍼 시그니처
test -f "${T}/lib/oidc.ts" -o -f "${T}/src/lib/oidc.ts"      # PKCE/state 헬퍼
# 라우트 시그니처 (둘 중 한 레이아웃)
test -f "${T}/app/api/auth/login/route.ts" -o -f "${T}/src/app/api/auth/login/route.ts"
test -f "${T}/app/api/auth/callback/route.ts" -o -f "${T}/src/app/api/auth/callback/route.ts"
```

판정:
- 위 시그니처 중 **2개 이상 일치** → "기존 OIDC 자체 구현 감지"로 판단
- `--overlay-existing-oidc`(별칭 `--force`)가 **없으면 즉시 중단(abort)**. 단순 "머지 권고"로 끝내지 않는다.
- abort 메시지에 다음을 명시:
  - 감지된 파일 목록
  - "두 패턴 혼재는 잘못된 통합입니다. 기존 구현을 유지하거나 제거를 먼저 결정하세요."
  - 그래도 강행하려면 `--overlay-existing-oidc` 안내 (이 경우 §5는 기존 파일을 여전히 덮어쓰지 않고 skip+머지 권고로만 동작)
- 시그니처 0~1개 → 신규/부분 도입으로 보고 계속 진행

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

응답의 `client_secret`은 별도 파일로 저장하지 않는다. **기본적으로 stdout에 출력하지 않는다** — 콘솔 출력은 셸 히스토리·스크롤백·터미널 로그에 평문으로 남는 위험이 있다. 전달 방식은 `--reveal-secret-to`로 명시할 때만 동작한다:

- 미지정(기본) → secret 값을 출력하지 않고 "client_secret 발급됨 (길이 N자). `--reveal-secret-to` 로 전달 방식을 지정하세요" 힌트만 표시
- `--reveal-secret-to stdout` → 화면에 1회 출력 (위험 인지한 경우만)
- `--reveal-secret-to clipboard` → `pbcopy`로 클립보드 복사, 화면엔 hint만
- `--reveal-secret-to file:<path>` → 지정 파일에 `chmod 600`으로 저장, 경로만 출력

어느 방식이든 사용자가 비밀 관리 시스템(.env, vault)에 옮긴 뒤 임시 노출 경로(클립보드/파일)를 정리하도록 안내한다. 409(CONFLICT)면 "이미 등록됨"으로 계속 진행(이 경우 secret 재발급 없음), 다른 에러면 즉시 중단.

### 5. 코드 설치

스택별 템플릿 디렉토리를 읽어 `${...}` 자리표시자를 실제 값으로 치환 후 대상 디렉토리에 쓴다.

#### Next.js (App Router)

**라우트 베이스(`${APP_DIR}`) 자동 감지** — Next.js는 `src/app/`과 `app/`을 모두 지원하지만 한 프로젝트는 하나만 인식한다. 잘못 쓰면 라우트가 조용히 누락되므로, 설치 위치를 고정하지 않고 다음 우선순위로 결정한다.

1. `--app-dir` 명시값이 있으면 그대로 사용
2. 기존 `src/app/` 디렉토리 존재 → `${APP_DIR}` = `src/app`
3. 기존 `app/` 디렉토리 존재 → `${APP_DIR}` = `app`
4. 둘 다 없음(신규 프로젝트) → `tsconfig.json`의 `compilerOptions.paths`에서 `@/*` 매핑이 `./src/*`를 가리키면 `src/app`, 아니면 `app`
5. 그래도 불명확 → `src/app` (create-next-app 기본값)

미들웨어 위치는 `${APP_DIR}`와 짝을 맞춘다: `src/app` → `src/middleware.ts`, `app` → `middleware.ts` (프로젝트 루트). `lib/`도 동일 규칙(`src/lib` vs `lib`).

| 템플릿 | 설치 위치 |
|--------|-----------|
| `templates/nextjs/api-auth-login.ts.tpl` | `${APP_DIR}/api/auth/login/route.ts` |
| `templates/nextjs/api-auth-callback.ts.tpl` | `${APP_DIR}/api/auth/callback/route.ts` |
| `templates/nextjs/api-auth-refresh.ts.tpl` | `${APP_DIR}/api/auth/refresh/route.ts` |
| `templates/nextjs/api-auth-logout.ts.tpl` | `${APP_DIR}/api/auth/logout/route.ts` |
| `templates/nextjs/middleware.ts.tpl` | `${MIDDLEWARE_PATH}` (= `src/middleware.ts` 또는 루트 `middleware.ts`. 이미 있으면 머지 권고만, 덮어쓰기 금지) |
| `templates/nextjs/lib-hub-service-token.ts.tpl` | `${LIB_DIR}/hub-service-token.ts` — `--enable-m2m` 시에만 |

**보안 계약 (모든 스택 라우트 템플릿이 반드시 만족해야 함)**

설치되는 라우트 템플릿은 다음을 코드와 주석으로 보장한다. 템플릿 자체가 이를 위반하면 설치 전에 수정한다.

- **토큰 비노출 (B4)**: `access_token`·`refresh_token`·`client_secret` raw 값은 **로그·에러 응답·리다이렉트 쿼리 어디에도 출력하지 않는다**. 템플릿 상단에 `// SECURITY: never log or return token raw values` 주석을 둔다.
- **감사 로그는 식별자만**: 인증 이벤트 기록 시 토큰이 아니라 `sub`(또는 `mIdx`)·action·timestamp만 남긴다. 예: `audit("login", { sub, ip })` — 토큰을 인자로 넘기지 않는다.
- **토큰 교환 실패 시 raw 에러 차단**: Hub의 token endpoint가 4xx/5xx를 반환해도 그 본문을 클라이언트에 그대로 전달하지 않고 일반화된 메시지(`authentication failed`)로 응답한다. 상세는 서버 로그(토큰 제외)에만.
- **open-redirect 방어 (B5)**: `?return_to=` 같은 deep-link 복원 파라미터를 받는 경우 login/callback 템플릿은 **허용 리스트(상대 경로만) + 정규화 후 재검증**을 거친다. **절대 URL은 허용하지 않는다** — `new URL(returnTo, origin)` 기반 origin 비교는 브라우저 URL 정규화(백슬래시→슬래시, protocol-relative, 선행 공백/제어문자) 때문에 우회되므로 쓰지 않는다.

  검증 순서(이 순서를 지킨다):
  1. `trim()` 후 `decodeURIComponent`를 더 이상 바뀌지 않을 때까지 반복 적용 (이중 인코딩 방어)
  2. 제어문자(`\t`·`\n`·`\r`·`\0` 등 `\x00-\x1F`) 포함 시 거부
  3. 모든 백슬래시(`\`)를 슬래시(`/`)로 치환 (브라우저가 `\`를 `/`로 해석하는 것에 선제 대응)
  4. 치환 결과가 **단일 `/`로 시작하고 두 번째 문자가 `/`가 아닐 때만** 허용 (즉 `//`·`/\`·`\\`·`\/` 류 protocol-relative 전부 거부)
  5. 콜론(`:`) 포함 등 스킴 형태(`https:evil.com`)면 거부
  6. 위 어느 하나라도 실패하면 **조용히 기본 경로(`/`)로 폴백**, 경고 로그(입력값 제외)만 남긴다

  허용되는 것은 오직 `/`로 시작하는 same-origin 상대 경로뿐이다. 외부 도메인 복귀가 정말 필요하면 코드에 하드코딩된 화이트리스트로만 처리하고 사용자 입력에서 받지 않는다.

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

**접두(`${ENV_PREFIX}`) 결정 (B3)** — 프로젝트마다 인증 환경변수 네이밍 컨벤션이 다르다(weaversmind 표준은 `IDENTITY_HUB_` 접두). 키 충돌·중복을 막기 위해 고정 키를 쓰지 않고 다음 순서로 접두를 정한다.

1. `--env-prefix` 명시값이 있으면 그대로 사용 (예: `IDENTITY_HUB_`)
2. 기존 `.env.example`(또는 `.env`)을 스캔해 `IDENTITY_HUB_` 접두 키가 **3개 이상**이면 `${ENV_PREFIX}` = `IDENTITY_HUB_`
3. 다른 일관된 접두(`*_HUB_`, `AUTH_` 등)가 3개 이상이면 그 접두 채택
4. 그 외 → 접두 없음 (`${ENV_PREFIX}` = 빈 문자열)

`.env.example`이 있으면 끝에 append, 없으면 새로 만든다.
이미 같은 키가 있으면(접두 적용 후 키 기준) 덮어쓰지 않고 "이미 존재함" 표시.

```env
# Identity Hub
${ENV_PREFIX}URL=${HUB_URL}
${ENV_PREFIX}REALM=${REALM}
${ENV_PREFIX}CLIENT_ID=${CLIENT_ID}
${ENV_PREFIX}REDIRECT_URI=${REDIRECT_URI}
# ${ENV_PREFIX}CLIENT_SECRET은 .env에만 두고 .env.example에는 빈 값 또는 생략
```

생성한 라우트 템플릿이 읽는 환경변수 키도 동일 `${ENV_PREFIX}`로 맞춘다(코드와 .env.example 키 불일치 방지).

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

### 8.5 dry-run 충돌 매트릭스 (B6)

`--dry-run`일 때는 "쓸 파일 목록"만 나열하지 않고, **각 설치 대상이 기존 상태와 어떻게 충돌하는지** 표로 보여준다. 사용자가 실제 실행 전에 무엇이 skip/머지/덮어쓰기 위험인지 한눈에 판단할 수 있어야 한다.

| 설치 경로 | 현재 상태 | 행동 |
|-----------|-----------|------|
| `${APP_DIR}/api/auth/login/route.ts` | 없음 | 신규 생성 |
| `${APP_DIR}/api/auth/callback/route.ts` | 이미 존재 | skip + 머지 권고 |
| `${MIDDLEWARE_PATH}` | 이미 존재 | skip + 머지 권고 (덮어쓰기 안 함) |
| `.env.example` | 일부 키 존재 | append (기존 키는 보존) |

행동 분류:
- **신규 생성**: 대상에 파일 없음 → 그대로 씀
- **skip + 머지 권고**: 이미 존재 → 쓰지 않고 사용자에게 수동 머지 안내
- **append**: `.env.example`/`.gitignore` 등 누적 대상 → 없는 항목만 추가
- **충돌(위험)**: §1.5 기존 OIDC 시그니처에 걸리는 경우 → abort 대상임을 표시

`--dry-run`은 어떤 파일도 쓰지 않으며, `/onboard` API도 호출하지 않는다(매트릭스 출력 후 종료).

### 9. 검증 및 사후 안내

생성된 파일 목록을 출력하고, **Keycloak Client 측에서 반드시 해야 할 일** 4개를 출력:

1. Redirect URI에 `${REDIRECT_URI}` 등록되어 있는지 확인
2. Web Origins 설정
3. `client_secret` 보관 (`/onboard` 응답 또는 Keycloak 콘솔)
4. 토큰 발급용 protocol mapper (`mIdx` 같은 커스텀 클레임이 필요한 경우)

`--dry-run`이 아닌 경우, 마지막에 `git status` 출력으로 어떤 파일이 추가/변경됐는지 사용자에게 명시.

## 안전 가드

- **기존 OIDC 자체 구현이 감지되면(§1.5) `--overlay-existing-oidc` 없이는 abort**. 라우트·미들웨어 2벌 공존을 원천 차단한다.
- Next.js 라우트 베이스는 `src/app`/`app`을 자동 감지(§5)하여 기존 레이아웃을 따른다. 임의로 `src/app`을 신규 생성해 라우트를 누락시키지 않는다.
- 기존 파일을 발견하면 **덮어쓰지 않는다**. 항상 "이미 존재함: `{path}` — 머지 권고" 출력 후 skip.
- 어떤 파일도 `.git/`, `node_modules/`, `dist/`, `build/` 안에는 쓰지 않는다.
- **토큰·secret raw 값은 로그·응답·리다이렉트에 절대 노출하지 않는다(§5 보안 계약).** 감사 로그는 `sub`/action만 남긴다.
- **`return_to`/`redirect` 파라미터는 same-origin 검증을 거친다(§5).** 검증 실패 시 기본 경로로 폴백.
- **`client_secret`은 기본적으로 stdout에 출력하지 않는다.** `--reveal-secret-to` 명시 시에만 지정 방식(stdout/clipboard/file)으로 전달(§4).
- `--admin-token`은 셸 히스토리에 남지 않도록 가능하면 stdin 또는 환경변수로 받는다.
- 실패 시 이미 생성한 파일을 자동 롤백하지 않고, 사용자에게 `git restore .` 명령을 안내한다 (`.git` 없으면 수동 정리 안내).

## 참고 자료

- 흐름 개요: `docs/flow-overview.md`
- Keycloak 설정 체크리스트: `docs/keycloak-checklist.md`
- 트러블슈팅: `docs/troubleshooting.md`
- 코드 컨트랙트 원본: `~/Workspace/identity-hub-frontend/src/lib/integration-guide/samples.ts` (ADR-007)
- Hub API: `~/Workspace/identity-hub/docs/feature/auth/02-api.md`, `~/Workspace/identity-hub/docs/feature/onboard/02-api.md`
