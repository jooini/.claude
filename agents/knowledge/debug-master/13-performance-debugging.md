# 성능 디버깅

> 성능 문제는 느린 느낌이 아니라 시간 예산을 초과한 구간을 찾는 작업이다.

---

## 1. 성능 디버깅 목표

성능 디버깅은 전체 latency를 구성 요소별로 나누고, 가장 큰 병목을 증거로 찾는 과정이다.
최적화는 측정 후에 한다.

먼저 정할 것:

- [ ] 목표 지표: p50, p95, p99, throughput
- [ ] 영향 범위: 특정 API, 전체 서비스, 특정 사용자
- [ ] 기준선: 정상 시점 latency
- [ ] 재현 부하: 요청 수, 동시성, 데이터 크기
- [ ] 허용 예산: 예를 들어 p95 300ms 이하

---

## 2. latency 분해

```
Total 1200ms
├── Gateway: 20ms
├── Auth: 35ms
├── App validation: 5ms
├── DB query: 870ms
├── External API: 210ms
└── Serialization: 60ms
```

분해 없이 "API가 느리다"고 말하면 수정 방향이 없다.
각 구간의 시간을 로그나 tracing으로 남긴다.

---

## 3. 코드 구간 측정

```typescript
import { performance } from 'perf_hooks';

async function measure<T>(name: string, fn: () => Promise<T>): Promise<T> {
    const started = performance.now();
    try {
        return await fn();
    } finally {
        console.info({
            event: 'performance.measure',
            name,
            durationMs: Math.round((performance.now() - started) * 100) / 100,
        });
    }
}

const user = await measure('load-user', () => userRepository.findById(userId));
const orders = await measure('load-orders', () => orderRepository.findRecent(userId));
```

측정 코드는 임시라도 정확해야 한다.
비동기 함수는 반드시 `await`를 포함해 측정한다.

---

## 4. Python 프로파일링

```python
import cProfile
import pstats

def run_profile():
    profiler = cProfile.Profile()
    profiler.enable()
    run_expensive_job()
    profiler.disable()

    stats = pstats.Stats(profiler).sort_stats("cumtime")
    stats.print_stats(30)

if __name__ == "__main__":
    run_profile()
```

`cumtime`은 하위 호출을 포함한 시간이다.
병목 함수의 호출 횟수와 누적 시간을 함께 본다.

---

## 5. 부하 재현

```bash
wrk -t4 -c64 -d60s \
    -H "authorization: Bearer $TOKEN" \
    "http://localhost:3000/api/orders/recent"
```

wrk가 없다면 간단히 병렬 curl로도 기준선을 잡을 수 있다.

```bash
seq 1 200 | xargs -I{} -P 20 curl -sS -o /dev/null -w "%{time_total}\n" \
    "http://localhost:3000/api/orders/recent" \
    > /tmp/latency.txt

sort -n /tmp/latency.txt | tail -20
```

---

## 6. N+1 쿼리

문제 코드:

```typescript
const orders = await orderRepository.findByUserId(userId);
for (const order of orders) {
    order.items = await itemRepository.findByOrderId(order.id);
}
```

확인:

```bash
rg "SELECT .*order_items" logs/query.log | wc -l
```

수정 방향:

```typescript
const orders = await orderRepository.findByUserId(userId);
const orderIds = orders.map((order) => order.id);
const items = await itemRepository.findByOrderIds(orderIds);
```

N+1은 데이터가 적을 때 안 보이고, 운영 데이터에서 갑자기 드러난다.

---

## 7. DB 실행 계획

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders
WHERE user_id = 'user-42'
ORDER BY created_at DESC
LIMIT 20;
```

확인할 항목:

- [ ] sequential scan 여부
- [ ] estimated rows와 actual rows 차이
- [ ] sort가 메모리 밖으로 나갔는가?
- [ ] shared hit/read 비율
- [ ] index condition이 사용되는가?

---

## 8. CPU 병목

```bash
node --cpu-prof dist/main.js
```

```bash
py-spy top --pid "$PID"
py-spy record --pid "$PID" --output /tmp/profile.svg --duration 30
```

CPU 병목은 slow query와 다르다.
DB 시간이 낮고 애플리케이션 CPU가 높으면 serialization, compression, regex, 암호화, 큰 loop를 의심한다.

---

## 9. 외부 API 병목

```typescript
const started = Date.now();
const response = await fetch(providerUrl, { method: 'POST', body });
logger.info({
    event: 'provider.request.done',
    provider: 'payment',
    status: response.status,
    durationMs: Date.now() - started,
});
```

외부 API가 느리면 timeout, retry, circuit breaker, bulkhead를 본다.
retry가 latency와 부하를 동시에 키울 수 있다.

---

## 10. 성능 수정 원칙

- [ ] 가장 큰 병목부터 수정한다.
- [ ] 수정 전후 같은 부하로 비교한다.
- [ ] 평균보다 p95/p99를 본다.
- [ ] 캐시는 원인 분석 후 마지막에 고려한다.
- [ ] 인덱스 추가는 write 비용도 확인한다.
- [ ] 병렬화는 외부 의존성과 DB pool 한계를 확인한다.

---

## 11. 결과 기록

```markdown
| 항목 | 수정 전 | 수정 후 |
|------|---------|---------|
| p50 | 180ms | 90ms |
| p95 | 1200ms | 240ms |
| p99 | 2500ms | 420ms |
| DB query count | 101 | 2 |
| CPU max | 78% | 42% |
```

성능 개선은 숫자로만 완료된다.

---

## 12. 완료 기준

- [ ] 기준선과 목표가 있다.
- [ ] 병목 구간을 측정으로 찾았다.
- [ ] 수정 전후를 같은 조건에서 비교했다.
- [ ] p95/p99가 목표에 들어왔다.
- [ ] 성능 회귀를 잡을 테스트나 모니터링이 있다.
