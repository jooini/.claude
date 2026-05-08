# Product Metrics

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/product-metrics

---

## 1. 메트릭 프레임워크 — AARRR (Pirate Metrics)

```
Acquisition  — 어떻게 사용자를 획득하는가
Activation   — 첫 경험이 좋은가 (AHA 모멘트)
Retention    — 돌아오는가
Revenue      — 어떻게 수익을 내는가
Referral     — 추천하는가
```

---

## 2. 핵심 제품 지표

```sql
-- DAU / MAU (일간/월간 활성 사용자)
-- Stickiness = DAU / MAU (높을수록 습관적 사용)
SELECT
  DATE(event_time) AS date,
  COUNT(DISTINCT user_id) AS dau
FROM events
WHERE event_type = 'session_start'
GROUP BY 1
ORDER BY 1

-- MAU
SELECT
  DATE_TRUNC('month', event_time) AS month,
  COUNT(DISTINCT user_id) AS mau
FROM events
WHERE event_type = 'session_start'
GROUP BY 1

-- NPS (Net Promoter Score)
SELECT
  COUNT(CASE WHEN score >= 9 THEN 1 END) * 100.0 / COUNT(*) AS promoters_pct,
  COUNT(CASE WHEN score <= 6 THEN 1 END) * 100.0 / COUNT(*) AS detractors_pct,
  (COUNT(CASE WHEN score >= 9 THEN 1 END) -
   COUNT(CASE WHEN score <= 6 THEN 1 END)) * 100.0 / COUNT(*) AS nps
FROM nps_surveys
WHERE survey_date >= CURRENT_DATE - 30
```

---

## 3. 리텐션 분석

```sql
-- Day-N 리텐션 (코호트별)
WITH cohorts AS (
  SELECT
    user_id,
    DATE_TRUNC('week', MIN(created_at)) AS cohort_week
  FROM users
  GROUP BY 1
),
activity AS (
  SELECT
    e.user_id,
    c.cohort_week,
    DATE_TRUNC('week', e.event_time) AS activity_week,
    DATE_PART('week', DATE_TRUNC('week', e.event_time) - c.cohort_week) AS week_number
  FROM events e
  JOIN cohorts c ON c.user_id = e.user_id
)
SELECT
  cohort_week,
  week_number,
  COUNT(DISTINCT user_id) AS retained_users,
  COUNT(DISTINCT user_id) * 100.0 /
    FIRST_VALUE(COUNT(DISTINCT user_id)) OVER (PARTITION BY cohort_week ORDER BY week_number) AS retention_rate
FROM activity
GROUP BY 1, 2
ORDER BY 1, 2
```

---

## 4. 퍼널 분석 SQL

```sql
-- 회원가입 → 첫 구매 → 재구매 퍼널
WITH user_journey AS (
  SELECT
    u.id AS user_id,
    u.created_at AS signup_date,
    MIN(o.created_at) AS first_purchase_date,
    CASE WHEN COUNT(o.id) >= 2 THEN MIN(o.created_at ORDER BY o.created_at DESC)
    END AS second_purchase_date
  FROM users u
  LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'completed'
  WHERE u.created_at >= '2024-01-01'
  GROUP BY 1, 2
)
SELECT
  COUNT(*)                                     AS total_signups,
  COUNT(first_purchase_date)                   AS first_purchasers,
  COUNT(second_purchase_date)                  AS repeat_purchasers,
  ROUND(COUNT(first_purchase_date) * 100.0 / COUNT(*), 1) AS signup_to_purchase_pct,
  ROUND(COUNT(second_purchase_date) * 100.0 / COUNT(first_purchase_date), 1) AS purchase_to_repeat_pct
FROM user_journey
```

---

## 5. 지표 설계 원칙

```
좋은 지표의 조건:
  ✅ 비교 가능: 전월 대비, 전년 동기 대비
  ✅ 이해 가능: 팀 전체가 의미를 앎
  ✅ 행동 유도: 지표 변화 → 무엇을 해야 하는지 명확
  ✅ 조작 어려움: 쉽게 게임화 불가

나쁜 지표 예시:
  페이지뷰만 → 질 낮은 트래픽도 포함
  가입자 수만 → 유령 계정 포함
  → 활성 유저 (로그인 또는 핵심 행동 기준)로
```

---

## 6. 안티패턴

- **허영 지표 (Vanity Metrics)**: 좋아 보이지만 결정에 도움 안 됨 (총 가입자 수)
- **단일 지표**: 한 지표 최적화 → 다른 지표 악화 (전환율↑ 환불율↑)
- **지표 정의 불일치**: 팀마다 다른 MAU 계산법
- **상관관계를 인과관계로**: "이 기능 출시 후 매출 상승" → 다른 변수 고려
- **이벤트 트래킹 부재**: 분석할 데이터 없음 → 이벤트 설계 먼저
