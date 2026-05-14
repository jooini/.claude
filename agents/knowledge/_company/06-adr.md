# Architecture Decision Records (ADR)

> 사내에서 결정된 핵심 아키텍처 선택. 새 ADR 추가 시 양식 따를 것 (맨 아래).

## ADR 인덱스

| 번호 | 제목 | 상태 | 날짜 |
|------|------|------|------|
| ADR-008 | Identity Hub 장애 시 identity-nginx 레거시 폴백 | ✅ Accepted | (2026-04-17 이전) |
| ❓ ADR-001~007 | 미문서화 (있으면 추출 필요) | - | - |

---

## ADR-008: SSO 장애 시 레거시 인증 폴백

**Status**: Accepted

### Context

- Identity Hub가 단일 인증 게이트웨이
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
