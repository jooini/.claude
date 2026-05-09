# Phase 2 구현

> 설계와 계약을 기준으로 구현 에이전트를 배치하고, 병렬 결과를 하나의 변경으로 통합한다.

---

## 1. Phase 2의 목적

Phase 2는 실제 코드와 문서를 변경하는 단계다.

dev-lead는 직접 구현만 하는 사람이 아니라 구현 흐름을 관리한다.

**핵심 책임:**
- 구현 단위를 에이전트별로 나눈다.
- 파일 소유권 충돌을 막는다.
- 계약 변경을 중심에 둔다.
- 중간 결과를 통합한다.
- 테스트 가능한 상태를 유지한다.

---

## 2. 구현 시작 전 확인

Phase 2는 다음이 준비된 뒤 시작한다.

- [ ] 목표가 한 문장으로 정리됨
- [ ] 변경 대상 파일이 대략 확인됨
- [ ] API/데이터 계약이 있거나 불필요함이 확인됨
- [ ] 파일 소유권이 정해짐
- [ ] 테스트 전략이 있음
- [ ] 리스크 높은 영역에 리뷰 계획이 있음

---

## 3. 구현 단위 나누기

| 작업 유형 | 단위 분리 기준 |
|-----------|----------------|
| Backend | controller/service/repository/test |
| Frontend | page/component/hook/state/test |
| Fullstack | contract/backend/frontend/e2e |
| Data | query/model/validation/report |
| AI | prompt/tool/eval/integration |
| DevOps | config/pipeline/monitor/rollback |

### 좋은 단위

- 독립적으로 구현 가능하다.
- 산출물이 명확하다.
- 테스트 방법이 있다.
- 다른 에이전트의 파일을 건드리지 않는다.

### 나쁜 단위

- "전체 기능 알아서 구현"
- "백엔드랑 프론트 모두 적당히 수정"
- "테스트도 필요하면 알아서"
- "관련 파일 전부 정리"

---

## 4. Backend 구현 패턴

```typescript
Agent("backend-developer", {
  task: "주문 취소 API 구현",
  ownership: [
    "server/order/order.controller.ts",
    "server/order/order.service.ts",
    "server/order/order.service.spec.ts"
  ],
  contract: "POST /orders/:id/cancel",
  constraints: [
    "배송 완료 주문은 취소 불가",
    "권한 없는 사용자는 403",
    "중복 요청은 idempotent하게 처리",
  ],
  output: ["changed files", "test command", "known risks"],
});
```

---

## 5. Frontend 구현 패턴

```typescript
Agent("frontend-developer", {
  task: "주문 상세 화면에 취소 버튼과 결과 상태를 연결",
  ownership: [
    "web/orders/OrderDetailPage.tsx",
    "web/orders/components/CancelOrderButton.tsx"
  ],
  contract: {
    endpoint: "POST /orders/:id/cancel",
    successStatus: "CANCELLED",
  },
  constraints: [
    "기존 버튼 컴포넌트 사용",
    "모바일에서 텍스트 overflow 금지",
    "서버 에러 메시지는 toast로 표시",
  ],
});
```

---

## 6. Fullstack 동시 구현

Fullstack 작업은 계약을 기준으로 병렬화한다.

```python
contract = {
    "endpoint": "GET /orders/:id",
    "response_addition": {
        "cancelable": "boolean",
        "cancelBlockReason": "string | null",
    },
}

backend = Agent("backend-developer", task="응답 필드 추가", contract=contract)
frontend = Agent("frontend-developer", task="취소 버튼 활성화 연결", contract=contract)
qa = Agent("qa", task="계약 기반 통합 시나리오 작성", contract=contract)
```

### 병렬 구현 원칙

- 계약이 확정되기 전에는 병렬 구현하지 않는다.
- mock은 계약에서 파생한다.
- 서버와 클라이언트의 enum 이름을 맞춘다.
- 통합 단계에서 schema/type mismatch를 먼저 확인한다.

---

## 7. Codex 대안 구현

L 이상 작업에서는 대안 구현이 가치 있다.

**대안 구현을 요청할 때:**
- 알고리즘 선택지가 여러 개다.
- 성능 최적화 방법이 불확실하다.
- 기존 설계를 건드릴지 말지 애매하다.
- 리뷰에서 설계 논쟁이 예상된다.

```typescript
Agent("codex", {
  task: "캐시 무효화 로직의 대안 구현 제안",
  mode: "alternative-implementation",
  constraints: [
    "기존 public API 변경 금지",
    "코드 변경 없이 설계와 patch 후보만 제시",
  ],
});
```

---

## 8. 구현 중 수렴 관리

dev-lead는 하위 결과를 그대로 합치지 않는다.

**수렴 시 확인할 것:**
- 파일 충돌이 없는가?
- 같은 개념의 이름이 일치하는가?
- 에러 처리 방식이 일관적인가?
- 테스트 fixture가 계약과 같은가?
- 문서와 타입이 같이 갱신되었는가?

### 수렴 메모 예시

```markdown
## 통합 판단
- Backend는 `cancelBlockReason`을 nullable string으로 구현
- Frontend mock은 undefined를 사용함
- 계약은 null로 확정
- Frontend fixture를 null 기반으로 수정 필요
```

---

## 9. 구현 산출물 형식

각 구현 에이전트는 다음을 보고해야 한다.

```markdown
## 변경 파일
- ...

## 구현 내용
- ...

## 테스트
- 실행:
- 결과:

## 남은 위험
- ...

## 리뷰 요청 포인트
- ...
```

---

## 10. 구현 중 금지 행동

- 사전 합의 없이 파일 소유권을 넘지 않는다.
- 계약을 몰래 바꾸지 않는다.
- 실패 테스트를 숨기지 않는다.
- unrelated refactor를 끼워 넣지 않는다.
- 타입 오류를 `any`로 덮지 않는다.
- 사용자 요구사항에 없는 정책을 만들지 않는다.

---

## 11. 구현 완료 기준

- [ ] 모든 담당 단위가 구현되었는가?
- [ ] 계약과 코드가 일치하는가?
- [ ] 타입/빌드 오류가 없는가?
- [ ] 최소 테스트가 추가되었는가?
- [ ] 변경 범위 밖 수정이 없는가?
- [ ] 리뷰자가 볼 포인트가 정리되었는가?

---

## 12. 최종 기준

Phase 2의 성공은 코드가 작성되었는지가 아니라, 여러 구현 결과가 계약 중심으로 충돌 없이 합쳐졌는지로 판단한다.
