# Test Strategy

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/test-strategy

---

## 1. 테스트 전략이란

무엇을, 얼마나, 어떻게 테스트할지에 대한 계획. 팀 전체가 동의한 기준.

**좋은 테스트 전략의 조건:**
- 리스크 기반 — 중요한 것부터
- 실행 가능 — 팀이 실제로 따를 수 있는
- 측정 가능 — 커버리지, 통과율 등 지표 존재
- 살아있는 문서 — 제품과 함께 진화

---

## 2. 테스트 피라미드

```
          /\
         /E2E\          적게 — 느리고 비쌈
        /──────\
       /  통합  \        중간 — 컴포넌트/서비스 조합
      /──────────\
     /    단위    \      많이 — 빠르고 저렴
    /______________\
```

**실용적 비율 (팀 상황에 따라 조정):**
- Unit: 60~70%
- Integration: 20~30%
- E2E: 5~10%

**Ice Cream Cone 안티패턴:**
```
    /E2E 많음\   ← 느리고 깨지기 쉬움
   /──────────\
  /  통합 중간 \
 /──────────────\
/  단위 거의 없음 \  ← 빠른 피드백 없음
```

---

## 3. 리스크 기반 테스트

모든 것을 테스트할 수 없다 → 리스크가 높은 것에 집중.

```
리스크 = 발생 확률 × 영향도

                  영향 낮음      영향 높음
발생 가능성 높음 │  중간 우선   │  최우선  │
발생 가능성 낮음 │  낮은 우선  │  높은 우선│
```

**최우선 테스트 대상:**
- 결제, 인증, 데이터 손실 관련 로직
- 자주 변경되는 코드
- 과거 버그가 많았던 영역
- 복잡한 비즈니스 로직

---

## 4. 테스트 레벨별 목적

### Unit Test
- **목적**: 함수/클래스 단위 로직 검증
- **속도**: 수 밀리초
- **격리**: 외부 의존성 모두 Mock
- **담당**: 개발자

```ts
// 순수 로직 테스트
describe('calculateDiscount', () => {
  it('VIP 고객에게 20% 할인 적용', () => {
    expect(calculateDiscount(10000, 'VIP')).toBe(8000)
  })
  it('일반 고객에게 할인 없음', () => {
    expect(calculateDiscount(10000, 'NORMAL')).toBe(10000)
  })
})
```

### Integration Test
- **목적**: 컴포넌트/서비스 간 상호작용 검증
- **속도**: 수백 밀리초~수 초
- **격리**: 실제 DB, 일부 외부 의존성
- **담당**: 개발자 + QA

```ts
// 실제 DB와 함께 테스트
it('주문 생성 시 재고 자동 감소', async () => {
  await productRepo.save({ id: 'p1', stock: 10 })
  await orderService.create({ productId: 'p1', quantity: 3 })
  const product = await productRepo.findById('p1')
  expect(product.stock).toBe(7)
})
```

### E2E Test
- **목적**: 실제 사용자 시나리오 검증
- **속도**: 수 초~수십 초
- **격리**: 없음 (실제 환경)
- **담당**: QA

```ts
// 사용자 관점 플로우
test('로그인 → 상품 구매 → 주문 확인', async ({ page }) => {
  await page.goto('/login')
  await page.fill('[name=email]', 'user@test.com')
  await page.fill('[name=password]', 'password')
  await page.click('[type=submit]')
  await expect(page).toHaveURL('/dashboard')
  // ... 구매 플로우
})
```

---

## 5. 테스트 전략 문서 구성

```markdown
# 프로젝트명 테스트 전략

## 1. 범위
- IN: 핵심 비즈니스 로직, API, UI
- OUT: 서드파티 라이브러리 내부, 레거시 미사용 코드

## 2. 테스트 환경
- 단위/통합: 로컬, CI
- E2E: 스테이징 환경

## 3. 도구
- Unit/Integration: Jest + @testing-library
- E2E: Playwright
- API: Supertest
- 커버리지: Istanbul (Jest 내장)

## 4. 커버리지 목표
- 전체 라인: 80% 이상
- 핵심 비즈니스 로직: 95% 이상
- E2E: 주요 Happy Path 100%

## 5. 완료 기준 (Definition of Done)
- 신규 기능: Unit + Integration 테스트 포함
- 버그 수정: 재발 방지 테스트 추가
- E2E: 주요 시나리오 커버

## 6. CI/CD 연동
- PR: Unit + Integration 자동 실행
- main 머지: E2E 자동 실행
- 실패 시 배포 차단
```

---

## 6. 테스트 메트릭

| 지표 | 설명 | 목표 |
|------|------|------|
| 코드 커버리지 | 테스트된 코드 비율 | 라인 80%+ |
| 테스트 통과율 | CI에서 통과하는 테스트 비율 | 99%+ |
| 테스트 실행 시간 | 전체 테스트 스위트 실행 시간 | PR: 5분 이내 |
| Flaky Test 비율 | 비결정적으로 실패하는 테스트 | 0% 목표 |
| 버그 탈출율 | 운영에서 발견된 버그 수 | 스프린트당 감소 추세 |

---

## 7. 안티패턴

- **커버리지만 채우는 테스트**: 의미 없는 assert → 실제 동작 검증
- **E2E 의존 전략**: 느리고 불안정 → 피라미드 균형
- **테스트 없는 버그 수정**: 수정 + 재발 방지 테스트 세트
- **Flaky Test 방치**: 신뢰도 저하 → 즉시 수정 또는 격리
- **QA만의 테스트**: 개발자도 단위/통합 테스트 작성
