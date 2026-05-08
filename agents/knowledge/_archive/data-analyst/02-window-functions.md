# Window Functions

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/window-functions

---

## 1. 윈도우 함수 기본 구조

```sql
함수명() OVER (
  PARTITION BY 그룹 기준 컬럼
  ORDER BY 정렬 기준 컬럼
  ROWS/RANGE BETWEEN 시작 AND 끝  -- 프레임 (선택)
)
```

GROUP BY와 달리 행을 줄이지 않고 각 행에 집계값을 붙인다.

---

## 2. 순위 함수

```sql
SELECT
  user_id,
  category,
  revenue,
  -- 동점자 같은 순위, 다음 순위 건너뜀 (1,1,3)
  RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank,
  -- 동점자 같은 순위, 다음 순위 안 건너뜀 (1,1,2)
  DENSE_RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS dense_rank,
  -- 동점자 없이 고유 번호 (1,2,3)
  ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) AS row_num,
  -- 백분율 순위 (0~1)
  PERCENT_RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS pct_rank,
  -- N개 버킷으로 분류 (사분위수 등)
  NTILE(4) OVER (ORDER BY revenue DESC) AS quartile
FROM user_sales

-- 카테고리별 TOP 3 추출
SELECT * FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) AS rn
  FROM user_sales
) t
WHERE rn <= 3
```

---

## 3. 집계 윈도우 함수

```sql
SELECT
  order_date,
  daily_revenue,
  -- 누적 합계
  SUM(daily_revenue) OVER (ORDER BY order_date) AS cumulative_revenue,
  -- 이동 평균 (최근 7일)
  AVG(daily_revenue) OVER (
    ORDER BY order_date
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ) AS moving_avg_7d,
  -- 전체 합계 (비율 계산용)
  SUM(daily_revenue) OVER () AS total_revenue,
  -- 비율
  ROUND(daily_revenue / SUM(daily_revenue) OVER () * 100, 1) AS pct_of_total
FROM daily_stats
ORDER BY order_date
```

---

## 4. LAG / LEAD (전후 행 참조)

```sql
SELECT
  user_id,
  event_date,
  event_type,
  -- 이전 행 (기본 1행 전)
  LAG(event_date) OVER (PARTITION BY user_id ORDER BY event_date) AS prev_event_date,
  -- 2행 전
  LAG(event_type, 2) OVER (PARTITION BY user_id ORDER BY event_date) AS two_ago,
  -- 다음 행
  LEAD(event_date) OVER (PARTITION BY user_id ORDER BY event_date) AS next_event_date,
  -- 전월 대비 성장률
  revenue,
  LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
  ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / LAG(revenue) OVER (ORDER BY month) * 100, 1) AS mom_growth_pct
FROM user_events
```

---

## 5. FIRST_VALUE / LAST_VALUE / NTH_VALUE

```sql
SELECT
  user_id,
  purchase_date,
  amount,
  -- 첫 번째 구매 금액
  FIRST_VALUE(amount) OVER (
    PARTITION BY user_id ORDER BY purchase_date
  ) AS first_purchase_amount,
  -- 마지막 구매 (RANGE BETWEEN 필요)
  LAST_VALUE(amount) OVER (
    PARTITION BY user_id ORDER BY purchase_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  ) AS last_purchase_amount,
  -- N번째 구매
  NTH_VALUE(amount, 3) OVER (
    PARTITION BY user_id ORDER BY purchase_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  ) AS third_purchase_amount
FROM purchases
```

---

## 6. 실전 분석 패턴

```sql
-- 세션 경계 찾기 (30분 이상 간격 = 새 세션)
WITH session_flags AS (
  SELECT
    user_id,
    event_time,
    CASE
      WHEN event_time - LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time)
           > INTERVAL '30 minutes'
        OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
      THEN 1 ELSE 0
    END AS is_session_start
  FROM events
)
SELECT
  user_id,
  event_time,
  SUM(is_session_start) OVER (PARTITION BY user_id ORDER BY event_time) AS session_id
FROM session_flags

-- 처음/마지막 구매 사이의 모든 행 플래그
SELECT *,
  MIN(purchase_date) OVER (PARTITION BY user_id) AS first_purchase,
  MAX(purchase_date) OVER (PARTITION BY user_id) AS last_purchase
FROM purchases
```

---

## 7. 안티패턴

- **PARTITION BY 없이 RANK()**: 전체 데이터를 하나의 윈도우로 처리
- **LAST_VALUE 프레임 미설정**: 기본 프레임이 현재 행까지라 마지막 값 ≠ 기대값
- **윈도우 함수를 WHERE에서 사용**: 불가 — 서브쿼리나 CTE로 감싸야 함
- **GROUP BY + 윈도우 함수 혼용**: GROUP BY 후 결과에 윈도우 함수 적용 가능하나 순서 주의
