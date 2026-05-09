# 경쟁 조건 디버깅

> 경쟁 조건은 순서가 바뀔 때 드러난다. 단일 실행으로는 보이지 않는 버그다.

---

## 1. 경쟁 조건의 신호

동시성 버그는 재현이 어렵고 로그가 모순처럼 보인다.
한 요청만 보면 정상인데 여러 요청이 겹칠 때 데이터가 깨진다.

대표 신호:

- [ ] 간헐적 실패
- [ ] 재시도하면 성공
- [ ] 부하가 높을 때만 발생
- [ ] 재고, 잔액, 카운터가 음수 또는 중복
- [ ] deadlock, lock timeout
- [ ] 이벤트 순서 역전

---

## 2. 기본 분류

| 유형 | 설명 | 예시 |
|------|------|------|
| read-modify-write | 읽고 계산하고 쓰는 사이 끼어듦 | 재고 oversell |
| check-then-act | 확인 후 실행 사이 상태 변경 | 중복 가입 |
| lost update | 마지막 write가 이전 write 덮음 | 프로필 수정 |
| deadlock | 서로 다른 lock 순서 | 주문/재고 |
| async ordering | 이벤트 도착 순서 역전 | 배송 전 결제 취소 |
| shared mutable state | 공유 객체 동시 변경 | in-memory cache |

---

## 3. 재현 부하 만들기

```bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"

seq 1 50 | xargs -I{} -P 25 curl -sS -X POST "$BASE_URL/api/reservations" \
    -H "content-type: application/json" \
    -H "x-debug-run: race-001" \
    -d '{"productId":"p-1","quantity":1,"userId":"user-{}"}' \
    > /tmp/race-results.jsonl

jq -r '.status' /tmp/race-results.jsonl | sort | uniq -c
```

동시성을 높여 실패 확률을 올린다.
단, 운영 시스템에 직접 부하를 주면 안 된다.

---

## 4. TypeScript read-modify-write 문제

문제 코드:

```typescript
async function withdraw(accountId: string, amount: number) {
    const account = await accountRepository.findById(accountId);
    if (account.balance < amount) {
        throw new Error('insufficient balance');
    }
    account.balance -= amount;
    await accountRepository.save(account);
}
```

검증 테스트:

```typescript
it('동시 출금이 잔액을 초과해 성공하지 않는다', async () => {
    await accountRepository.save({ id: 'a-1', balance: 100 });

    const results = await Promise.allSettled([
        withdraw('a-1', 100),
        withdraw('a-1', 100),
    ]);

    const fulfilled = results.filter((result) => result.status === 'fulfilled');
    expect(fulfilled).toHaveLength(1);
});
```

---

## 5. Atomic update 수정

```typescript
async function withdraw(accountId: string, amount: number) {
    const rows = await dataSource.query(
        `
        UPDATE accounts
        SET balance = balance - $2
        WHERE id = $1
          AND balance >= $2
        RETURNING id, balance
        `,
        [accountId, amount],
    );

    if (rows.length === 0) {
        throw new Error('insufficient balance');
    }
}
```

조건부 update는 check와 act를 DB 내부의 한 연산으로 묶는다.

---

## 6. Python lock 검증

```python
import threading

counter = 0
lock = threading.Lock()

def increment_safe():
    global counter
    with lock:
        current = counter
        counter = current + 1

threads = [threading.Thread(target=increment_safe) for _ in range(1000)]
for thread in threads:
    thread.start()
for thread in threads:
    thread.join()

assert counter == 1000
```

프로세스가 여러 개라면 in-process lock은 충분하지 않다.
DB lock, Redis lock, queue serialization 같은 프로세스 간 제어가 필요하다.

---

## 7. Deadlock 분석

```sql
SELECT blocked_locks.pid AS blocked_pid,
       blocking_locks.pid AS blocking_pid,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
  ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
 AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
 AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
 AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
 AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
JOIN pg_catalog.pg_stat_activity blocking_activity
  ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted
  AND blocking_locks.granted;
```

deadlock은 lock을 잡는 순서를 통일하는 방식으로 해결하는 경우가 많다.

---

## 8. 이벤트 순서 역전

```text
Expected:
payment.authorized → order.confirmed → shipment.created

Observed:
shipment.created → payment.authorized → order.confirmed
```

확인할 것:

- [ ] 이벤트에 version 또는 sequence가 있는가?
- [ ] consumer가 오래된 이벤트를 무시하는가?
- [ ] retry가 순서를 바꾸는가?
- [ ] queue partition key가 일관적인가?

---

## 9. 비동기 코드 계측

```typescript
async function publishEvent(event: DomainEvent) {
    console.info({
        event: 'event.publish.start',
        aggregateId: event.aggregateId,
        eventType: event.type,
        version: event.version,
    });

    await producer.send({
        topic: 'orders',
        messages: [{ key: event.aggregateId, value: JSON.stringify(event) }],
    });
}
```

partition key가 aggregate id가 아니면 같은 주문의 이벤트 순서가 깨질 수 있다.

---

## 10. 디버깅 체크리스트

- [ ] 단일 실행과 병렬 실행 결과가 다른가?
- [ ] 공유 상태가 있는가?
- [ ] DB update가 조건부/원자적인가?
- [ ] lock 획득 순서가 일관적인가?
- [ ] retry가 중복 실행을 만들지 않는가?
- [ ] idempotency key가 있는가?
- [ ] 이벤트 순서를 보장하는 key가 있는가?

---

## 11. 완료 기준

- [ ] 병렬 재현 스크립트가 있다.
- [ ] 실패 확률을 측정했다.
- [ ] race window를 설명할 수 있다.
- [ ] 수정 후 같은 부하에서 실패하지 않는다.
- [ ] 회귀 테스트가 동시 실행을 포함한다.
