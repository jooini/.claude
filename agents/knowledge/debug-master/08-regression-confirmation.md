# 회귀 확인

> Phase 7: CONFIRM. 고쳤다는 말은 실패가 다시 자동으로 잡힌다는 뜻까지 포함한다.

---

## 1. 확인 단계의 목적

수정 후 확인은 단순히 한 번 실행해 보는 단계가 아니다.
기존 재현 케이스가 실패에서 성공으로 바뀌었고, 주변 기능이 깨지지 않았으며, 같은 문제가 다시 들어오면 테스트가 잡는다는 것을 증명한다.

확인 대상:

- [ ] 원래 재현 스크립트
- [ ] 새 회귀 테스트
- [ ] 관련 단위/통합 테스트
- [ ] 핵심 사용자 경로
- [ ] 운영 모니터링 지표

---

## 2. 확인 순서

```
1. 수정 전 실패하던 재현 케이스 실행
2. 가장 작은 단위 테스트 실행
3. 관련 통합 테스트 실행
4. 필요 시 E2E 또는 smoke test 실행
5. 운영/스테이징 지표 확인
```

작은 테스트부터 시작하면 실패 원인을 빠르게 찾을 수 있다.
E2E부터 실행하면 느리고 신호가 흐려진다.

---

## 3. 회귀 테스트 작성 기준

좋은 회귀 테스트는 과거 버그의 조건을 직접 표현한다.

```typescript
it('동시 재고 예약이 재고 수량을 초과해 성공하지 않는다', async () => {
    await productRepository.save({ id: 'p-1', stock: 1 });

    const results = await Promise.allSettled([
        inventoryService.reserve('p-1', 1),
        inventoryService.reserve('p-1', 1),
    ]);

    const successCount = results.filter((result) => result.status === 'fulfilled').length;
    const product = await productRepository.findById('p-1');

    expect(successCount).toBe(1);
    expect(product.stock).toBe(0);
});
```

테스트 이름에 버그의 조건을 남긴다.
"should work"는 회귀 의도를 설명하지 못한다.

---

## 4. 재현 스크립트 재실행

```bash
set -euo pipefail

echo "before fix reproduction should now pass"
./scripts/reproduce-order-race.sh

echo "related tests"
npm test -- inventory.service.spec.ts
npm test -- order.service.spec.ts
```

수정 전 실패했던 명령을 그대로 다시 실행한다.
명령 자체가 바뀌었다면 무엇이 바뀌었는지 기록한다.

---

## 5. Python 회귀 테스트 예시

```python
import pytest

from billing import calculate_next_charge_at

@pytest.mark.parametrize(
    ("now", "expected"),
    [
        ("2026-02-28T23:59:59+09:00", "2026-03-31T00:00:00+09:00"),
        ("2026-04-30T12:00:00+09:00", "2026-05-31T00:00:00+09:00"),
    ],
)
def test_month_end_billing_does_not_skip_next_month(freeze_time, now, expected):
    freeze_time(now)
    assert calculate_next_charge_at("Asia/Seoul").isoformat() == expected
```

시간, locale, timezone 관련 버그는 fixture로 고정해야 한다.
현재 시간에 의존하면 나중에 다시 flaky해진다.

---

## 6. 통합 테스트 확인

```bash
docker compose up -d postgres redis
pytest tests/integration/test_order_checkout.py -q
npm run test:integration -- --runInBand
```

통합 테스트에서는 실제 DB constraint, transaction, serialization, cache 동작을 확인한다.
mock 단위 테스트만으로는 인프라 경계 버그를 잡기 어렵다.

---

## 7. E2E 확인이 필요한 경우

E2E가 필요한 상황:

- [ ] UI 상태와 API 응답이 함께 영향을 받는다.
- [ ] 인증/세션/cookie 경계가 원인이었다.
- [ ] 결제, 주문, 가입처럼 사용자 플로우 전체가 중요하다.
- [ ] 브라우저별 차이가 원인 후보였다.

```typescript
import { test, expect } from '@playwright/test';

test('쿠폰 적용 후 결제 플로우가 완료된다', async ({ page }) => {
    await page.goto('/cart');
    await page.fill('[name=couponCode]', 'SPRING');
    await page.click('[data-testid=apply-coupon]');
    await expect(page.getByTestId('checkout-button')).toBeEnabled();
    await page.click('[data-testid=checkout-button]');
    await expect(page.getByText('주문이 완료되었습니다')).toBeVisible();
});
```

---

## 8. 운영 확인

운영 장애였다면 배포 후 모니터링을 확인한다.

```bash
curl -sS "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=sum(rate(http_requests_total{route="/api/orders",status=~"5.."}[5m]))' \
    | jq .
```

확인할 지표:

- [ ] 에러율
- [ ] latency p95/p99
- [ ] retry 횟수
- [ ] DB lock wait
- [ ] queue lag
- [ ] memory/CPU

---

## 9. 회귀 확인 표

```markdown
| 확인 항목 | 명령/링크 | 결과 |
|-----------|-----------|------|
| 재현 스크립트 | `./scripts/reproduce-order-race.sh` | 통과 |
| 단위 테스트 | `npm test -- inventory.service.spec.ts` | 통과 |
| 통합 테스트 | `pytest tests/integration/test_checkout.py` | 통과 |
| 운영 에러율 | dashboard link | 5xx 0.8% → 0.02% |
| lock wait | dashboard link | p95 3.2s → 20ms |
```

---

## 10. 실패 시 대응

확인 단계에서 실패하면 수정 단계로 돌아가지 말고 먼저 실패 성격을 분류한다.

- [ ] 원래 증상이 그대로 재현되는가?
- [ ] 새로운 실패인가?
- [ ] 테스트 fixture가 잘못되었는가?
- [ ] 수정이 일부 경로에만 적용되었는가?
- [ ] 환경 차이인가?

원래 증상이 그대로라면 가설 검증이 부족했던 것이다.
새로운 실패라면 사이드 이펙트 분석을 다시 한다.

---

## 11. 확인 완료 기준

- [ ] 기존 재현 케이스가 통과한다.
- [ ] 회귀 테스트가 실패 조건을 포함한다.
- [ ] 관련 테스트가 통과한다.
- [ ] 운영 이슈라면 지표가 안정화되었다.
- [ ] 남은 리스크가 기록되었다.
- [ ] 임시 로그와 feature flag 상태를 정리했다.
