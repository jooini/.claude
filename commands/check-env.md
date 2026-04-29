# /check-env - 환경 설정 일관성 검증

다중 프로젝트 간 환경변수, URL 설정의 일관성을 검증한다.
2026-02-06 401 에러의 근본 원인이었던 "Keycloak 인스턴스 불일치" 같은 문제를 사전 차단한다.

## 사용법

- `/check-env` - 전체 프로젝트 환경 설정 검증
- `/check-env local` - 로컬 환경만
- `/check-env dev` - dev 서버 환경만

## 인자

$ARGUMENTS

## 수행 작업

### 1단계: 로컬 환경 설정 수집

아래 파일들에서 Identity Hub URL, Keycloak URL 관련 설정을 추출:

| 프로젝트 | 파일 | 확인할 키 |
|----------|------|----------|
| maxai-b2c-backend | `.env` | `IDENTITY_HUB_URL`, `KEYCLOAK_REALM` |
| maxai-b2c-backend | `application/config/keycloak.php` | `identity_hub.url`, `server_url`, `realm` |
| maxai-b2c-backend | `maxAI/src/config/inc/define.js` | `identityHubUrl` (LOCAL/DEV/PROD 분기) |
| identity-hub | `.env.local`, `.env.dev` | `KEYCLOAK_SERVER_URL`, `KEYCLOAK_INTERNAL_URL` |
| maxai-docker | `.env.dev` | `IDENTITY_HUB_URL`, `KEYCLOAK_*` |
| weaversbrain-infra-docker | `local/php83/.env-maxai-b2c-backend` | `IDENTITY_HUB_URL` |

프로젝트 경로:
- `~/Workspace/maxai-b2c-backend/`
- `~/Workspace/identity-hub/`
- `~/Workspace/maxai-docker/`
- `~/Workspace/weaversbrain-infra-docker/`

### 2단계: 일관성 검증

다음 규칙으로 검증:

1. **Keycloak URL 일관성**: 프론트엔드(`define.js`)와 백엔드(`.env`)가 같은 Keycloak 인스턴스를 가리키는지
2. **Identity Hub URL 일관성**: PHP `.env`와 Docker compose의 URL이 일치하는지
3. **Realm 일관성**: 모든 곳에서 같은 realm 사용하는지
4. **Client ID 일관성**: `KEYCLOAK_CLIENT_ID`가 일치하는지

### 3단계: dev 서버 환경 (인자가 dev일 때)

SSH로 dev2-backend에 접속하여 컨테이너 내부 환경변수 확인:
```bash
ssh dev2-backend "docker exec maxai-b2c-backend cat /workspace/maxai-b2c-backend/.env | grep -E 'IDENTITY_HUB|KEYCLOAK'"
ssh dev2-backend "docker exec dev-maxai-identity-hub env | grep -E 'KEYCLOAK|REDIS|DATABASE'"
```

### 4단계: 결과 출력

| 설정 | 프론트엔드 | 백엔드 .env | Docker | 일치 |
|------|-----------|------------|--------|------|

불일치 항목이 있으면 경고와 함께 어떤 값으로 통일해야 하는지 제안한다.
