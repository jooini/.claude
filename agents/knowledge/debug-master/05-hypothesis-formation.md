# 가설 수립

> Phase 4: HYPOTHESIZE. 좋은 가설은 맞을 수도 있고 틀릴 수도 있지만, 반드시 검증 가능해야 한다.

---

## 1. 가설의 역할

가설은 관찰된 증거를 하나의 원인 설명으로 연결하는 문장이다.
"캐시 문제"는 가설이 아니다. "상품 가격 캐시가 주문 생성 후 invalidation되지 않아 이전 가격으로 결제 금액이 계산된다"는 가설이다.

좋은 가설의 조건:

- [ ] 원인과 결과가 연결되어 있다.
- [ ] 어떤 조건에서 실패하는지 설명한다.
- [ ] 반례를 만들 수 있다.
- [ ] 검증 방법이 명확하다.
- [ ] 수정 방향을 암시한다.

---

## 2. 가설 문장 템플릿

```text
관찰된 증상은 [조건]에서 [원인] 때문에 발생한다.
왜냐하면 [증거 A]와 [증거 B]가 있고,
[검증 방법]을 수행하면 [예상 결과]가 나와야 하기 때문이다.
```

예시:

```text
쿠폰 적용 후 결제 버튼 비활성화는 할인 금액이 0원일 때 프론트 상태 머신이 `invalid`로 전이하기 때문에 발생한다.
왜냐하면 실패 요청의 couponDiscount가 0이고, 버튼 disabled reason 로그가 `INVALID_TOTAL`이며,
0원 쿠폰 fixture로 상태 머신 테스트를 실행하면 같은 상태가 나와야 하기 때문이다.
```

---

## 3. 가설 유형

| 유형 | 설명 | 대표 증거 |
|------|------|-----------|
| 타이밍 | 순서, 지연, 경쟁 조건 | 간헐적 실패, lock wait |
| 상태 | 객체/세션/캐시 상태 불일치 | 특정 계정만 실패 |
| 리소스 | CPU, 메모리, connection 부족 | 부하 시 증가 |
| 데이터 패턴 | 특정 입력/레코드에서 실패 | nullable, boundary |
| 설정 | env, flag, dependency version 차이 | 환경별 차이 |
| 외부 의존성 | provider 응답 또는 계약 차이 | 4xx/5xx, timeout |

---

## 4. 타이밍 가설

```text
동시 주문 요청에서 재고가 음수가 되는 이유는 재고 조회와 차감이 같은 transaction lock 안에서 수행되지 않기 때문이다.
두 요청이 같은 `stock=1`을 읽고 각각 차감하면 둘 다 성공할 수 있다.
```

검증 실험:

```bash
seq 1 20 | xargs -I{} -P 20 curl -sS -X POST "$BASE_URL/api/orders" \
    -H "content-type: application/json" \
    -d '{"userId":"race-user","productId":"p-1","quantity":1}' \
    > /tmp/race-results.jsonl

rg '"status":"success"' /tmp/race-results.jsonl | wc -l
```

예상 결과:

- 버그가 있으면 성공 수가 재고보다 많다.
- lock 또는 atomic update 적용 후 성공 수가 재고 이하로 제한된다.

---

## 5. 상태 가설

```typescript
type CheckoutState = {
    userId: string;
    cartVersion: number;
    couponCode?: string;
    totalAmount: number;
};

function assertCheckoutState(state: CheckoutState) {
    if (state.totalAmount < 0) {
        throw new Error(`invalid totalAmount userId=${state.userId} version=${state.cartVersion}`);
    }
}
```

상태 가설은 "어떤 상태 조합에서만 실패하는가"를 설명해야 한다.
예를 들어 신규 사용자, 휴면 복구 사용자, 쿠폰 사용 이력 있는 사용자처럼 상태 축을 나눈다.

---

## 6. 리소스 가설

```bash
while true; do
    date -Is
    ps -o pid,pcpu,pmem,rss,command -p "$PID"
    lsof -p "$PID" | wc -l
    sleep 5
done
```

리소스 가설 예:

- DB connection pool이 고갈되어 요청이 timeout된다.
- 파일 디스크립터 누수로 일정 시간 후 외부 API 호출이 실패한다.
- heap 증가로 GC pause가 길어져 health check가 실패한다.

---

## 7. 데이터 패턴 가설

```python
def classify_order(row):
    return {
        "has_coupon": row["coupon_code"] is not None,
        "is_zero_amount": row["total_amount"] == 0,
        "has_legacy_user": row["user_source"] == "legacy",
        "item_count": row["item_count"],
    }

failed = [classify_order(row) for row in failed_orders]
success = [classify_order(row) for row in success_orders]

print("failed", failed[:10])
print("success", success[:10])
```

특정 패턴이 실패 집합에만 나타나면 강한 가설 후보가 된다.
단, 상관관계가 원인은 아니다. 검증 실험으로 이어져야 한다.

---

## 8. 설정 가설

```bash
comm -3 \
    <(sort /tmp/local-env.txt) \
    <(sort /tmp/staging-env.txt)
```

설정 가설 예:

- 스테이징만 `FEATURE_STRICT_TOKEN=true`라 legacy token이 거부된다.
- 운영만 Node.js minor version이 달라 URL parsing 결과가 다르다.
- `TZ` 값 차이로 날짜 계산이 하루 밀린다.

---

## 9. 가설 우선순위

| 점수 | 기준 |
|------|------|
| +3 | 직접 증거가 있다 |
| +2 | 재현 조건을 설명한다 |
| +2 | 최근 변경과 연결된다 |
| +1 | 검증 비용이 낮다 |
| -2 | 반례가 있다 |
| -3 | 검증 방법이 없다 |

높은 점수부터 검증하되, 검증 비용이 낮은 가설을 먼저 처리할 수 있다.
중요한 것은 순서보다 기록이다.

---

## 10. 나쁜 가설

- 캐시가 이상한 것 같다.
- DB 문제일 수 있다.
- 프론트 버그 같다.
- 배포가 꼬인 것 같다.
- 네트워크가 불안정하다.

위 문장은 범위가 넓고 검증 기준이 없다.
반드시 조건, 원인, 예상 결과를 포함해 다시 쓴다.

---

## 11. 가설 완료 기준

- [ ] 가설이 한 문장으로 명확하다.
- [ ] 증거가 최소 2개 이상 연결되어 있다.
- [ ] 반증 가능한 실험이 있다.
- [ ] 실험의 예상 결과가 적혀 있다.
- [ ] 틀렸을 때 다음 후보로 넘어갈 수 있다.
