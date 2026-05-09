# ETL Pipelines

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/etl-pipelines

---

## 1. ETL vs ELT

```
ETL (Extract → Transform → Load):
  변환 후 적재. 전통적 방식.
  적합: 레거시 시스템, 복잡한 사전 변환

ELT (Extract → Load → Transform):
  원본 그대로 적재 후 웨어하우스에서 변환.
  적합: 클라우드 DW (BigQuery, Snowflake), 대용량
  장점: 원본 보존, 재처리 용이, SQL로 변환
```

---

## 2. Python ETL 기본 구조

```python
import pandas as pd
from sqlalchemy import create_engine
import logging
from datetime import date, timedelta

logger = logging.getLogger(__name__)

def extract(source_db_url: str, target_date: date) -> pd.DataFrame:
    """소스에서 데이터 추출"""
    engine = create_engine(source_db_url)
    query = """
        SELECT id, user_id, amount, status, created_at
        FROM orders
        WHERE DATE(created_at) = %(date)s
    """
    df = pd.read_sql(query, engine, params={'date': target_date})
    logger.info(f"Extracted {len(df)} rows for {target_date}")
    return df

def transform(df: pd.DataFrame) -> pd.DataFrame:
    """데이터 정제 및 변환"""
    # 타입 변환
    df['created_at'] = pd.to_datetime(df['created_at'])
    df['amount'] = df['amount'].astype(float)

    # 파생 컬럼
    df['order_date'] = df['created_at'].dt.date
    df['is_large_order'] = df['amount'] >= 100000

    # NULL 처리
    df['status'] = df['status'].fillna('unknown')

    # 중복 제거
    df = df.drop_duplicates(subset=['id'])

    logger.info(f"Transformed {len(df)} rows")
    return df

def load(df: pd.DataFrame, target_db_url: str, table: str):
    """대상 DB에 적재"""
    engine = create_engine(target_db_url)
    df.to_sql(
        table,
        engine,
        if_exists='append',  # 또는 'replace'
        index=False,
        chunksize=1000,
        method='multi',
    )
    logger.info(f"Loaded {len(df)} rows to {table}")

def run_pipeline(source_url: str, target_url: str, target_date: date):
    try:
        df = extract(source_url, target_date)
        df = transform(df)
        load(df, target_url, 'fact_orders')
        log_success(target_date, len(df))
    except Exception as e:
        logger.error(f"Pipeline failed: {e}")
        send_alert(f"ETL failed for {target_date}: {e}")
        raise
```

---

## 3. 오케스트레이션 — Apache Airflow

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.sql import SQLCheckOperator
from datetime import datetime, timedelta

default_args = {
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
    'email_on_failure': True,
    'email': ['data-team@company.com'],
}

with DAG(
    'daily_orders_etl',
    default_args=default_args,
    schedule_interval='0 3 * * *',  # 매일 오전 3시
    start_date=datetime(2024, 1, 1),
    catchup=False,  # 과거 미실행 건 소급 실행 안 함
) as dag:

    extract_task = PythonOperator(
        task_id='extract_orders',
        python_callable=extract,
        op_kwargs={'target_date': '{{ ds }}'},  # 실행 날짜
    )

    transform_task = PythonOperator(
        task_id='transform_orders',
        python_callable=transform,
    )

    # 품질 체크
    quality_check = SQLCheckOperator(
        task_id='check_row_count',
        sql="SELECT COUNT(*) > 0 FROM fact_orders WHERE order_date = '{{ ds }}'",
        conn_id='warehouse',
    )

    extract_task >> transform_task >> quality_check
```

---

## 4. 멱등성 (Idempotency)

파이프라인을 여러 번 실행해도 같은 결과.

```python
def load_idempotent(df: pd.DataFrame, target_date: date):
    """같은 날짜 데이터는 먼저 삭제 후 삽입"""
    with engine.begin() as conn:
        # 기존 데이터 삭제
        conn.execute(
            "DELETE FROM fact_orders WHERE order_date = %s",
            (target_date,)
        )
        # 새 데이터 삽입
        df.to_sql('fact_orders', conn, if_exists='append', index=False)
```

---

## 5. 에러 처리와 재시도

```python
import time
from functools import wraps

def retry(max_attempts: int = 3, delay: float = 1.0, backoff: float = 2.0):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_attempts):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts - 1:
                        raise
                    wait = delay * (backoff ** attempt)
                    logger.warning(f"Attempt {attempt+1} failed: {e}. Retrying in {wait}s")
                    time.sleep(wait)
        return wrapper
    return decorator

@retry(max_attempts=3, delay=2.0)
def extract_with_retry(source_url: str, date: date) -> pd.DataFrame:
    return extract(source_url, date)
```

---

## 6. 안티패턴

- **멱등성 없는 파이프라인**: 재실행 시 중복 데이터
- **에러 처리 없음**: 실패 시 조용히 부분 성공
- **단일 거대 파이프라인**: 실패 시 전체 재실행 → 태스크 분리
- **모니터링 없는 파이프라인**: 실패를 나중에 발견
- **하드코딩된 날짜**: 파라미터로 외부에서 주입
