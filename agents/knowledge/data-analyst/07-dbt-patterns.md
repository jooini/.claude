# dbt Patterns

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/dbt-patterns

---

## 1. dbt란

SQL 기반 변환 도구. ELT에서 "T" 담당.
버전 관리, 테스트, 문서화를 SQL 변환에 적용.

```
소스 데이터 (Bronze)
    ↓ staging models
정제된 데이터 (Silver)
    ↓ intermediate models
    ↓ mart models
분석용 데이터 (Gold)
```

---

## 2. 프로젝트 구조

```
models/
  staging/           # 소스 1:1 매핑, 이름 표준화
    stg_orders.sql
    stg_users.sql
  intermediate/      # 재사용 가능한 중간 변환
    int_order_items_enriched.sql
  marts/             # 비즈니스 도메인별 최종 모델
    core/
      dim_users.sql
      fct_orders.sql
    marketing/
      mart_user_acquisition.sql

seeds/               # CSV → DB 테이블 (코드 테이블 등)
  country_codes.csv

tests/               # 커스텀 테스트
  generic/
    assert_positive.sql

macros/              # 재사용 가능한 SQL 매크로
  date_trunc_week.sql
```

---

## 3. Staging 모델

```sql
-- models/staging/stg_orders.sql
-- 소스에서 그대로 가져오되 이름/타입 표준화

WITH source AS (
  SELECT * FROM {{ source('app_db', 'orders') }}
),

renamed AS (
  SELECT
    id                                        AS order_id,
    user_id,
    status,
    amount                                    AS order_amount,
    created_at::TIMESTAMPTZ                   AS created_at,
    updated_at::TIMESTAMPTZ                   AS updated_at,

    -- 표준화
    LOWER(TRIM(status))                       AS status_cleaned

  FROM source
)

SELECT * FROM renamed
```

---

## 4. Mart 모델

```sql
-- models/marts/core/fct_orders.sql
{{
  config(
    materialized='incremental',      -- 점진적 업데이트
    unique_key='order_id',
    on_schema_change='sync_all_columns'
  )
}}

WITH orders AS (
  SELECT * FROM {{ ref('stg_orders') }}

  {% if is_incremental() %}
  WHERE created_at > (SELECT MAX(created_at) FROM {{ this }})
  {% endif %}
),

users AS (
  SELECT * FROM {{ ref('stg_users') }}
),

final AS (
  SELECT
    o.order_id,
    o.user_id,
    u.email,
    u.country,
    u.plan,
    o.order_amount,
    o.status_cleaned AS status,
    o.created_at,
    DATE_TRUNC('month', o.created_at) AS order_month
  FROM orders o
  LEFT JOIN users u ON u.user_id = o.user_id
)

SELECT * FROM final
```

---

## 5. dbt 테스트

```yaml
# models/staging/schema.yml
version: 2

models:
  - name: stg_orders
    description: "주문 스테이징 모델"
    columns:
      - name: order_id
        description: "주문 고유 ID"
        tests:
          - not_null
          - unique

      - name: status
        tests:
          - not_null
          - accepted_values:
              values: ['pending', 'completed', 'cancelled', 'refunded']

      - name: user_id
        tests:
          - not_null
          - relationships:
              to: ref('stg_users')
              field: user_id

      - name: order_amount
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: ">= 0"
```

```bash
# 테스트 실행
dbt test --select stg_orders
dbt test --select tag:daily  # 태그별 실행
```

---

## 6. Macro 활용

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
  ({{ column_name }} / 100.0)::NUMERIC(10, 2)
{% endmacro %}

-- 사용
SELECT
  {{ cents_to_dollars('amount_cents') }} AS amount_dollars

-- macros/date_spine.sql — 날짜 연속 생성
{% macro date_spine(start_date, end_date) %}
  {{ dbt_utils.date_spine(
    datepart="day",
    start_date="cast('" ~ start_date ~ "' as date)",
    end_date="cast('" ~ end_date ~ "' as date)"
  ) }}
{% endmacro %}
```

---

## 7. 안티패턴

- **Staging에서 비즈니스 로직**: Staging은 소스 매핑만, 로직은 Mart에서
- **테스트 없는 모델**: unique + not_null 최소한 추가
- **모든 것을 Full Refresh**: 대용량 테이블은 Incremental로
- **ref() 없이 하드코딩 테이블명**: `FROM raw.orders` → `FROM {{ ref('stg_orders') }}`
- **문서화 없는 모델**: description 필수 (downstream 이해 가능)
