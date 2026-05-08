# ADR-NNN: [결정 한 줄 요약]

> Status: Accepted / Superseded / Deprecated
> Date: YYYY-MM-DD
> Authors: 주인식, 현준
> Supersedes: ADR-MMM (있으면)

## Context (배경)

(왜 이 결정을 해야 했나 — 당시 상황, 제약, 트레이드오프)

예: "B2C 백엔드는 PHP 레거시이고 NestJS로 마이그레이션 중. 두 시스템이 동시에 Keycloak에 접근하면 토큰 발급 충돌이 발생함. 표준화가 필요."

## Decision (결정)

(무엇을 하기로 했나 — 명확하게)

예: "Keycloak 직접 호출은 금지. 모든 시스템은 Identity Hub를 경유하여 Keycloak에 접근한다. B2C 백엔드도 `IdentityHub_lib::getServiceToken()` 사용."

## Rationale (근거)

| 옵션 | 장점 | 단점 | 채택? |
|------|------|------|------|
| A: 각자 직접 Keycloak 호출 | 단순 | 충돌, 보안 키 분산 | ❌ |
| B: Identity Hub 경유 | 중앙화, 캐싱 | 단일 장애점 | ✅ |
| C: API Gateway 추가 | 더 일반적 | 인프라 추가 | ❌ |

## Consequences (결과)

### 긍정

- 보안 키(client_secret)가 Identity Hub 한 곳만 보유
- service-token 캐싱으로 Keycloak 부하 감소

### 부정

- Identity Hub 다운 시 모든 인증 영향 → identity-nginx 폴백 필요 (ADR-008 참조)
- 신규 컴포넌트 추가 시 Identity Hub 설정 필요 (배포 의존성)

## 검증 / 모니터링

- Keycloak 직접 호출 차단 확인: nginx access log에서 `host=keycloak.*` 외부 트래픽 0건
- service-token 발급률 알람: 분당 100건 초과 시 Slack
