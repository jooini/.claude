# TDD 모드 오케스트레이션

> QA가 실패 테스트를 설계하고, developer가 Green 구현을 만들고, reviewer가 품질을 확인한다.

---

## 1. TDD 모드의 목적

TDD 모드는 요구사항을 테스트로 먼저 고정한다.

특히 신규 기능이나 복잡한 비즈니스 규칙에서 효과적이다.

**TDD 흐름:**
1. 요구사항 정리
2. QA 테스트 케이스 설계
3. 실패 테스트 작성 또는 명세화
4. developer Green 구현
5. reviewer 품질 검토
6. tester 회귀 확인

---

## 2. TDD 모드 진입 조건

- 사용자가 "TDD로"라고 요청
- 신규 기능 추가
- 비즈니스 규칙이 복잡함
- 과거 버그가 반복됨
- 수용 기준을 테스트로 표현하기 쉬움

### TDD가 적합하지 않은 경우

- 단순 문구 변경
- 탐색적 UI 디자인
- 요구사항이 아직 불명확함
- 외부 시스템 의존이 커서 테스트 환경이 없음

---

## 3. QA 테스트 설계

TDD에서는 qa가 먼저 움직인다.

```python
Agent("qa", task="""
쿠폰 적용 기능의 TDD 테스트 케이스를 설계하라.
정상, 만료, 최소 주문 금액 미달, 중복 사용, 권한 없는 사용자를 포함하라.
각 케이스는 Given/When/Then 형식으로 작성하라.
""")
```

### 테스트 케이스 형식

```markdown
## TC-01 유효 쿠폰 적용
- Given: 사용 가능한 10% 쿠폰과 50,000원 주문
- When: 사용자가 쿠폰을 적용한다
- Then: 결제 금액은 45,000원이 된다

## TC-02 만료 쿠폰 거부
- Given: 만료된 쿠폰
- When: 사용자가 쿠폰을 적용한다
- Then: `COUPON_EXPIRED` 에러가 반환된다
```

---

## 4. 실패 테스트 작성

가능하면 실제 실패 테스트를 먼저 만든다.

| 도메인 | 테스트 형태 |
|--------|-------------|
| Backend | unit/integration |
| Frontend | component/e2e |
| Data | query snapshot |
| AI | eval case |
| DevOps | dry-run policy test |

```typescript
describe("CouponService.apply", () => {
  it("만료된 쿠폰은 적용할 수 없다", async () => {
    await expect(service.apply(expiredCouponRequest))
      .rejects
      .toThrow("COUPON_EXPIRED");
  });
});
```

---

## 5. 사용자 확인 지점

TDD에서 테스트가 곧 요구사항이므로, 애매한 정책은 구현 전에 확인한다.

**확인 필요 예시:**
- 쿠폰 중복 사용 정책
- 환불 시 쿠폰 복구 여부
- 소수점 할인 처리
- 만료 시간 기준 timezone
- 권한 없는 접근의 에러 코드

확인 없이 비즈니스 정책을 만들지 않는다.

---

## 6. Green 구현

developer는 테스트를 통과시키는 최소 구현을 만든다.

```typescript
Agent("backend-developer", {
  task: "QA가 정의한 쿠폰 테스트를 통과시키는 최소 구현",
  tests: ["coupon.service.spec.ts"],
  constraints: [
    "테스트 의도를 바꾸지 말 것",
    "비즈니스 정책 임의 추가 금지",
    "기존 MoneyValue 패턴 사용",
  ],
});
```

### Green 구현 원칙

- 테스트를 삭제하거나 약화하지 않는다.
- 하드코딩으로 테스트만 통과시키지 않는다.
- 기존 도메인 패턴을 따른다.
- 실패 경로의 에러 코드를 명확히 한다.

---

## 7. Refactor 단계

Green 후에는 구조를 정리한다.

**정리 대상:**
- 중복 조건문
- 테스트 fixture 중복
- 불명확한 네이밍
- 에러 생성 코드 반복
- 프론트 상태 분기 중복

```python
Agent("code-reviewer", task="""
TDD Green 이후 리팩터링 관점으로 리뷰하라.
동작 변경 제안보다 중복 제거, 네이밍, 책임 위치를 우선하라.
""")
```

---

## 8. Fullstack TDD

Fullstack에서는 계약 테스트가 중심이다.

```markdown
## 계약 테스트
- Backend는 `discountAmount`를 number로 반환한다.
- Frontend는 같은 값을 결제 요약에 표시한다.
- 에러 `COUPON_EXPIRED`는 만료 안내 toast로 매핑된다.
```

### Fullstack TDD 배치

| 단계 | 담당 |
|------|------|
| 수용 기준 | po + qa |
| API 계약 | backend + frontend |
| 실패 테스트 | qa |
| Backend Green | backend-developer |
| Frontend Green | frontend-developer |
| 통합 확인 | tester |

---

## 9. AI 기능 TDD

AI 기능은 deterministic test만으로 부족하다.

eval case를 먼저 만든다.

```python
Agent("prompt-engineer", task="""
문의 분류 프롬프트의 평가 케이스를 만든다.
정답 라벨, 허용 답변, 실패 예시를 포함하라.
""")
```

### AI TDD 기준

- 대표 입력 10개 이상
- 경계 입력 포함
- 실패 시 기대 fallback 명시
- 비용과 latency 측정 포함

---

## 10. TDD 실패 대응

| 실패 | 의미 | 대응 |
|------|------|------|
| 테스트가 구현 불가능 | 요구사항 재검토 |
| 테스트가 너무 세부적 | 행동 기반으로 수정 |
| Green 구현이 과도함 | 최소 구현으로 축소 |
| 기존 테스트 충돌 | 정책 충돌 확인 |

---

## 11. TDD 완료 기준

- [ ] QA 테스트 케이스가 수용 기준을 표현하는가?
- [ ] 실패 테스트가 먼저 확인되었는가?
- [ ] developer가 테스트 의도를 유지했는가?
- [ ] 모든 신규 테스트가 통과하는가?
- [ ] 기존 회귀 테스트가 통과하는가?
- [ ] reviewer가 구조와 edge case를 확인했는가?

---

## 12. 최종 기준

TDD 모드의 성공은 테스트가 많아지는 것이 아니라, 요구사항과 구현 사이의 해석 차이가 줄어드는 것이다.
