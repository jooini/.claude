# PostgreSQL

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/postgresql

---

## 1. PostgreSQL vs MySQL/MariaDB

| 항목 | PostgreSQL | MariaDB |
|------|-----------|---------|
| JSON 지원 | JSONB (인덱싱 가능) | JSON (텍스트) |
| 전문 검색 | tsvector 내장 | 별도 엔진 필요 |
| 배열 타입 | 네이티브 | 없음 |
| CTE | 완전 지원 | 제한적 |
| 윈도우 함수 | 완전 지원 | 완전 지원 |
| 확장성 | Extensions (PostGIS 등) | 제한적 |

---

## 2. 핵심 타입

```sql
-- UUID
CREATE TABLE users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ...
);

-- JSONB — JSON 저장 + 인덱싱 가능
CREATE TABLE products (
  id UUID PRIMARY KEY,
  metadata JSONB
);

-- 조회
SELECT * FROM products WHERE metadata->>'category' = 'electronics';
SELECT * FROM products WHERE metadata @> '{"tags": ["sale"]}';

-- JSONB 인덱스
CREATE INDEX idx_products_metadata ON products USING GIN(metadata);

-- 배열
CREATE TABLE posts (
  id UUID PRIMARY KEY,
  tags TEXT[]
);

INSERT INTO posts (tags) VALUES (ARRAY['nestjs', 'typescript']);
SELECT * FROM posts WHERE 'nestjs' = ANY(tags);
CREATE INDEX idx_posts_tags ON posts USING GIN(tags);

-- ENUM
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'banned');
ALTER TABLE users ADD COLUMN status user_status DEFAULT 'active';
```

---

## 3. 인덱스 전략

```sql
-- B-Tree (기본) — 등호, 범위 조건
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

-- 복합 인덱스 — 컬럼 순서 중요 (선두 컬럼부터 사용)
CREATE INDEX idx_orders_user_status ON orders(user_id, status);
-- WHERE user_id = ? → 사용 가능
-- WHERE user_id = ? AND status = ? → 사용 가능
-- WHERE status = ? → 사용 불가 (선두 컬럼 없음)

-- 부분 인덱스 — 조건 범위 축소
CREATE INDEX idx_active_users ON users(email) WHERE status = 'active';

-- GIN — 배열, JSONB, 전문 검색
CREATE INDEX idx_posts_tags ON posts USING GIN(tags);
CREATE INDEX idx_products_search ON products USING GIN(to_tsvector('korean', title));

-- 인덱스 사용 여부 확인
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';
```

---

## 4. 쿼리 최적화

```sql
-- EXPLAIN ANALYZE로 실행 계획 확인
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT u.id, u.name, COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE u.status = 'active'
GROUP BY u.id, u.name
ORDER BY order_count DESC
LIMIT 20;

-- 주요 확인 포인트:
-- Seq Scan → 인덱스 추가 검토
-- Nested Loop vs Hash Join → 데이터 크기에 따라
-- cost=0.00..1234.56 → 추정 비용
-- actual time=0.123..45.678 → 실제 실행 시간
-- rows=100 → 예상 행 수 (실제와 크게 차이나면 ANALYZE 실행)
```

```sql
-- 통계 업데이트 (쿼리 플래너 정확도 향상)
ANALYZE users;
VACUUM ANALYZE orders;
```

---

## 5. CTE (Common Table Expressions)

```sql
-- 복잡한 쿼리를 단계적으로 분해
WITH active_users AS (
  SELECT id, name, email
  FROM users
  WHERE status = 'active'
),
user_order_stats AS (
  SELECT
    user_id,
    COUNT(*) as order_count,
    SUM(total) as total_spent
  FROM orders
  WHERE created_at >= NOW() - INTERVAL '30 days'
  GROUP BY user_id
)
SELECT
  u.name,
  u.email,
  COALESCE(s.order_count, 0) as order_count,
  COALESCE(s.total_spent, 0) as total_spent
FROM active_users u
LEFT JOIN user_order_stats s ON s.user_id = u.id
ORDER BY total_spent DESC
LIMIT 10;

-- Recursive CTE — 계층 구조 (카테고리 트리, 조직도)
WITH RECURSIVE category_tree AS (
  -- 기반 쿼리
  SELECT id, name, parent_id, 0 AS depth
  FROM categories
  WHERE parent_id IS NULL

  UNION ALL

  -- 재귀 쿼리
  SELECT c.id, c.name, c.parent_id, ct.depth + 1
  FROM categories c
  JOIN category_tree ct ON ct.id = c.parent_id
)
SELECT * FROM category_tree ORDER BY depth, name;
```

---

## 6. 윈도우 함수

```sql
-- 각 카테고리에서 가장 많이 팔린 상품 Top 3
SELECT *
FROM (
  SELECT
    product_id,
    category_id,
    total_sales,
    ROW_NUMBER() OVER (
      PARTITION BY category_id       -- 카테고리별로 분리
      ORDER BY total_sales DESC      -- 판매량 내림차순
    ) AS rank
  FROM product_sales
) ranked
WHERE rank <= 3;

-- 누적 합계
SELECT
  order_date,
  daily_revenue,
  SUM(daily_revenue) OVER (ORDER BY order_date) AS cumulative_revenue
FROM daily_stats;

-- 이전 행 참조
SELECT
  id,
  created_at,
  LAG(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS prev_login,
  created_at - LAG(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS gap
FROM user_sessions;
```

---

## 7. 전문 검색 (Full Text Search)

```sql
-- tsvector 컬럼 추가
ALTER TABLE posts ADD COLUMN search_vector tsvector;

-- 트리거로 자동 업데이트
CREATE FUNCTION posts_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := to_tsvector('simple',
    COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER posts_search_vector_trigger
BEFORE INSERT OR UPDATE ON posts
FOR EACH ROW EXECUTE FUNCTION posts_search_vector_update();

-- GIN 인덱스
CREATE INDEX idx_posts_search ON posts USING GIN(search_vector);

-- 검색
SELECT id, title, ts_rank(search_vector, query) AS rank
FROM posts, to_tsquery('simple', 'nestjs & typescript') query
WHERE search_vector @@ query
ORDER BY rank DESC
LIMIT 20;
```

---

## 8. 안티패턴

- **SELECT \* in production**: 불필요한 컬럼 전송, 인덱스 온리 스캔 불가
- **LIKE '%검색어%'**: 인덱스 미사용 → 전문 검색 또는 pg_trgm
- **함수 감싼 WHERE 조건**: `WHERE DATE(created_at) = '2024-01-01'` → 인덱스 미사용. `WHERE created_at >= '2024-01-01' AND created_at < '2024-01-02'`로
- **VACUUM 미실행**: 불필요한 행 누적 → 정기 VACUUM ANALYZE
- **통계 미업데이트**: 쿼리 플래너 오판 → ANALYZE 정기 실행
