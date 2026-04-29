# redaction-rules

`--audience=external` 일 때 자동 적용. 최종 공개 전 사람 검수 필수.

## 치환 룰 (정규식 → 대체)

| 패턴 | 대체 |
|---|---|
| `(?i)weaversbrain` | Company (EdTech) |
| `(?i)speakingmax(?:app)?` | Company (EdTech) |
| `(?i)weaversmind` | Company (EdTech) |
| `(?i)maxaiapp` | Company (EdTech) |
| `identity-hub(?:-frontend)?` | SSO platform |
| `identity-keycloak` | Keycloak SPI |
| `maxai-([a-z0-9-]+)` | EdTech service ($1) |
| `speakingmax-([a-z0-9-]+)` | EdTech service ($1) |
| `speech-hub(?:-admin)?` | Speech platform |
| `sso-[a-z0-9-]+` | SSO tool |
| `b2c-[a-z0-9-]+` | Consumer service |
| `sso\.(?:dev-)?(?:qa-)?weaversbrain\.com` | {sso-domain} |
| `sso\.weaversmind\.com` | {sso-domain} |
| `dev-sso\.speakingmaxapp\.com` | {sso-dev-domain} |
| `sso\.maxaiapp\.com` | {sso-prod-domain} |
| 커밋 SHA (`[0-9a-f]{7,40}`) | (제거) |
| Jira key (`[A-Z]+-\d+`) | (제거) |

## 사람 이름

이메일·실명은 수동 확인. 자동 치환 규칙:
- `[a-z]+\.[a-z]+@[a-z0-9.-]+` (이메일) → `<role>@company`
- 한글 이름 2~4자 연속 + 직함(`님`, `책임`, `수석`) → 역할명

자동이 부정확할 수 있으므로 external 문서 Write 전에 사용자에게 "실명 자동 치환됨. 수동 확인 부탁" 안내.

## 보존 (치환하지 않음)

- 표준 기술 용어: `Keycloak`, `OAuth`, `JWT`, `SAML`, `SSO`
- 오픈 소스 프로젝트 이름: `Next.js`, `Spring Boot`, `FastAPI`
- 공개 도메인 지식: `RFC 6749`, `OpenID Connect`
- 언어·프레임워크 버전

## 치환 적용 순서

1. 도메인 URL
2. 레포 이름 (길이 긴 것부터)
3. 회사명
4. 사람 이름
5. 커밋 SHA / Jira 키

**순서 중요**: 회사명 먼저 치환하면 `identity-hub.weaversbrain.com` 같은 경우 도메인 치환이 깨진다.

## 예시

### 원본 (internal)

> "identity-hub-frontend에서 Next.js 16 마이그레이션을 완료. 15개 커밋, +6286/-726 라인. 관련 커밋 `e23696e`. 운영 도메인 `sso.maxaiapp.com`."

### 치환 후 (external)

> "SSO platform (frontend)에서 Next.js 16 마이그레이션을 완료. 15개 커밋, +6286/-726 라인. 운영 도메인 `{sso-prod-domain}`."

## 검수 체크리스트

Write 직전 문서에서 다음 단어 검색:
- `weaversbrain`, `speakingmax`, `maxai`, `identity-hub`, `keycloak-` (플랜·회사 문맥)
- 실명 2자 이상
- `\.com`, `\.co\.kr` (도메인 누락 여부)
- Jira/Linear 키 패턴

하나라도 남아 있으면 **Write 금지**, 사용자에게 보고.
