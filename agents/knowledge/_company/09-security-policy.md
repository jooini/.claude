# 보안 정책

> 검증된 것 ✅ vs 추측 ❓ 분리. 운영 적용 전 ❓ 항목은 확인 필수.

## 검증된 정책 (메모리/workflows 기반)

### 인증 (SSO)

- ✅ **계정 중복 허용**: 전화번호/이메일 중복 허용 (레거시 유지)
- ✅ **refresh_token 보유 위치**: Identity Hub만. B2C 백엔드는 access_token만
- ✅ **PHP 세션/쿠키에 refresh_token 저장 금지**
- ✅ **토큰 갱신**: `POST {hub}/api/v1/auth/refresh` body `{access_token}` 경유
- ✅ **`getUserByUsername`** 호출 시 `exact=True` 필수
- ✅ **Keycloak 직접 호출 금지** — identity-hub 경유만
- ✅ **인증 모드**: `auth_mode=sso|legacy` (config/keycloak.php). 2026-04-17 기준 LOCAL/DEV/QA/PP/LIVE 모두 `sso`

### 키 / 토큰 관리

- ✅ **`client_secret`**: Identity Hub만 보유
- ✅ **service-token**: TTL 5분, Redis 캐시 4분 (4:30 시점 fail 위험)
- ✅ **사내 cert**: `verify_peer=false` 필요 — 운영에서 켜면 다운

### 응답 보안

- ✅ stack trace 운영 환경 노출 금지
- ✅ password/passwordHash 응답에 절대 포함 금지

## ❓ 미확인 정책 (회사 결정 확인 필요)

| 항목 | 임시 가정 | 확인 필요 |
|------|---------|----------|
| 비밀번호 최소 길이 | 12자 (NIST 권장) | 실제 사내 정책? |
| 비밀번호 복잡도 | 대/소/숫자/특수 | 실제 사내 정책? |
| MFA 필수 대상 | admin, 결제 | 실제 정책? |
| 세션 만료 (access) | 15분 | 실제 값? |
| 세션 만료 (refresh) | 14일 | 실제 값? |
| API 키 보관 위치 | AWS Secrets Manager (추정) | 실제? |
| API 키 로테이션 주기 | 분기별 (추정) | 실제? |
| user enumeration 정책 | 일반 SaaS 가정 → 명시 | 실제 결정? |
| Sentry 사용 | 추정 | 실제? |

## 데이터 분류 (가이드라인 — ❓ 확인)

| 등급 | 예시 | 보관 |
|------|------|------|
| 공개 | 마케팅 콘텐츠 | 자유 |
| 내부 | 사내 문서 | weaversbrain Notion (추정) |
| 민감 | 사용자 음성 | 암호화 저장, ❓ TTL |
| 기밀 | 비밀번호 hash, 키 | 격리 DB |

## 함정 (검증)

- ⚠️ admin API 호출 시 service-token 4:30 시점 fail 위험 (TTL 5분 / 캐시 4분 갭)
- ⚠️ 사내 cert이라 `verify_peer=false` — 운영에서 실수로 켜면 다운
- ⚠️ Keycloak 직접 호출 금지 (identity-hub 경유만)

## 사용 시 주의

이 파일의 ✅ 만 신뢰. ❓ 항목은 코드에 반영하기 전 회사 결정 확인 필수.
