# 범위 축소

> Phase 3: NARROW. 모든 것이 원인일 수 있다는 말은 아직 아무것도 모른다는 뜻이다.

---

## 1. 범위 축소의 목적

범위 축소는 의심 범위를 계층별로 줄여 실제 원인을 찾을 수 있는 크기로 만드는 단계다.
로그와 재현 결과를 기준으로 "가능성 있음"과 "증거상 제외"를 분리한다.

기본 레이어는 다음 순서로 본다.

```
Client
  ↓
Network / Gateway
  ↓
Application
  ↓
Database / Cache
  ↓
External Dependency
  ↓
Configuration / Runtime
```

---

## 2. 범위 축소 원칙

- [ ] 정상 경로와 실패 경로를 비교한다.
- [ ] 레이어를 하나씩 제외한다.
- [ ] 제외 근거를 기록한다.
- [ ] 재현 가능한 입력을 유지한다.
- [ ] "최근 변경"은 힌트로만 쓰고 증거로 착각하지 않는다.

---

## 3. 레이어별 질문

| 레이어 | 확인 질문 | 제외 증거 |
|--------|-----------|-----------|
| 클라이언트 | 요청 payload가 올바른가? | 서버 로그에 정상 payload 도착 |
| 네트워크 | 요청이 서버까지 도달하는가? | gateway access log 존재 |
| 인증 | 사용자/권한 상태가 맞는가? | claims와 policy 통과 로그 |
| 애플리케이션 | 어느 함수에서 실패하는가? | 스택트레이스 프레임 |
| DB | 쿼리가 실행되는가? | query log, lock 상태 |
| 캐시 | stale/miss/hit 영향인가? | cache bypass 실험 |
| 외부 API | 다운스트림 실패인가? | mock 또는 provider log |
| 설정 | 환경변수 차이인가? | config dump 비교 |

---

## 4. 요청 경로 추적

```bash
TRACE_ID="scope-order-001"

curl -sS -D /tmp/headers.txt \
    -H "x-debug-trace-id: $TRACE_ID" \
    http://localhost:3000/api/orders/order-123 \
    -o /tmp/body.json

rg "$TRACE_ID" logs/ -n
cat /tmp/headers.txt
jq . /tmp/body.json
```

요청이 gateway에는 찍히지만 application log에는 없으면 라우팅, 인증, WAF, timeout을 의심한다.
application에는 찍히지만 DB query가 없으면 validation 또는 비즈니스 로직에서 멈춘 것이다.

---

## 5. 정상/실패 비교

```bash
diff -u \
    <(jq -S . /tmp/success-request.json) \
    <(jq -S . /tmp/failure-request.json)
```

비교 대상:

- [ ] headers
- [ ] auth claims
- [ ] request body
- [ ] account flags
- [ ] feature flags
- [ ] locale/timezone
- [ ] DB row version

작은 차이가 원인일 수 있다.
특히 날짜, nullable 필드, 권한 플래그, 실험군은 자주 놓친다.

---

## 6. 이진 탐색

코드 변경이 많다면 git 범위를 좁힌다.

```bash
git log --oneline --since="2026-05-01" -- api/orders src/inventory
git bisect start
git bisect bad HEAD
git bisect good v2026.04.30
git bisect run ./scripts/reproduce-order.sh
```

데이터나 설정도 이진 탐색할 수 있다.
feature flag를 절반씩 끄거나, payload 필드를 절반씩 제거해 실패 조건을 찾는다.

---

## 7. DB와 로직 분리

```typescript
async function debugCreateOrder(input: CreateOrderInput) {
    const validation = validateOrderInput(input);
    console.info({ event: 'debug.validation', validation });

    const inventory = await inventoryRepository.findByProductIds(
        input.items.map((item) => item.productId),
    );
    console.info({ event: 'debug.inventory.loaded', count: inventory.length });

    const result = calculateOrder(input, inventory);
    console.info({ event: 'debug.order.calculated', total: result.total });

    return orderRepository.save(result);
}
```

DB 조회 전 실패하면 validation/입력 문제다.
계산 후 저장에서 실패하면 constraint, transaction, connection, serialization 문제로 좁혀진다.

---

## 8. 캐시 영향 분리

```bash
curl -sS "$BASE_URL/api/products/p-1" \
    -H "cache-control: no-cache" \
    -H "x-debug-bypass-cache: true" | jq .
```

```python
def get_product(product_id: str, bypass_cache: bool = False):
    if not bypass_cache:
        cached = cache.get(f"product:{product_id}")
        if cached:
            return cached

    product = repository.get(product_id)
    cache.set(f"product:{product_id}", product, ttl=300)
    return product
```

cache bypass에서만 정상이라면 캐시 key, TTL, invalidation, serialization을 확인한다.
항상 실패하면 캐시는 제외한다.

---

## 9. 외부 의존성 분리

외부 API가 원인인지 확인할 때는 mock으로 격리한다.

```typescript
import nock from 'nock';

nock('https://payment.example.com')
    .post('/authorize')
    .reply(200, { status: 'approved', transactionId: 'debug-tx-1' });

const result = await paymentService.authorize({
    orderId: 'order-123',
    amount: 10000,
});

expect(result.status).toBe('approved');
```

mock에서는 정상이고 실제 provider에서 실패하면 network, credentials, provider validation을 본다.
mock에서도 실패하면 내부 요청 구성 또는 로직 문제다.

---

## 10. 범위 축소 보드

```markdown
| 후보 | 상태 | 근거 | 다음 행동 |
|------|------|------|-----------|
| 클라이언트 payload | 제외 | 서버 로그에 동일 payload 도착 | 없음 |
| Gateway timeout | 제외 | app log에서 요청 처리 시작 | 없음 |
| 재고 DB lock | 유력 | `pg_locks`에서 wait 확인 | lock 순서 실험 |
| Redis stale | 제외 | bypass cache에서도 실패 | 없음 |
| 결제 API | 제외 | 결제 호출 전 실패 | 없음 |
```

---

## 11. 범위 축소 완료 기준

- [ ] 제외한 후보와 근거가 있다.
- [ ] 남은 후보가 1~3개 수준으로 줄었다.
- [ ] 각 후보가 검증 가능한 가설로 바뀔 수 있다.
- [ ] 다음 실험에서 바꿀 조건이 명확하다.
- [ ] 무관한 리팩터나 대규모 수정 없이 진행 가능하다.
