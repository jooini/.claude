# Advanced SQL

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/advanced-sql

---

## 1. 서브쿼리 패턴

```sql
-- 인라인 뷰 (FROM 절 서브쿼리)
SELECT dept, avg_salary
FROM (
  SELECT department AS dept, AVG(salary) AS avg_salary
  FROM employees
  GROUP BY department
) dept_stats
WHERE avg_salary > 5000000

-- 스칼라 서브쿼리 (SELECT 절)
SELECT
  o.id,
  o.total,
  (SELECT AVG(total) FROM orders WHERE user_id = o.user_id) AS user_avg_order
FROM orders o

-- EXISTS vs IN
-- EXISTS: 존재 여부만 확인, 대용량에서 빠름
SELECT * FROM users u
WHERE EXISTS (
  SELECT 1 FROM orders o WHERE o.user_id = u.id AND o.status = 'completed'
)

-- IN: 목록이 작을 때 사용
SELECT * FROM products
WHERE category_id IN (1, 2, 3)
```

---

## 2. CTE (Common Table Expressions)

```sql
-- 기본 CTE — 복잡한 쿼리를 단계적으로
WITH monthly_revenue AS (
  SELECT
    DATE_TRUNC('month', created_at) AS month,
    SUM(amount) AS revenue
  FROM orders
  WHERE status = 'completed'
  GROUP BY 1
),
revenue_growth AS (
  SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) AS prev_revenue,
    revenue - LAG(revenue) OVER (ORDER BY month) AS growth
  FROM monthly_revenue
)
SELECT
  month,
  revenue,
  ROUND(growth / prev_revenue * 100, 1) AS growth_rate_pct
FROM revenue_growth
WHERE prev_revenue IS NOT NULL
ORDER BY month

-- Recursive CTE — 계층 구조 탐색
WITH RECURSIVE category_path AS (
  -- 기반: 최상위 카테고리
  SELECT id, name, parent_id, name::TEXT AS path, 0 AS depth
  FROM categories
  WHERE parent_id IS NULL

  UNION ALL

  -- 재귀: 하위 카테고리
  SELECT c.id, c.name, c.parent_id,
         cp.path || ' > ' || c.name,
         cp.depth + 1
  FROM categories c
  JOIN category_path cp ON cp.id = c.parent_id
)
SELECT * FROM category_path ORDER BY path
```

---

## 3. CASE 표현식

```sql
-- 기본 CASE
SELECT
  user_id,
  total_purchases,
  CASE
    WHEN total_purchases >= 1000000 THEN 'VIP'
    WHEN total_purchases >= 500000  THEN 'Gold'
    WHEN total_purchases >= 100000  THEN 'Silver'
    ELSE 'Bronze'
  END AS grade

-- CASE를 이용한 피벗
SELECT
  user_id,
  SUM(CASE WHEN channel = 'organic' THEN revenue ELSE 0 END) AS organic_revenue,
  SUM(CASE WHEN channel = 'paid'    THEN revenue ELSE 0 END) AS paid_revenue,
  SUM(CASE WHEN channel = 'email'   THEN revenue ELSE 0 END) AS email_revenue
FROM conversions
GROUP BY user_id
```

---

## 4. 집합 연산

```sql
-- UNION: 중복 제거 (느림)
-- UNION ALL: 중복 포함 (빠름, 중복 없다면 항상 ALL)
SELECT user_id, 'buyer' AS type FROM orders
UNION ALL
SELECT user_id, 'seller' AS type FROM listings

-- INTERSECT: 교집합 — 두 쿼리 모두에 있는 것
SELECT user_id FROM buyers
INTERSECT
SELECT user_id FROM sellers  -- 구매도 하고 판매도 하는 유저

-- EXCEPT: 차집합 — 첫 번째에만 있는 것
SELECT user_id FROM registered_users
EXCEPT
SELECT user_id FROM purchasers  -- 가입했지만 구매 안 한 유저
```

---

## 5. 고급 집계

```sql
-- GROUPING SETS: 여러 GROUP BY 결합
SELECT
  channel,
  device,
  COUNT(*) AS sessions
FROM web_sessions
GROUP BY GROUPING SETS (
  (channel, device),  -- 채널 + 기기 조합
  (channel),          -- 채널별
  (device),           -- 기기별
  ()                  -- 전체 합계
)

-- ROLLUP: 계층적 소계
SELECT
  year,
  quarter,
  SUM(revenue) AS revenue
FROM sales
GROUP BY ROLLUP (year, quarter)
-- year + quarter / year 합계 / 전체 합계 순서로

-- FILTER (PostgreSQL)
SELECT
  COUNT(*) FILTER (WHERE status = 'active') AS active_count,
  COUNT(*) FILTER (WHERE status = 'churned') AS churned_count,
  AVG(revenue) FILTER (WHERE plan = 'premium') AS premium_avg_revenue
FROM users
```

---

## 6. 성능 최적화 SQL

```sql
-- 인덱스를 타는 쿼리 작성
-- ❌ 함수 감싸면 인덱스 미사용
WHERE DATE(created_at) = '2024-03-01'

-- ✅ 범위로 표현
WHERE created_at >= '2024-03-01' AND created_at < '2024-03-02'

-- ❌ OR 조건 — 인덱스 활용 제한
WHERE status = 'active' OR email LIKE '%@example.com'

-- ✅ UNION ALL로 분리
SELECT * FROM users WHERE status = 'active'
UNION ALL
SELECT * FROM users WHERE email LIKE '%@example.com' AND status != 'active'

-- 대용량 집계: 인덱스 온리 스캔 활용
-- 커버링 인덱스: (user_id, created_at, amount)
SELECT user_id, SUM(amount)
FROM orders  -- 인덱스만으로 처리 가능
WHERE created_at >= '2024-01-01'
GROUP BY user_id
```

---

## 7. 안티패턴

- **SELECT \*** : 필요한 컬럼만 명시 (성능 + 가독성)
- **암묵적 JOIN**: `FROM a, b WHERE a.id = b.a_id` → 명시적 JOIN
- **HAVING 대신 WHERE**: 집계 전 필터는 WHERE로 (집계 후만 HAVING)
- **중복 서브쿼리**: 같은 서브쿼리 여러 번 → CTE로 한 번만
- **NULL 비교**: `WHERE col = NULL` → `WHERE col IS NULL`
