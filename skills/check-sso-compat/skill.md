---
name: check-sso-compat
description: B2C 코드 변경 시 SSO 호환성을 검증한다. AUTH_MODE 분기, JWT 검증, Identity Hub 연동이 정상인지 체크. "/check-sso-compat", "SSO 호환성", "SSO 체크" 등으로 트리거.
allowed-tools: Bash, Read, Glob, Grep
---

# Check SSO Compatibility

B2C Backend 코드 변경이 SSO 통합인증과 호환되는지 검증한다.

## 검증 대상

SSO 관련 핵심 파일들:

| 파일 | 역할 | 변경 시 위험도 |
|------|------|-------------|
| `libraries/Auth.php` | 인증 라이브러리 | 🔴 높음 |
| `libraries/KeycloakJwt.php` | JWT 검증 | 🔴 높음 |
| `libraries/KeycloakAdmin.php` | Keycloak Admin API | 🔴 높음 |
| `middleware/Auth_middleware.php` | 인증 미들웨어 | 🔴 높음 |
| `config/sso.php` | SSO 설정 | 🟡 중간 |
| `helpers/sso_helper.php` | SSO 헬퍼 | 🟡 중간 |

## 실행 절차

### 1단계: 변경 파일 수집

```bash
cd ~/Workspace/maxai-b2c-backend
git diff --name-only
```

### 2단계: SSO 영향 판별

변경 파일이 위 핵심 파일에 해당하거나, SSO 관련 코드를 포함하는지 확인:

```bash
# 변경 파일에서 SSO 관련 키워드 검색
git diff | grep -E "(AUTH_MODE|sso|keycloak|jwt|identity.hub|access_token|refresh_token|X-SSO)" || echo "SSO 관련 변경 없음"
```

### 3단계: 호환성 체크리스트

| # | 항목 | 검증 방법 |
|---|------|----------|
| 1 | AUTH_MODE 분기 유지 | `grep -n "AUTH_MODE" [변경파일]` — legacy/sso 양쪽 분기 존재 확인 |
| 2 | JWT 검증 로직 무결성 | KeycloakJwt 변경 시 JWKS 캐시, RS256, aud/azp 검증 유지 확인 |
| 3 | Identity Hub API 호출 | URL 패턴 (`/api/v1/*`), 인증 헤더 (Bearer token) 확인 |
| 4 | 폴백 처리 | Identity Hub 502/503/504 시 레거시 폴백 경로 존재 확인 |
| 5 | 세션 처리 | SSO 모드에서 세션/쿠키 올바르게 설정되는지 확인 |
| 6 | 에러 전파 | Identity Hub 에러 응답이 클라이언트에 적절히 전달되는지 확인 |
| 7 | 회원 타입 처리 | B2B/B2C 분기에서 SSO 경로가 올바른지 확인 |

### 4단계: 자동 테스트 실행

```bash
cd ~/Workspace/maxai-b2c-backend

# PHPUnit 테스트 (있으면 실행)
php vendor/bin/phpunit --filter SSO 2>/dev/null || echo "SSO 테스트 없음"

# 또는 전체 테스트
php vendor/bin/phpunit 2>/dev/null || echo "테스트 실패 또는 미설정"
```

### 5단계: 결과 보고

```
## SSO 호환성 검증 결과

**변경 범위**: [변경 파일 수] 파일
**SSO 영향**: 있음/없음

### 체크리스트
| # | 항목 | 결과 |
|---|------|------|
| 1 | AUTH_MODE 분기 | ✅/❌ |
| 2 | JWT 검증 | ✅/❌/N/A |
| 3 | Identity Hub API | ✅/❌/N/A |
| 4 | 폴백 처리 | ✅/❌/N/A |
| 5 | 세션 처리 | ✅/❌/N/A |
| 6 | 에러 전파 | ✅/❌/N/A |
| 7 | 회원 타입 | ✅/❌/N/A |

### 발견된 이슈
- [있으면 나열]

### 권고
- [수정 필요 사항]
```

## 규칙

- 이 스킬은 검증만 수행, 코드 수정은 하지 않음
- 🔴 높음 파일 변경 시 반드시 이 스킬 실행 권고
- SSO 관련 변경 없으면 "SSO 영향 없음"으로 빠르게 종료
