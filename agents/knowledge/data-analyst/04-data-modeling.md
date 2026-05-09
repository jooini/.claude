# Data Modeling

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/data-modeling

---

## 1. 분석용 데이터 모델 vs 운영 DB

```
운영 DB (OLTP):
  목적: 빠른 쓰기/읽기
  정규화: 높음 (중복 최소화)
  쿼리: 단건 조회, 간단한 집계

분석 DB (OLAP):
  목적: 복잡한 집계 쿼리
  정규화: 낮음 (조인 최소화)
  쿼리: 대용량 집계, 복잡한 분석
```

---

## 2. Star Schema (별 모양 스키마)

```
사실 테이블 (Fact Table) — 중심
  측정값 (매출, 수량, 클릭 수)
  외래키 (차원 테이블 참조)

차원 테이블 (Dimension Table) — 주변
  설명 속성 (누가, 언제, 어디서, 무엇을)
```

```sql
-- 사실 테이블
CREATE TABLE fact_sales (
  sale_id       BIGINT,
  date_key      INT,         -- dim_date 참조
  user_key      INT,         -- dim_user 참조
  product_key   INT,         -- dim_product 참조
  quantity      INT,
  unit_price    DECIMAL,
  discount_amt  DECIMAL,
  net_revenue   DECIMAL      -- 계산된 값 미리 저장 (성능)
);

-- 날짜 차원 (분석에 매우 유용)
CREATE TABLE dim_date (
  date_key      INT PRIMARY KEY,  -- YYYYMMDD 형식
  date          DATE,
  year          INT,
  quarter       INT,
  month         INT,
  month_name    VARCHAR(10),
  week_of_year  INT,
  day_of_week   INT,
  is_weekend    BOOLEAN,
  is_holiday    BOOLEAN
);

-- 분석 쿼리 — 조인이 단순해짐
SELECT
  d.year, d.month_name,
  p.category,
  SUM(f.net_revenue) AS revenue
FROM fact_sales f
JOIN dim_date    d ON d.date_key = f.date_key
JOIN dim_product p ON p.product_key = f.product_key
WHERE d.year = 2024
GROUP BY 1, 2, 3
```

---

## 3. SCD (Slowly Changing Dimensions)

차원이 시간에 따라 변할 때 처리 방법.

```sql
-- SCD Type 1: 덮어쓰기 (변경 이력 없음)
UPDATE dim_user SET email = 'new@email.com' WHERE user_id = 123

-- SCD Type 2: 이력 보존 (분석에 주로 사용)
CREATE TABLE dim_user (
  user_key     SERIAL PRIMARY KEY,   -- 대리 키
  user_id      INT,                  -- 원본 키
  email        VARCHAR,
  plan         VARCHAR,
  effective_from DATE,
  effective_to   DATE,               -- NULL = 현재 활성
  is_current     BOOLEAN
);

-- 변경 시: 기존 행 닫고 새 행 삽입
UPDATE dim_user SET effective_to = CURRENT_DATE, is_current = FALSE
WHERE user_id = 123 AND is_current = TRUE;

INSERT INTO dim_user (user_id, email, plan, effective_from, is_current)
VALUES (123, 'new@email.com', 'premium', CURRENT_DATE, TRUE);

-- 과거 시점 분석 가능
SELECT * FROM dim_user
WHERE user_id = 123 AND '2023-06-01' BETWEEN effective_from AND COALESCE(effective_to, '9999-12-31')
```

---

## 4. 비정규화 패턴

```sql
-- 분석용 Wide Table (조인 없이 바로 분석)
CREATE TABLE user_summary AS
SELECT
  u.id                           AS user_id,
  u.created_at                   AS signup_date,
  u.plan,
  u.country,
  COUNT(o.id)                    AS total_orders,
  SUM(o.amount)                  AS total_revenue,
  MIN(o.created_at)              AS first_order_date,
  MAX(o.created_at)              AS last_order_date,
  COUNT(DISTINCT DATE(o.created_at)) AS order_days
FROM users u
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'completed'
GROUP BY 1, 2, 3, 4;

-- 매일 갱신 (dbt 또는 Materialized View)
```

---

## 5. 그래프 데이터 모델링

```sql
-- 소셜 네트워크, 추천 시스템에서 사용
-- 인접 리스트 방식 (PostgreSQL)
CREATE TABLE user_follows (
  follower_id  INT REFERENCES users(id),
  followee_id  INT REFERENCES users(id),
  followed_at  TIMESTAMPTZ,
  PRIMARY KEY (follower_id, followee_id)
);

-- 2단계 연결 (친구의 친구)
SELECT DISTINCT uf2.followee_id AS suggested_user
FROM user_follows uf1
JOIN user_follows uf2 ON uf2.follower_id = uf1.followee_id
WHERE uf1.follower_id = 123
  AND uf2.followee_id != 123
  AND NOT EXISTS (
    SELECT 1 FROM user_follows
    WHERE follower_id = 123 AND followee_id = uf2.followee_id
  )
```

---

## 6. 안티패턴

- **운영 DB에서 직접 분석**: 운영 쿼리 성능 영향, 분석 쿼리 느림
- **과도한 정규화**: 분석용 DB에서 10개 이상 조인 → 비정규화 검토
- **날짜 차원 없음**: `DATE_TRUNC` 반복 계산 → dim_date로 미리 생성
- **NULL 처리 미설계**: NULL이 집계에 미치는 영향 미고려
- **대리키 없는 SCD Type 2**: 원본 ID로만 관리 → 이력 조회 어려움
