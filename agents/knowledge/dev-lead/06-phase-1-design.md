# Phase 1 설계

> 구현 전에 계약, 구조, 테스트 전략을 정해 병렬 작업의 기준점을 만든다.

---

## 1. Phase 1의 목적

Phase 1은 "어떻게 만들 것인가"를 결정하는 단계다.

좋은 설계는 하위 에이전트가 독립적으로 움직여도 같은 방향으로 수렴하게 만든다.

**Phase 1 산출물:**
- 실행 계획
- API 또는 데이터 계약
- 파일 소유권
- 테스트 전략
- 위험 대응책
- 병렬 실행 경계

---

## 2. 언제 설계가 필요한가

| 작업 | 설계 필요도 | 이유 |
|------|-------------|------|
| S 수정 | 낮음 | 구현 위치가 명확함 |
| M 기능 | 중간 | 테스트와 에러 처리가 필요함 |
| L 풀스택 | 높음 | BE/FE 계약이 필요함 |
| XL 변경 | 필수 | 분할과 배포 전략이 필요함 |

### 설계 없이 진행 가능한 경우

- 변경 범위가 단일 함수다.
- 기존 패턴을 그대로 복사해 적용한다.
- 테스트가 요구사항을 이미 명확히 표현한다.

### 설계가 먼저인 경우

- API 응답이 바뀐다.
- DB schema가 바뀐다.
- 여러 에이전트가 병렬 구현한다.
- 사용자 플로우가 바뀐다.
- 배포 순서가 필요하다.

---

## 3. 설계 입력

Phase 1은 Phase 0 결과를 입력으로 받는다.

```markdown
## Phase 0 요약
- 관련 파일:
- 기존 패턴:
- 위험:
- 테스트 위치:
- 불확실성:

## 설계 목표
- 변경 후 사용자가 얻는 결과:
- 변경하지 않을 것:
- 수용 기준:
```

---

## 4. 아키텍처 결정

아키텍처 결정은 가능한 작고 명확해야 한다.

| 결정 항목 | 예시 |
|-----------|------|
| 책임 위치 | 검증 로직은 Controller가 아니라 Service |
| 데이터 흐름 | 프론트는 서버 상태를 query cache로 관리 |
| 실패 처리 | 외부 API 실패 시 retry 없이 명시적 에러 |
| 호환성 | 기존 응답 필드는 유지하고 신규 필드 추가 |
| 배포 전략 | nullable column 추가 후 backfill |

### 결정 기록 예시

```markdown
## 결정
주문 취소 가능 여부는 프론트에서 계산하지 않고 Backend의 `cancelable` 필드를 사용한다.

## 이유
배송 상태, 결제 상태, 권한이 서버 데이터에 의존한다.

## 영향
Backend는 `cancelable`과 `cancelBlockReason`을 응답한다.
Frontend는 버튼 활성화와 tooltip에 이 값을 사용한다.
```

---

## 5. API 계약 설계

Fullstack 작업에서는 API 계약이 병렬 실행의 기준이다.

```typescript
interface CancelOrderRequest {
  orderId: string;
  reasonCode: "USER_REQUEST" | "PAYMENT_FAILED" | "OTHER";
  memo?: string;
}

interface CancelOrderResponse {
  orderId: string;
  status: "CANCELLED";
  cancelledAt: string;
  refundStatus: "PENDING" | "COMPLETED" | "NOT_REQUIRED";
}
```

### API 계약 체크리스트

- [ ] 필수 필드와 선택 필드가 구분되었는가?
- [ ] 에러 코드가 명확한가?
- [ ] 기존 클라이언트 호환성이 유지되는가?
- [ ] null 가능성이 명시되었는가?
- [ ] 프론트 표시 규칙과 연결되는가?
- [ ] 테스트 fixture를 만들 수 있는가?

---

## 6. 파일 소유권 설계

병렬 구현에서는 쓰기 범위를 분리한다.

| 담당 | 소유 범위 | 금지 범위 |
|------|-----------|-----------|
| backend-developer | `server/order/**` | `web/**` |
| frontend-developer | `web/order/**` | `server/**` |
| qa | `tests/e2e/**` | 구현 파일 |
| reviewer | read-only | 직접 수정 금지 |

### 소유권 프롬프트

```python
Agent("frontend-developer", task="""
주문 취소 UI를 구현한다.
소유 범위: web/order/**
server/** 파일은 수정하지 말고, 계약이 부족하면 dev-lead에게 보고한다.
""")
```

---

## 7. 테스트 전략 설계

테스트는 구현 후에 떠올리는 것이 아니라 설계 단계에서 정한다.

| 변경 유형 | 테스트 |
|-----------|--------|
| 순수 로직 | unit |
| repository/DB | integration |
| API 계약 | contract/integration |
| 사용자 플로우 | e2e |
| 성능 | benchmark/load |
| 프롬프트 | eval set |

### 테스트 케이스 예시

```markdown
## 주문 취소 테스트
- 취소 가능한 주문은 취소된다.
- 이미 배송된 주문은 409를 반환한다.
- 다른 사용자의 주문은 403을 반환한다.
- 같은 요청을 두 번 보내도 중복 환불되지 않는다.
- 프론트 버튼은 cancelable=false일 때 비활성화된다.
```

---

## 8. Plan 에이전트 활용

복잡한 작업은 구현 전에 계획 전용 에이전트를 둘 수 있다.

```typescript
Agent("dev-lead", {
  mode: "plan-only",
  task: "정기 결제 해지 플로우 설계",
  constraints: [
    "기존 결제 API 호환",
    "환불 정책은 변경하지 않음",
    "BE/FE 병렬 구현 가능해야 함",
  ],
  output: ["contract", "task split", "test plan", "risk"],
});
```

### Plan 출력 검토 기준

- 구현 순서가 명확한가?
- 의존성이 줄어들었는가?
- 테스트가 수용 기준과 연결되는가?
- 위험 대응이 실행 가능한가?
- 소유 파일이 충돌하지 않는가?

---

## 9. 도메인 자문 배치

Phase 1에서는 구현보다 자문이 더 가치 있을 수 있다.

| 질문 | 자문 에이전트 |
|------|---------------|
| 요구사항이 모호함 | po |
| UX 흐름이 어색함 | designer |
| 데이터 정의가 불명확함 | data-analyst |
| 프롬프트 평가가 필요함 | prompt-engineer |
| 배포 위험이 있음 | ops-lead |
| 보안 우려가 있음 | code-reviewer |

---

## 10. 설계 산출물 템플릿

```markdown
# Phase 1 설계

## 목표

## 비목표

## 계약

## 작업 분해

## 에이전트 배치

## 테스트 전략

## 위험과 대응

## 완료 기준
```

---

## 11. 설계 완료 기준

- [ ] 목표와 비목표가 구분되었는가?
- [ ] API/데이터/UI 계약이 작성되었는가?
- [ ] 파일 소유권이 분리되었는가?
- [ ] 병렬 실행 가능한 단위가 나왔는가?
- [ ] 테스트 전략이 수용 기준을 덮는가?
- [ ] 위험 대응책이 구체적인가?
- [ ] 구현 에이전트가 바로 시작할 수 있는가?

---

## 12. 최종 기준

좋은 Phase 1은 구현자의 자유도를 없애는 것이 아니라 충돌 없이 전문성을 발휘할 경계를 만든다.
