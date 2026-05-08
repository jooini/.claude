# Architecture Decision Records (ADR)

> 사내에서 결정된 핵심 아키텍처 선택. 새 ADR 추가 시 양식 따를 것 (맨 아래).

## ADR 인덱스

| 번호 | 제목 | 상태 | 날짜 |
|------|------|------|------|
| ADR-007 | B2C → Keycloak 직접 호출 금지, Identity Hub 경유 | ✅ Accepted | (2026-04 이전) |
| ADR-008 | Identity Hub 장애 시 identity-nginx 레거시 폴백 | ✅ Accepted | (2026-04-17 이전) |
| ❓ ADR-001~006 | 미문서화 (있으면 추출 필요) | - | - |

---

## ADR-007: Keycloak 직접 호출 금지, Identity Hub 경유

**Status**: Accepted
**Authors**: 주인식

### Context

- B2C 백엔드는 PHP CodeIgniter 레거시이고 NestJS로 마이그레이션 중
- 두 시스템이 동시에 Keycloak에 직접 접근하면 토큰 발급 충돌, client_secret 분산 보관
- 보안/일관성 표준화 필요

### Decision

- **Keycloak 직접 호출 금지**. 모든 컴포넌트는 Identity Hub 경유.
- B2C 백엔드는 `IdentityHub_lib::getServiceToken()` + `setAdminCurlOptions($token)` 패턴 사용
- service-token = client_credentials grant로 Identity Hub가 발급, Bearer 헤더로 admin API 호출

### Consequences

긍정:
- `client_secret`은 Identity Hub 한 곳만 보유
- service-token 캐싱(4분)으로 Keycloak 부하 감소
- 인증 로직 변경 시 한 곳만 수정

부정:
- Identity Hub 다운 시 모든 인증 영향 → ADR-008 폴백 필요
- 신규 컴포넌트 추가 시 Identity Hub 설정 필요 (배포 의존성)

### 검증

- nginx access log에서 `host=keycloak.*` 외부 트래픽 0건이어야 함
- service-token 발급률 알람: 분당 100건 초과 시 Slack ❓ 알람 임계치 미확인

---

## ADR-008: SSO 장애 시 레거시 인증 폴백

**Status**: Accepted

### Context

- ADR-007에 따라 Identity Hub가 단일 인증 게이트웨이
- Hub 장애 시 사용자 로그인 전면 차단 위험

### Decision

- Identity Nginx에서 Identity Hub 502/503/504 감지 시 레거시 인증 경로로 폴백
- `auth_mode=sso|legacy` 동적 전환 (`config/keycloak.php`)
- 2026-04-17 기준 LOCAL/DEV/QA/PP/LIVE 모두 `sso` 모드

---

## 새 ADR 작성 양식

```markdown
## ADR-NNN: [한 줄 결정 요약]

**Status**: Accepted | Superseded by ADR-MMM | Deprecated
**Date**: YYYY-MM-DD
**Authors**: (이름)

### Context
- 왜 이 결정이 필요했나 (당시 상황, 제약)

### Decision
- 무엇을 하기로 했나 (명확하게)

### Rationale
| 옵션 | 장점 | 단점 | 채택 |
|------|------|------|------|
| A    | ...  | ...  | ❌   |
| B    | ...  | ...  | ✅   |

### Consequences
긍정: ...
부정: ...

### 검증
- 어떻게 결정대로 굴러가는지 측정/모니터링
```

❓ 미문서화 ADR 추출 필요: ADR-001 ~ ADR-006 (있으면 회의록에서 추출)
