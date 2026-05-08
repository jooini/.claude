# [시스템 이름] 토폴로지

> 사내 컴포넌트 흐름 — Claude가 절대 알 수 없는 내부 아키텍처.

## 컴포넌트 표

| 컴포넌트 | 역할 | 호스트/도메인 | 의존 |
|---------|------|---------------|------|
| [예: B2C 백엔드] | 사용자 앱 API | `b2c.maxaiapp.com` | Identity Hub, MySQL |
| [예: Identity Hub] | SSO 중앙 인증 | `identity-hub.weaversbrain.com` | Keycloak, Redis |

## 호출 흐름 (텍스트 다이어그램)

```
[클라이언트 앱]
      │ HTTPS
      ▼
[B2C 백엔드 (PHP)]
      │ POST /api/v1/auth/refresh (Bearer service-token)
      ▼
[Identity Hub]
      │ Keycloak Admin API
      ▼
[Keycloak]
```

## 핵심 결정

- **refresh_token 보유 위치**: Identity Hub만. B2C 백엔드는 access_token만.
- **Keycloak 직접 호출 금지**: identity-hub 경유만 (ADR-007 참조)
- **폴백**: identity-nginx 502/503/504 시 레거시 인증 폴백

## 운영 메모

- 502 발생 시: `identity-nginx` 로그 확인 → upstream timeout 인지 체크
- access_token 만료 시: 자동 갱신 — 클라이언트는 재시도만
