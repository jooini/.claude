# 외부 의존성

> 외부 SDK/API의 우리만의 사용 패턴 — 호환성, 함정, 결정 근거.

## 음성 인식

| SDK/API | 버전 | 용도 | 호환 |
|---------|------|------|------|
| 셀바스 SDK (iOS) | 1.4.2 | 클라이언트 음성 인식 | iOS 14+ |
| 셀바스 SDK (Android) | 1.4.2 | 동일 | Android 8+ |
| 클로바노트 STT | API v2 | 회의록 (사내용) | - |

### 함정

- ⚠️ 셀바스 SDK 5.0 미만은 호환 안 됨 (음성 포맷 변경)
- ⚠️ 업데이트는 **현준과 사전 협의** 필수
- ⚠️ 클로바노트는 사람 이름 받아쓰기 약함 ("현준" → "홍주"/"현주")

## 인증

| SDK/API | 버전 | 용도 |
|---------|------|------|
| Keycloak | 24.x | identity-hub 의존 (직접 호출 금지, ADR-007) |

## 클라우드

| 서비스 | 사용처 |
|--------|--------|
| AWS Lambda | 국가별 URL 분기 (B2C_LAUNCH_URLS) |
| AWS Secrets Manager | client_secret, API 키 보관 |
| AWS S3 | 음성 파일 (180일 TTL) |
| ClickHouse Cloud | 분석 DB |

## 결제

| 서비스 | 사용 영역 |
|--------|---------|
| (예: 토스페이먼츠) | B2C 구독 |
| (예: Stripe) | B2B (해외) |

## 함정 / 알려진 이슈

- ⚠️ AWS Lambda `B2C_LAUNCH_URLS.DEFAULT` — 2026-04-14 incident 원인 (구버전 URL stale)
- ⚠️ 클로바노트는 회의록 정확도 낮음 — STT 자동 정정 후 검수 필수
- ⚠️ 토스 결제 webhook은 retry 정책 5회, idempotency key 필수
