# 보안 정책

> 회사가 채택한 구체 정책. OWASP 일반론 X, 우리 결정 O.

## 인증 정책

| 항목 | 정책 | 비고 |
|------|------|------|
| 비밀번호 최소 길이 | 12자 | NIST 권장 추월 |
| 비밀번호 복잡도 | 대/소/숫자/특수 모두 | |
| MFA 필수 대상 | admin, 결제 | 일반 사용자는 옵션 |
| 세션 만료 | access 15분, refresh 14일 | |
| refresh_token 보유 위치 | **Identity Hub만** | B2C 백엔드 보유 금지 (ADR-007) |

## 키 / 토큰 관리

| 종류 | 보유 위치 | 갱신 |
|------|----------|------|
| Keycloak `client_secret` | Identity Hub만 | AWS Secrets Manager |
| service-token | 발급 후 4분 캐시 | 자동 갱신 |
| API 키 (외부 서비스) | AWS Secrets Manager | 분기별 로테이션 |

## 데이터 분류

| 등급 | 예시 | 보관 |
|------|------|------|
| 공개 | 마케팅 콘텐츠 | 자유 |
| 내부 | 사내 문서 | weaversbrain Notion |
| 민감 | 사용자 음성 | 암호화 저장, 180일 TTL |
| 기밀 | 비밀번호 hash, 키 | 격리 DB, 접근 로그 |

## 응답 보안

- ❌ stack trace 운영 환경 노출 금지
- ❌ password/passwordHash 응답에 절대 포함 금지
- ❌ user enumeration 가능한 에러 메시지 (예: "이메일 없음" vs "비밀번호 틀림" 구분)
  - **회사 결정**: 일반 SaaS이므로 UX 우선 → 명시 (보안 민감 시스템 아님)
- ✅ 모든 에러는 `X-Request-ID` 로 Sentry 추적

## 함정

- ⚠️ admin API 호출 시 service-token TTL은 5분, 캐시는 4분 — 4분 30초 시점 호출은 fail
- ⚠️ 사내 cert이라 `verify_peer=false` — 운영에서 켜면 다운
