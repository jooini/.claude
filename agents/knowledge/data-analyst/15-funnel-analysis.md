# Funnel Analysis

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/funnel-analysis

---

## 1. 퍼널 분석 목적

사용자가 목표 행동(구매, 가입)까지 어느 단계에서 이탈하는지 파악.
이탈 지점 = 개선 기회.

---

## 2. 전환 퍼널 SQL

```sql
-- 방문 → 상품 조회 → 장바구니 → 결제 완료
WITH funnel AS (
  SELECT
    user_id,
    MAX(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END)       AS visited,
    MAX(CASE WHEN event_type = 'product_view' THEN 1 ELSE 0 END)    AS viewed_product,
    MAX(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END)     AS added_to_cart,
    MAX(CASE WHEN event_type = 'purchase_complete' THEN 1 ELSE 0 END) AS purchased
  FROM events
  WHERE event_date = CURRENT_DATE - 1
  GROUP BY user_id
)
SELECT
  SUM(visited)        AS step1_visitors,
  SUM(viewed_product) AS step2_product_viewers,
  SUM(added_to_cart)  AS step3_cart_adders,
  SUM(purchased)      AS step4_purchasers,

  -- 단계별 전환율
  ROUND(SUM(viewed_product) * 100.0 / NULLIF(SUM(visited), 0), 1)        AS step1_to_2_cvr,
  ROUND(SUM(added_to_cart) * 100.0 / NULLIF(SUM(viewed_product), 0), 1)  AS step2_to_3_cvr,
  ROUND(SUM(purchased) * 100.0 / NULLIF(SUM(added_to_cart), 0), 1)       AS step3_to_4_cvr,

  -- 최종 전환율
  ROUND(SUM(purchased) * 100.0 / NULLIF(SUM(visited), 0), 2)             AS overall_cvr
FROM funnel
```

---

## 3. 세그먼트별 퍼널 비교

```sql
-- 디바이스별 퍼널 비교
WITH funnel AS (
  SELECT
    user_id,
    device_type,
    MAX(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END)         AS visited,
    MAX(CASE WHEN event_type = 'purchase_complete' THEN 1 ELSE 0 END)  AS purchased
  FROM events
  WHERE event_date >= CURRENT_DATE - 30
  GROUP BY 1, 2
)
SELECT
  device_type,
  COUNT(*) AS users,
  SUM(purchased) AS purchasers,
  ROUND(SUM(purchased) * 100.0 / COUNT(*), 2) AS cvr
FROM funnel
GROUP BY device_type
ORDER BY cvr DESC
-- 결과: 모바일 cvr 1.2%, 데스크탑 cvr 3.4% → 모바일 개선 기회
```

---

## 4. 이탈 분석

```sql
-- 장바구니 이탈 후 행동 분석
WITH cart_abandoners AS (
  SELECT DISTINCT user_id
  FROM events
  WHERE event_type = 'add_to_cart'
    AND event_date = CURRENT_DATE - 1
  EXCEPT
  SELECT DISTINCT user_id
  FROM events
  WHERE event_type = 'purchase_complete'
    AND event_date = CURRENT_DATE - 1
),
next_actions AS (
  SELECT
    e.user_id,
    e.event_type,
    e.event_time,
    ROW_NUMBER() OVER (PARTITION BY e.user_id ORDER BY e.event_time) AS rn
  FROM events e
  JOIN cart_abandoners ca ON ca.user_id = e.user_id
  WHERE e.event_time > (
    SELECT MAX(event_time) FROM events
    WHERE user_id = e.user_id AND event_type = 'add_to_cart'
  )
)
SELECT event_type, COUNT(*) AS count
FROM next_actions
WHERE rn = 1
GROUP BY 1
ORDER BY 2 DESC
-- 이탈 후 가장 많이 하는 행동 파악
```

---

## 5. 시간 기반 퍼널

```sql
-- 가입 후 N일 이내 구매 전환
SELECT
  DATE_TRUNC('week', u.created_at) AS cohort_week,
  COUNT(*) AS signups,
  COUNT(CASE WHEN o.created_at <= u.created_at + INTERVAL '1 day' THEN 1 END)  AS day1_cvr,
  COUNT(CASE WHEN o.created_at <= u.created_at + INTERVAL '7 days' THEN 1 END) AS day7_cvr,
  COUNT(CASE WHEN o.created_at <= u.created_at + INTERVAL '30 days' THEN 1 END) AS day30_cvr
FROM users u
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'completed'
GROUP BY 1
ORDER BY 1
```

---

## 6. 안티패턴

- **집계 퍼널만**: 세그먼트(디바이스, 채널, 신규/기존) 비교 없음
- **순서 무시**: 동일 기간 내 이벤트 발생 순서 고려 안 함
- **중복 집계**: 사용자 기준이 아닌 이벤트 기준으로 집계
- **이탈 후 분석 없음**: 어디서 빠졌는지만 보고 왜 빠졌는지 분석 안 함
- **A/B 테스트 없이 결론**: 상관관계를 인과관계로
