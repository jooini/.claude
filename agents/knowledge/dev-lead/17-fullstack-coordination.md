# 풀스택 작업 조율

> Backend와 Frontend를 API 계약 중심으로 병렬 진행하고, 통합 검증으로 수렴한다.

---

## 1. 풀스택 조율의 목적

풀스택 작업의 실패는 보통 코드가 아니라 계약 불일치에서 발생한다.

dev-lead는 Backend와 Frontend가 동시에 작업하되 같은 계약을 바라보게 만든다.

**조율 목표:**
- API 계약을 먼저 고정한다.
- BE/FE 파일 소유권을 분리한다.
- mock과 실제 응답을 일치시킨다.
- 에러/로딩/빈 상태를 함께 설계한다.
- 통합 테스트로 최종 수렴한다.

---

## 2. 풀스택 작업 신호

- API 응답 필드 추가와 UI 표시가 함께 필요함
- 폼 제출과 서버 validation이 연결됨
- 인증/세션 플로우가 브라우저와 서버 모두 관련됨
- 에러 코드가 사용자 메시지로 매핑됨
- 프론트 mock과 백엔드 DTO가 함께 바뀜

---

## 3. API 계약 우선

계약은 병렬 구현의 기준이다.

```typescript
type OrderStatus = "CREATED" | "PAID" | "SHIPPED" | "CANCELLED";

interface OrderDetailResponse {
  id: string;
  status: OrderStatus;
  cancelable: boolean;
  cancelBlockReason: string | null;
  items: Array<{
    productName: string;
    quantity: number;
    price: number;
  }>;
}
```

### 계약 체크리스트

- [ ] enum 값 대소문자가 정해졌는가?
- [ ] nullable과 optional이 구분되었는가?
- [ ] 날짜 형식이 정해졌는가?
- [ ] 금액 단위가 정해졌는가?
- [ ] 에러 코드와 메시지 책임이 구분되었는가?
- [ ] pagination, sorting 규칙이 있는가?

---

## 4. BE/FE 병렬 실행

```python
contract = {
    "endpoint": "GET /orders/{id}",
    "fields": ["id", "status", "cancelable", "cancelBlockReason"],
    "errors": ["ORDER_NOT_FOUND", "ORDER_FORBIDDEN"],
}

Agent("backend-developer", task="OrderDetailResponse 계약 구현", contract=contract)
Agent("frontend-developer", task="OrderDetailResponse 계약 기반 화면 연결", contract=contract)
Agent("qa", task="계약 기반 통합 테스트 케이스 작성", contract=contract)
```

### 병렬 실행 조건

- 계약이 문서화됨
- backend와 frontend 소유 파일이 분리됨
- mock 데이터가 계약에서 파생됨
- 통합 검증 담당이 있음

---

## 5. Backend 책임

Backend는 서버 진실을 제공한다.

**Backend 책임:**
- 권한 검증
- 비즈니스 규칙 계산
- 에러 코드 정의
- 데이터 정합성 유지
- 응답 schema 안정성
- API 테스트 작성

### Backend 핸드오프

```typescript
Agent("backend-developer", {
  task: "주문 상세 응답에 취소 가능 여부 추가",
  contract: "OrderDetailResponse.cancelable",
  tests: ["OrderControllerTest", "OrderServiceTest"],
  constraints: ["기존 status 필드 의미 변경 금지"],
});
```

---

## 6. Frontend 책임

Frontend는 서버 진실을 사용자 경험으로 변환한다.

**Frontend 책임:**
- 로딩/에러/빈 상태 표시
- 서버 에러 코드와 메시지 매핑
- 버튼 활성화/비활성화
- 낙관적 업데이트 여부 결정
- 접근성/반응형 확인
- 컴포넌트 또는 E2E 테스트

```typescript
Agent("frontend-developer", {
  task: "cancelable 필드 기반 취소 버튼 상태 구현",
  states: ["loading", "enabled", "disabled", "error"],
  constraints: ["프론트에서 취소 가능 여부 재계산 금지"],
});
```

---

## 7. 에러 계약

에러 계약은 성공 응답만큼 중요하다.

| 에러 코드 | HTTP | Frontend 처리 |
|-----------|------|---------------|
| ORDER_NOT_FOUND | 404 | 상세 화면 not found |
| ORDER_FORBIDDEN | 403 | 권한 없음 안내 |
| ORDER_NOT_CANCELABLE | 409 | 버튼 비활성화 + 사유 표시 |
| ORDER_ALREADY_CANCELLED | 409 | 상태 새로고침 |

### 에러 계약 원칙

- 사용자가 복구할 수 있는 메시지를 제공한다.
- 내부 에러 메시지를 그대로 노출하지 않는다.
- 프론트는 에러 코드를 임의로 만들지 않는다.
- retry 가능한 오류와 불가능한 오류를 구분한다.

---

## 8. 통합 검증

통합 검증은 mock과 실제 API를 비교한다.

**검증 항목:**
- response schema 일치
- enum 값 일치
- error code mapping
- loading/error/empty state
- 권한 실패
- 모바일 표시

```python
Agent("code-tester", task="""
주문 상세 API와 화면 통합 검증을 수행한다.
Backend test, frontend typecheck, e2e smoke를 순서대로 실행하고 결과를 요약하라.
""")
```

---

## 9. 풀스택 충돌 패턴

| 충돌 | 원인 | 해결 |
|------|------|------|
| `null` vs `undefined` | 계약 부재 | 계약 수정 |
| enum 대소문자 불일치 | 서버/클라 독립 정의 | shared schema |
| 에러 코드 누락 | 성공 경로만 설계 | error contract |
| 프론트 재계산 | 서버 필드 불신 | 책임 재정의 |
| mock만 통과 | 실제 API 미검증 | integration test |

---

## 10. 디자인 조율

풀스택 작업도 UX가 필요하다.

| 상태 | UI 요구 |
|------|---------|
| loading | skeleton 또는 disabled |
| success | 상태 반영 |
| validation error | 필드 근처 메시지 |
| permission error | 접근 불가 안내 |
| conflict | 새로고침 또는 상태 설명 |

designer는 L 이상의 사용자 플로우 변경에서 투입한다.

---

## 11. 풀스택 체크리스트

- [ ] API 계약이 먼저 작성되었는가?
- [ ] BE/FE가 같은 enum과 null 규칙을 쓰는가?
- [ ] 에러 계약이 있는가?
- [ ] mock이 실제 계약에서 파생되었는가?
- [ ] 통합 테스트 또는 smoke test가 있는가?
- [ ] 프론트가 서버 비즈니스 규칙을 중복 계산하지 않는가?
- [ ] 사용자 상태 전환이 자연스러운가?

---

## 12. 최종 기준

풀스택 조율의 성공은 Backend와 Frontend가 각각 완성되는 것이 아니라, 사용자가 보는 흐름이 서버 진실과 정확히 연결되는 것이다.
