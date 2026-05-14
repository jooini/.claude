# 사내 라이브러리 / 함수 카탈로그

> B2C 백엔드 (PHP CodeIgniter) 의 사내 인증 라이브러리. 외부에는 없는 우리 코드.

## 주요 함수

### `IdentityHub_lib::getServiceToken()`

- **목적**: B2C → identity-hub admin API 호출용 service-token 발급
- **인증**: client_credentials grant
- **캐싱**: 발급 후 4분 TTL Redis 캐시
- **사용 예**:
  ```php
  $token = IdentityHub_lib::getServiceToken();
  $opts  = setAdminCurlOptions($token);
  ```

### `setAdminCurlOptions($token)`

- **목적**: admin API curl 호출용 헤더/SSL 옵션 묶음
- **포함**: `Authorization: Bearer`, `X-Service-Caller: b2c`, SSL verify off (사내 cert)

## 사용 규칙

- ✅ admin API 호출 시 위 두 함수 함께 사용
- ❌ Keycloak 직접 호출 금지 — identity-hub 경유만
- ❌ token 직접 캐싱 금지 — `getServiceToken()` 내부에서 처리

## 함정

- service-token TTL은 5분, 캐시는 4분 — 타임아웃 회피
- 사내 cert이라 `verify_peer=false` 필요 — 운영에서 실수로 켜면 다운
