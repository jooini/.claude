# Cohort Analysis

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/cohort-analysis

---

## 1. 코호트 분석이란

동일한 기간에 같은 경험을 한 사용자 그룹(코호트)의 행동을 시간에 따라 추적.
리텐션, 수익화, LTV 분석의 핵심.

---

## 2. 리텐션 코호트

```sql
-- 주별 신규 가입 코호트의 리텐션
WITH user_cohorts AS (
  SELECT
    user_id,
    DATE_TRUNC('week', created_at)::DATE AS cohort_week
  FROM users
),
weekly_activity AS (
  SELECT
    uc.user_id,
    uc.cohort_week,
    DATE_TRUNC('week', e.event_time)::DATE AS activity_week,
    (DATE_TRUNC('week', e.event_time) - uc.cohort_week) / 7 AS week_number
  FROM user_cohorts uc
  JOIN events e ON e.user_id = uc.user_id
  WHERE e.event_type = 'session_start'
),
cohort_sizes AS (
  SELECT cohort_week, COUNT(DISTINCT user_id) AS cohort_size
  FROM user_cohorts
  GROUP BY 1
)
SELECT
  wa.cohort_week,
  cs.cohort_size,
  wa.week_number,
  COUNT(DISTINCT wa.user_id) AS retained_users,
  ROUND(COUNT(DISTINCT wa.user_id) * 100.0 / cs.cohort_size, 1) AS retention_rate
FROM weekly_activity wa
JOIN cohort_sizes cs ON cs.cohort_week = wa.cohort_week
WHERE wa.week_number <= 12  -- 12주까지
GROUP BY 1, 2, 3
ORDER BY 1, 3
```

---

## 3. 리텐션 매트릭스 시각화

```python
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

# SQL 결과를 피벗
retention_matrix = df.pivot_table(
    index='cohort_week',
    columns='week_number',
    values='retention_rate'
)

# 히트맵
fig, ax = plt.subplots(figsize=(14, 8))
sns.heatmap(
    retention_matrix,
    annot=True,
    fmt='.0f',
    cmap='RdYlGn',
    vmin=0, vmax=100,
    ax=ax,
    cbar_kws={'label': '리텐션율 (%)'}
)
ax.set_title('주별 코호트 리텐션 매트릭스', fontsize=14)
ax.set_xlabel('가입 후 경과 주')
ax.set_ylabel('코호트 (가입 주)')
plt.tight_layout()
```

---

## 4. LTV 코호트 분석

```sql
-- 코호트별 누적 LTV (가입 후 월별)
WITH user_cohorts AS (
  SELECT user_id, DATE_TRUNC('month', created_at)::DATE AS cohort_month
  FROM users
),
monthly_revenue AS (
  SELECT
    uc.user_id,
    uc.cohort_month,
    DATE_TRUNC('month', o.created_at)::DATE AS order_month,
    (DATE_TRUNC('month', o.created_at) - uc.cohort_month)::INT / 30 AS month_number,
    SUM(o.amount) AS revenue
  FROM user_cohorts uc
  JOIN orders o ON o.user_id = uc.user_id AND o.status = 'completed'
  GROUP BY 1, 2, 3, 4
)
SELECT
  cohort_month,
  month_number,
  SUM(revenue) / COUNT(DISTINCT user_id) AS avg_revenue_per_user,
  SUM(SUM(revenue) / COUNT(DISTINCT user_id)) OVER (
    PARTITION BY cohort_month ORDER BY month_number
  ) AS cumulative_ltv
FROM monthly_revenue
GROUP BY 1, 2
ORDER BY 1, 2
```

---

## 5. 코호트 비교 분석

```sql
-- 획득 채널별 코호트 품질 비교
SELECT
  acquisition_channel,
  DATE_TRUNC('month', u.created_at) AS cohort_month,
  COUNT(DISTINCT u.id) AS cohort_size,
  -- D30 리텐션
  COUNT(DISTINCT CASE
    WHEN e.event_time BETWEEN u.created_at + INTERVAL '28 days'
                          AND u.created_at + INTERVAL '31 days'
    THEN u.id END) * 100.0 / COUNT(DISTINCT u.id) AS d30_retention,
  -- 3개월 LTV
  SUM(CASE WHEN o.created_at <= u.created_at + INTERVAL '90 days'
      THEN o.amount END) / COUNT(DISTINCT u.id) AS ltv_90d
FROM users u
LEFT JOIN events e ON e.user_id = u.id AND e.event_type = 'session_start'
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'completed'
GROUP BY 1, 2
ORDER BY 2 DESC, d30_retention DESC
```

---

## 6. 안티패턴

- **전체 집계만**: "월 리텐션 25%" → 코호트별로 보면 신규가 낮고 기존이 높을 수 있음
- **절대값만 비교**: 코호트 크기 다르면 절대값 비교 무의미
- **짧은 관찰 기간**: 2주 데이터로 장기 LTV 예측 → 최소 3~6개월
- **활성 정의 불명확**: 로그인 = 활성? 핵심 행동 = 활성? 명확히 정의
- **세그먼트 없는 코호트**: 채널, 플랜별 비교 없이 전체만
