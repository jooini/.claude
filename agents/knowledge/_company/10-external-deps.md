# 외부 의존성

> 검증된 것 ✅ vs 추정 ❓ 분리. 코드 작성 전 ❓ 항목은 실제 버전 확인 필수.

## 음성 인식 (검증)

| SDK/API | 용도 | 검증된 사실 |
|---------|------|-------------|
| 셀바스 SDK (iOS/Android) | 클라이언트 음성 인식 | ✅ 클라이언트 팀 담당 |
| 클로바노트 STT | 회의록 자동 받아쓰기 | ✅ 사내용 |

❓ 셀바스 SDK 정확한 버전 / 호환 OS 범위 / 호환 안 되는 버전 — 미확인

## 인증 (검증)

- ✅ **Keycloak 24.x** (사용자 본인 메모리)
- ✅ **identity-hub 경유만** — Keycloak 직접 호출 금지

## 클라우드 (메모리/incident 기반 검증)

| 서비스 | 사용처 | 출처 |
|--------|--------|------|
| AWS Lambda | 국가별 URL 분기 (`B2C_LAUNCH_URLS`) | ✅ 2026-04-14 STT 외계어 incident 원인 |
| ClickHouse | 분석/이벤트 로그 (`{env}-wb-clickhouse`) | ✅ 메모리 |
| Redis | service-token 캐시 / refresh_token 보관 (Identity Hub) | ✅ workflows/sso.md |
| RDS | Keycloak 사용자 DB | ✅ 추정 (Keycloak 표준) |

❓ AWS Secrets Manager / S3 / Sentry 등 — 사용 여부 미확인

## 결제 (❓ 미확인)

- ❓ 결제 PG: 토스페이먼츠? KCP? 다른 곳? — 미확인
- ❓ 해외 결제 / 구독 모델 — 미확인
- 코드 작성 시 결제 관련 부분은 회사 확인 필수

## 함정 / 알려진 이슈 (검증)

- ⚠️ **AWS Lambda `B2C_LAUNCH_URLS.DEFAULT`** — 2026-04-14 STT 외계어 incident 원인. 환경 분기 default 안전한 쪽으로 설정 필수.
- ⚠️ **클로바노트는 사람 이름 부정확** — STT 결과 정정 필수

## 사용 시 주의

`✅` 만 신뢰. `❓` 항목은 코드에 반영 전 실제 확인 필수.
