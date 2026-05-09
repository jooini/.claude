# 데이터베이스 디버깅

> DB 디버깅은 쿼리 하나가 아니라 트랜잭션, lock, index, 데이터 분포를 함께 보는 작업이다.

---

## 1. 대표 증상

DB 문제는 애플리케이션에서 timeout, 500, deadlock, connection pool exhausted로 보인다.
애플리케이션 로그만 보면 원인을 놓치기 쉽다.

신호:

- [ ] slow query 증가
- [ ] lock wait 증가
- [ ] deadlock detected
- [ ] connection pool timeout
- [ ] CPU 또는 IO 급증
- [ ] 특정 테이블 접근 시 지연
- [ ] migration 이후 에러 증가

---

## 2. 현재 활동 확인

```sql
SELECT pid,
       usename,
       application_name,
       state,
       wait_event_type,
       wait_event,
       now() - query_start AS running_for,
       query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start;
```

`wait_event_type`이 `Lock`, `IO`, `Client`, `LWLock` 중 무엇인지 확인한다.
대기 종류에 따라 원인이 완전히 다르다.

---

## 3. slow query

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders
WHERE user_id = 'user-42'
ORDER BY created_at DESC
LIMIT 50;
```

실행 계획에서 볼 것:

- [ ] Seq Scan이 큰 테이블에서 발생하는가?
- [ ] rows estimate가 실제와 크게 다른가?
- [ ] Sort가 느린가?
- [ ] Buffers read가 많은가?
- [ ] index condition이 사용되는가?

---

## 4. 인덱스 확인

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'orders'
ORDER BY indexname;
```

쿼리가 `WHERE user_id = ? ORDER BY created_at DESC LIMIT ?`라면 복합 인덱스를 검토한다.

```sql
CREATE INDEX CONCURRENTLY idx_orders_user_created_at
ON orders (user_id, created_at DESC);
```

운영에서는 `CONCURRENTLY` 여부, lock 영향, 디스크 사용량을 확인한다.

---

## 5. Lock 확인

```sql
SELECT blocked.pid AS blocked_pid,
       blocking.pid AS blocking_pid,
       blocked.query AS blocked_query,
       blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_locks blocked_locks ON blocked_locks.pid = blocked.pid
JOIN pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
 AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
 AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
 AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
 AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
JOIN pg_stat_activity blocking ON blocking.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted
  AND blocking_locks.granted;
```

blocking query가 오래 열린 transaction이면 애플리케이션의 transaction boundary를 확인한다.

---

## 6. Deadlock 분석

Deadlock은 두 트랜잭션이 서로 상대 lock을 기다리는 상태다.
해결은 보통 lock 획득 순서 통일, transaction 축소, index 개선이다.

```text
Transaction A: lock order(id=1) → lock inventory(id=1)
Transaction B: lock inventory(id=1) → lock order(id=1)
```

수정 방향:

- [ ] 모든 코드 경로에서 같은 순서로 row를 잠근다.
- [ ] transaction 안에서 외부 API를 호출하지 않는다.
- [ ] 필요한 row만 잠근다.
- [ ] retry는 idempotency 보장 후 적용한다.

---

## 7. 트랜잭션 격리

| 격리 수준 | 특징 | 주의 |
|-----------|------|------|
| READ COMMITTED | 각 statement마다 최신 committed | non-repeatable read |
| REPEATABLE READ | transaction 내 snapshot 유지 | serialization 실패 가능 |
| SERIALIZABLE | 직렬 실행처럼 보장 | retry 필요 |

격리 수준을 올리는 것은 비용이 있다.
먼저 쿼리와 lock 범위를 정확히 확인한다.

---

## 8. connection pool

```typescript
const dataSource = new DataSource({
    type: 'postgres',
    extra: {
        max: 20,
        idleTimeoutMillis: 30_000,
        connectionTimeoutMillis: 2_000,
    },
});
```

pool timeout이 나면 DB max connection만 늘리지 않는다.
긴 transaction, connection leak, slow query가 pool을 점유하는지 확인한다.

```sql
SELECT application_name, state, COUNT(*)
FROM pg_stat_activity
GROUP BY application_name, state
ORDER BY COUNT(*) DESC;
```

---

## 9. 마이그레이션 디버깅

```bash
psql "$DATABASE_URL" -c '\d+ orders'
psql "$DATABASE_URL" -c 'SELECT COUNT(*) FROM schema_migrations;'
```

확인할 것:

- [ ] migration이 모든 환경에 적용되었는가?
- [ ] nullable 변경이 기존 데이터와 충돌하는가?
- [ ] default 값이 기대와 같은가?
- [ ] long-running migration이 lock을 잡는가?
- [ ] rollback migration이 있는가?

---

## 10. 데이터 패턴 확인

```sql
SELECT status, COUNT(*)
FROM orders
GROUP BY status
ORDER BY COUNT(*) DESC;

SELECT COUNT(*)
FROM orders
WHERE paid_at IS NULL
  AND status = 'PAID';
```

잘못된 데이터 상태는 코드 버그의 결과이거나 원인일 수 있다.
코드 수정과 데이터 보정은 별도로 계획한다.

---

## 11. DB 디버깅 체크리스트

- [ ] slow query와 lock wait를 구분했다.
- [ ] 실행 계획을 실제 파라미터로 확인했다.
- [ ] index 존재와 사용 여부를 확인했다.
- [ ] transaction 범위와 외부 호출을 점검했다.
- [ ] connection pool 상태를 봤다.
- [ ] 데이터 분포와 이상 row를 확인했다.

---

## 12. 완료 기준

- [ ] DB 증상이 애플리케이션 증상과 시간상 연결된다.
- [ ] 원인 쿼리 또는 transaction을 특정했다.
- [ ] 수정 전후 실행 계획/latency를 비교했다.
- [ ] lock/deadlock 재현이 사라졌다.
- [ ] migration 또는 index 변경의 운영 영향이 검토되었다.
