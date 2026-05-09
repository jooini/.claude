# Query Optimization

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/query-optimization

---

## 1. EXPLAIN / EXPLAIN ANALYZE

```sql
-- 실행 계획 확인 (PostgreSQL)
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM orders
WHERE user_id = '123' AND status = 'completed'
ORDER BY created_at DESC
LIMIT 20;

-- 주요 용어
-- Seq Scan: 전체 테이블 스캔 (인덱스 없음)
-- Index Scan: 인덱스 사용 후 테이블 접근
-- Index Only Scan: 인덱스만으로 처리 (가장 빠름)
-- Hash Join: 해시 테이블로 조인 (대용량)
-- Nested Loop: 중첩 루프 조인 (소량)
-- cost: 예상 비용 (낮을수록 빠름)
-- rows: 예상 반환 행 수
-- actual time: 실제 실행 시간 (ms)
```

---

## 2. 인덱스 전략

```sql
-- 복합 인덱스 컬럼 순서
-- WHERE user_id = ? AND status = ? ORDER BY created_at
-- → (user_id, status, created_at) 순서가 최적

-- 선택도(Selectivity) 높은 컬럼 먼저
-- user_id (값 수백만) > status (값 5개)
-- → user_id를 앞에

-- 부분 인덱스: 자주 쿼리하는 조건만
CREATE INDEX idx_active_orders
ON orders (user_id, created_at)
WHERE status = 'active';  -- status = 'active'인 쿼리에서만 사용

-- 인덱스 사용 확인
SELECT
  indexname,
  idx_scan,       -- 사용 횟수
  idx_tup_read,   -- 읽은 행 수
  idx_tup_fetch   -- 실제 가져온 행 수
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY idx_scan DESC;
```

---

## 3. JOIN 최적화

```sql
-- 대규모 테이블 조인 순서: 작은 테이블이 드라이빙 테이블
-- 필터 먼저 적용 후 조인

-- ❌ 전체 조인 후 필터
SELECT *
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE u.country = 'KR' AND o.created_at >= '2024-01-01'

-- ✅ 서브쿼리로 필터 먼저
SELECT *
FROM (
  SELECT * FROM orders WHERE created_at >= '2024-01-01'
) o
JOIN (
  SELECT * FROM users WHERE country = 'KR'
) u ON u.id = o.user_id

-- 불필요한 JOIN 제거
-- 집계에 필요 없는 테이블은 JOIN 안 함
SELECT o.user_id, COUNT(*) AS order_count
FROM orders o
-- users 테이블 없어도 됨 (user_id만 필요)
GROUP BY o.user_id
```

---

## 4. 대용량 집계 최적화

```sql
-- 사전 집계 (Materialized View 또는 Summary Table)
-- 매일 자정 전일 데이터 집계
CREATE MATERIALIZED VIEW daily_user_stats AS
SELECT
  user_id,
  DATE(created_at) AS date,
  COUNT(*) AS orders,
  SUM(amount) AS revenue
FROM orders
GROUP BY 1, 2;

-- 주기적 갱신
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_user_stats;

-- 파티셔닝 (날짜별 분할)
CREATE TABLE orders (
  id UUID,
  created_at TIMESTAMPTZ,
  amount NUMERIC
) PARTITION BY RANGE (created_at);

CREATE TABLE orders_2024_01 PARTITION OF orders
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
-- 특정 날짜 범위 쿼리 시 해당 파티션만 스캔
```

---

## 5. 쿼리 리팩토링 패턴

```sql
-- DISTINCT 대신 EXISTS
-- ❌ 느림
SELECT DISTINCT u.id FROM users u
JOIN orders o ON o.user_id = u.id

-- ✅ 빠름
SELECT u.id FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)

-- COUNT DISTINCT 최적화 (근사치로 충분할 때)
-- HyperLogLog 사용 (PostgreSQL)
SELECT approx_count_distinct(user_id) FROM events  -- 빠름, 약 1~2% 오차

-- 대용량 LIKE 검색
-- ❌ 전체 스캔
WHERE name LIKE '%검색어%'
-- ✅ 전문 검색 인덱스
CREATE INDEX idx_products_name ON products USING GIN(to_tsvector('simple', name));
WHERE to_tsvector('simple', name) @@ to_tsquery('simple', '검색어')
```

---

## 6. 통계 정보 관리

```sql
-- 테이블 통계 업데이트 (쿼리 플래너 정확도 향상)
ANALYZE orders;
VACUUM ANALYZE orders;  -- 불필요 행 제거 + 통계 갱신

-- 통계 확인
SELECT
  tablename,
  n_live_tup,     -- 현재 행 수
  n_dead_tup,     -- 삭제됐지만 공간 미반환 행 수
  last_analyze,
  last_vacuum
FROM pg_stat_user_tables
WHERE tablename = 'orders';
```

---

## 7. 안티패턴

- **EXPLAIN 없는 최적화**: 실제 병목 확인 없이 추측으로 변경
- **모든 컬럼 인덱스**: 쓰기 성능 저하, 인덱스 유지 비용
- **GROUP BY 전 미필터링**: WHERE로 먼저 줄이고 집계
- **함수로 감싼 인덱스 컬럼**: `YEAR(created_at)` → 인덱스 미사용
- **OFFSET이 큰 페이지네이션**: `OFFSET 100000` → 커서 기반으로
