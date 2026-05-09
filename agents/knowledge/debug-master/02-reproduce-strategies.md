# 재현 전략

> Phase 1: REPRODUCE. 재현되지 않는 버그는 아직 분석 대상이 아니라 관찰 대상이다.

---

## 1. 재현의 목표

재현은 "한 번 보았다"가 아니라 "조건을 통제하면 다시 만들 수 있다"는 뜻이다.
재현 단계의 목적은 실패를 반복 가능한 형태로 고정하여 이후 수집, 범위 축소, 검증의 기준선을 만드는 것이다.

좋은 재현 결과에는 다음이 포함된다.

- [ ] 실행 명령 또는 사용자 동작 순서
- [ ] 입력 데이터와 계정 상태
- [ ] 환경 정보
- [ ] 기대 결과와 실제 결과
- [ ] 성공/실패 빈도
- [ ] 마지막 정상 버전 또는 정상 조건

---

## 2. 재현 케이스 최소화

처음부터 전체 E2E 플로우를 디버깅하지 않는다.
실패를 유지하면서 입력, 단계, 의존성을 줄인다.

| 축소 대상 | 질문 | 예시 |
|-----------|------|------|
| 입력 | 어떤 필드가 없어도 실패하는가? | 쿠폰 제거 후도 실패 |
| 데이터 | 특정 사용자만 실패하는가? | `userId=42`만 실패 |
| 단계 | 어느 API부터 실패하는가? | 결제 전 재고 예약에서 실패 |
| 환경 | 로컬/스테이징/운영 중 어디서 실패하는가? | 스테이징만 실패 |
| 시간 | 특정 시간대에만 실패하는가? | 배치 실행 중 실패 |

---

## 3. API 버그 재현

```bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN="${TOKEN:?TOKEN is required}"

curl -sS -D /tmp/headers.txt \
    -X POST "$BASE_URL/api/orders" \
    -H "authorization: Bearer $TOKEN" \
    -H "content-type: application/json" \
    -H "x-debug-trace-id: reproduce-order-001" \
    -d '{
        "userId": "user-42",
        "items": [
            { "productId": "product-1", "quantity": 2 }
        ],
        "couponCode": "SPRING"
    }' | jq .

cat /tmp/headers.txt
```

재현 스크립트는 실행자가 바뀌어도 같은 결과를 내야 한다.
토큰, URL, 날짜처럼 바뀌는 값은 환경변수로 빼고, 실패 입력은 파일로 남긴다.

---

## 4. UI 버그 재현

```typescript
import { test, expect } from '@playwright/test';

test('쿠폰 적용 후 결제 버튼이 비활성화되는 문제 재현', async ({ page }) => {
    await page.goto('http://localhost:3000/login');
    await page.fill('[name=email]', 'debug-user@example.com');
    await page.fill('[name=password]', 'password');
    await page.click('button[type=submit]');

    await page.goto('http://localhost:3000/cart');
    await page.fill('[name=couponCode]', 'SPRING');
    await page.click('button[data-testid=apply-coupon]');

    await expect(page.getByText('쿠폰이 적용되었습니다')).toBeVisible();
    await expect(page.getByTestId('checkout-button')).toBeEnabled();
});
```

UI 재현은 눈으로 클릭 순서를 적는 것보다 자동화 스크립트로 남기는 편이 좋다.
스크립트가 실패하면 스크린샷, trace, network log를 함께 확보할 수 있다.

---

## 5. 데이터 상태 재현

특정 데이터에서만 실패하면 데이터 스냅샷이 필요하다.

```sql
SELECT id, status, total_amount, version, updated_at
FROM orders
WHERE id = 'order-123';

SELECT order_id, product_id, quantity, reserved_quantity
FROM order_items
WHERE order_id = 'order-123'
ORDER BY product_id;
```

```bash
pg_dump "$DATABASE_URL" \
    --data-only \
    --table=orders \
    --table=order_items \
    --where="id = 'order-123'" \
    > /tmp/order-123-reproduce.sql
```

운영 데이터는 개인정보와 민감정보를 마스킹해야 한다.
재현에 필요 없는 필드는 제거한다.

---

## 6. 간헐적 버그 재현

간헐적 버그는 성공/실패를 반복 측정한다.

```bash
#!/usr/bin/env bash
set -euo pipefail

success=0
failure=0

for i in $(seq 1 100); do
    if ./scripts/reproduce-order.sh >"/tmp/repro-$i.log" 2>&1; then
        success=$((success + 1))
    else
        failure=$((failure + 1))
        echo "failed at iteration=$i"
        tail -n 40 "/tmp/repro-$i.log"
    fi
done

echo "success=$success failure=$failure"
```

실패 확률이 1%라도 반복 실행으로 관찰할 수 있다.
동시성 이슈라면 병렬도, CPU 제한, 네트워크 지연을 조절한다.

---

## 7. 환경별 재현 매트릭스

| 환경 | 재현 여부 | 버전 | 데이터 | 비고 |
|------|-----------|------|--------|------|
| 로컬 | 실패 | current branch | fixture | 개발자 재현 |
| CI | 통과 | current branch | fixture | 병렬도 낮음 |
| 스테이징 | 실패 | `2026.05.09-1` | staging DB | Redis cluster |
| 운영 | 실패 | `2026.05.09-1` | real | 영향 3% |

환경 차이는 원인 후보를 좁히는 강한 신호다.
단, "운영에서만 발생"은 로컬 재현을 포기하는 이유가 아니다.
운영 조건을 로컬에 가져오는 작업이 필요하다.

---

## 8. 시간 의존 버그 재현

```python
from freezegun import freeze_time
from billing import calculate_next_charge_at

def test_month_end_charge_date():
    with freeze_time("2026-02-28 23:59:59"):
        result = calculate_next_charge_at("Asia/Seoul")
    assert result.isoformat() == "2026-03-31T00:00:00+09:00"
```

시간대, 월말, 윤년, DST, 만료 시간은 재현 스크립트에 고정해야 한다.
현재 시간을 직접 사용하는 코드는 테스트가 불안정해진다.

---

## 9. 재현 실패 시 할 일

- [ ] 사용자의 원본 요청/입력/브라우저/계정 상태를 다시 확인한다.
- [ ] 로그에서 실제 실패 요청의 trace id를 찾는다.
- [ ] 정상 요청과 실패 요청의 차이를 비교한다.
- [ ] 최근 배포, 설정 변경, 데이터 마이그레이션을 확인한다.
- [ ] 반복 횟수와 동시성을 늘린다.
- [ ] 실패 조건을 통계로 기록한다.

---

## 10. 재현 완료 기준

재현 단계는 다음 중 하나가 충족되면 완료된다.

- [ ] 로컬 또는 테스트 환경에서 같은 실패를 만들었다.
- [ ] 운영에서만 가능한 실패라면 안전한 읽기 전용 관찰로 실패 조건을 특정했다.
- [ ] 간헐적 실패라면 반복 실행으로 실패 확률을 측정했다.
- [ ] 재현 명령과 입력값이 문서화되었다.
- [ ] 다음 단계에서 수집할 로그와 상태가 명확해졌다.
