# Data Quality

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/data-quality

---

## 1. 데이터 품질 프레임워크

```
예방 (Prevention):
  소스 시스템에서 품질 규칙 적용
  입력 유효성 검사

탐지 (Detection):
  자동화된 품질 체크
  모니터링 대시보드

대응 (Response):
  알림 및 에스컬레이션
  재처리 프로세스
```

---

## 2. Great Expectations (Python)

```python
import great_expectations as gx

context = gx.get_context()

# 데이터셋에 기대치 정의
suite = context.add_expectation_suite("orders_quality")

validator = context.get_validator(
    datasource_name="postgres",
    data_asset_name="orders",
    expectation_suite_name="orders_quality",
)

# 완전성
validator.expect_column_values_to_not_be_null("order_id")
validator.expect_column_values_to_not_be_null("user_id")

# 유일성
validator.expect_column_values_to_be_unique("order_id")

# 유효값
validator.expect_column_values_to_be_in_set(
    "status",
    ["pending", "completed", "cancelled", "refunded"]
)

# 범위
validator.expect_column_values_to_be_between(
    "amount",
    min_value=0,
    max_value=10_000_000
)

# 형식
validator.expect_column_values_to_match_regex(
    "email",
    r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$"
)

# 참조 무결성
validator.expect_column_pair_values_to_be_in_set(
    column_A="status",
    column_B="refund_amount",
    value_pairs_set=[("refunded", None), ("completed", None)],  # 미환불 주문은 환불금액 NULL
)

# 체크포인트 실행
checkpoint = context.add_checkpoint(
    name="orders_daily_check",
    validations=[{
        "batch_request": {"datasource_name": "postgres", "data_asset_name": "orders"},
        "expectation_suite_name": "orders_quality",
    }],
    action_list=[{
        "name": "send_slack_on_failure",
        "action": {"class_name": "SlackNotificationAction"},
    }]
)

result = checkpoint.run()
print(result["success"])  # True/False
```

---

## 3. SQL 기반 품질 체크

```sql
-- 품질 체크 결과를 테이블에 저장
INSERT INTO data_quality_checks (table_name, check_name, check_date, passed, failed_count, details)

SELECT
  'orders' AS table_name,
  'null_order_id' AS check_name,
  CURRENT_DATE AS check_date,
  COUNT(*) FILTER (WHERE order_id IS NULL) = 0 AS passed,
  COUNT(*) FILTER (WHERE order_id IS NULL) AS failed_count,
  'order_id must not be null' AS details
FROM orders
WHERE order_date = CURRENT_DATE - 1

UNION ALL

SELECT
  'orders',
  'valid_status',
  CURRENT_DATE,
  COUNT(*) FILTER (WHERE status NOT IN ('pending','completed','cancelled','refunded')) = 0,
  COUNT(*) FILTER (WHERE status NOT IN ('pending','completed','cancelled','refunded')),
  'status must be valid enum value'
FROM orders
WHERE order_date = CURRENT_DATE - 1;

-- 품질 대시보드
SELECT
  table_name,
  check_name,
  check_date,
  CASE WHEN passed THEN '✅' ELSE '❌' END AS status,
  failed_count
FROM data_quality_checks
WHERE check_date >= CURRENT_DATE - 7
ORDER BY check_date DESC, passed ASC
```

---

## 4. 이상 탐지

```python
import pandas as pd
from scipy import stats

def detect_anomalies(df: pd.DataFrame, column: str, window: int = 7) -> pd.DataFrame:
    """Z-score 기반 이상값 탐지"""
    df = df.copy()
    df['rolling_mean'] = df[column].rolling(window=window).mean()
    df['rolling_std']  = df[column].rolling(window=window).std()
    df['z_score'] = (df[column] - df['rolling_mean']) / df['rolling_std']
    df['is_anomaly'] = df['z_score'].abs() > 3  # 3 시그마
    return df

# 일별 주문 수 이상 탐지
daily_orders = df.groupby('order_date').size().reset_index(name='order_count')
result = detect_anomalies(daily_orders, 'order_count')

anomalies = result[result['is_anomaly']]
if not anomalies.empty:
    send_alert(f"주문 수 이상 탐지: {anomalies}")
```

---

## 5. 데이터 계보 (Data Lineage)

```
원본 데이터 → 어떤 변환 → 최종 데이터

추적이 중요한 이유:
  - 버그 발생 시 영향 범위 파악
  - 규정 준수 (GDPR 등)
  - 신뢰성 확보

dbt에서 자동 계보 생성:
  dbt docs generate
  dbt docs serve
  → 모델 간 의존성 시각화
```

---

## 6. 안티패턴

- **수동 품질 체크**: 자동화 없는 일회성 확인
- **품질 문제 발견 후 무시**: 알림만 하고 대응 없음
- **소스에서 품질 체크 없음**: 다운스트림에서 발견 → 영향 범위 큼
- **임계값 없는 모니터링**: "몇 건이 이상이면 알림?" 기준 없음
- **품질 이력 미보존**: 과거 품질 추세 파악 불가
