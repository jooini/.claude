# 가설 검증

> Phase 5: VERIFY. 검증은 가설을 믿기 위한 절차가 아니라, 틀렸을 때 빨리 버리기 위한 절차다.

---

## 1. 검증의 목적

가설 검증은 원인 후보를 실험으로 지지하거나 반박하는 단계다.
검증 없이 수정하면 운이 좋을 때만 문제가 사라지고, 운이 나쁠 때는 원인과 무관한 변경이 쌓인다.

검증 전 확인할 것:

- [ ] 어떤 가설을 검증하는가?
- [ ] 바꿀 조건은 하나인가?
- [ ] 예상 결과가 무엇인가?
- [ ] 실험이 안전한가?
- [ ] 실패해도 원상복구 가능한가?

---

## 2. 검증 실험 유형

| 실험 | 목적 | 예시 |
|------|------|------|
| 로깅 추가 | 내부 상태 관찰 | 계산 전후 값 출력 |
| 조건 변경 | 원인 조건 제거 | feature flag off |
| 격리 테스트 | 외부 의존성 제거 | API mock |
| 반복 실행 | 확률 측정 | 100회 stress |
| 프로파일링 | 리소스 병목 확인 | CPU flamegraph |
| 데이터 비교 | 실패 패턴 확인 | 성공/실패 row diff |

---

## 3. 안전한 로깅 검증

```typescript
function debugLogPriceCalculation(input: PriceInput, result: PriceResult) {
    console.info(JSON.stringify({
        event: 'debug.price.calculated',
        traceId: input.traceId,
        userId: input.userId,
        itemCount: input.items.length,
        couponCode: input.couponCode,
        subtotal: result.subtotal,
        discount: result.discount,
        total: result.total,
    }));
}
```

운영 로그 검증 시 주의:

- [ ] 개인정보를 남기지 않는다.
- [ ] 로그량을 특정 trace/user로 제한한다.
- [ ] 종료 조건과 제거 계획이 있다.
- [ ] 로그 레벨을 복구한다.

---

## 4. 조건 변경 검증

feature flag로 원인 조건을 제거한다.

```bash
curl -sS -X PATCH "$ADMIN_URL/flags/new-price-engine" \
    -H "authorization: Bearer $ADMIN_TOKEN" \
    -H "content-type: application/json" \
    -d '{"enabled": false, "reason": "debug verification", "ttlMinutes": 10}'
```

판정:

- flag off 후 실패가 사라지면 새 가격 엔진이 원인 범위에 들어온다.
- flag off 후도 실패하면 새 가격 엔진은 제외한다.
- 트래픽이나 데이터가 달라지지 않았는지 같이 확인한다.

---

## 5. 격리 테스트

```python
from unittest.mock import Mock

def test_order_creation_without_payment_provider():
    payment = Mock()
    payment.authorize.return_value = {"status": "approved", "transaction_id": "debug"}

    service = OrderService(payment_provider=payment, repository=FakeOrderRepository())
    result = service.create_order(user_id="u-1", product_id="p-1", quantity=1)

    assert result.status == "created"
    payment.authorize.assert_called_once()
```

mock에서 통과하고 실제 provider에서 실패하면 외부 계약, credentials, network를 본다.
mock에서도 실패하면 내부 로직을 본다.

---

## 6. 반복 검증

간헐적 버그는 단일 실행으로 판정하지 않는다.

```bash
run_repro() {
    ./scripts/reproduce-checkout.sh >/tmp/checkout.out 2>/tmp/checkout.err
}

success=0
failure=0

for i in $(seq 1 200); do
    if run_repro; then
        success=$((success + 1))
    else
        failure=$((failure + 1))
    fi
done

printf 'success=%s failure=%s failure_rate=%s%%\n' \
    "$success" "$failure" "$((failure * 100 / (success + failure)))"
```

검증 전 실패율과 검증 후 실패율을 모두 기록한다.
0/1회 실패는 판단 근거가 약하다.

---

## 7. 데이터 검증

```sql
SELECT coupon_code, COUNT(*) AS failure_count
FROM order_failures
WHERE created_at >= now() - interval '1 hour'
GROUP BY coupon_code
ORDER BY failure_count DESC;
```

```bash
psql "$DATABASE_URL" -f queries/failure-pattern.sql \
    -v since="'2026-05-09 10:00:00+09'" \
    -o /tmp/failure-pattern.txt
```

데이터 검증은 sample bias를 조심해야 한다.
성공 케이스도 함께 비교해야 특정 패턴이 원인 후보인지 알 수 있다.

---

## 8. 리소스 검증

```bash
pid="$(pgrep -f 'node dist/main.js' | head -1)"

for i in $(seq 1 60); do
    printf '%s ' "$(date -Is)"
    ps -o pid,pcpu,pmem,rss,vsz -p "$pid" | tail -1
    sleep 5
done
```

리소스 가설은 시간 그래프가 중요하다.
요청 수, CPU, RSS, GC pause, connection count를 같은 시간축에서 비교한다.

---

## 9. 반증 우선 사고

좋은 실험은 가설이 틀렸을 때 빠르게 드러난다.

| 가설 | 반증 조건 |
|------|-----------|
| 캐시 stale | cache bypass에서도 실패 |
| DB lock | lock wait가 없고 쿼리가 즉시 완료 |
| 외부 API timeout | mock에서도 동일 실패 |
| 환경변수 차이 | 동일 env dump에서도 실패 차이 유지 |
| race condition | 단일 스레드 반복에서만 실패 |

반증되면 코드를 억지로 설명하지 말고 가설을 폐기한다.

---

## 10. 검증 로그 템플릿

```markdown
## Verification
- hypothesis: 재고 차감 race condition
- experiment: 20 parallel requests against stock=1
- before: success=3 failure=17
- change: SELECT FOR UPDATE 적용 branch
- after: success=1 failure=19
- conclusion: hypothesis supported
- remaining risk: distributed inventory worker path not covered
```

---

## 11. 검증 완료 기준

- [ ] 실험 전 예상 결과를 기록했다.
- [ ] 실험에서 바꾼 조건이 하나다.
- [ ] 결과가 가설을 지지하거나 반박한다.
- [ ] 재현 케이스로 반복 확인했다.
- [ ] 다음 단계가 수정인지, 새 가설인지 명확하다.
