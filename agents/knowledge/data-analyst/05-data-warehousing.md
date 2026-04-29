# Data Warehousing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/data-warehousing

---

## 1. 데이터 웨어하우스 아키텍처

```
소스 시스템 (운영 DB, API, 파일)
       ↓ Extract
스테이징 레이어 (원본 그대로)
       ↓ Transform
데이터 웨어하우스 (정제, 모델링)
       ↓
데이터 마트 (부서별 뷰)
       ↓
BI 도구 (Tableau, Looker, Metabase)
```

---

## 2. 레이어 구조 (Medallion Architecture)

```
Bronze (Raw / Staging):
  - 소스에서 그대로 적재
  - 스키마 검증만, 변환 없음
  - 재처리를 위한 원본 보존

Silver (Cleaned / Conformed):
  - 중복 제거, 타입 변환
  - 표준화 (날짜 포맷, 단위)
  - 비즈니스 엔티티 통합

Gold (Aggregated / Served):
  - 비즈니스 로직 적용
  - KPI 계산, 집계
  - BI 도구용 최적화
```

---

## 3. 주요 플랫폼 비교

| 플랫폼 | 특징 | 적합한 경우 |
|--------|------|-----------|
| BigQuery | 서버리스, 쿼리 비용 | GCP 환경, 초기 스타트업 |
| Snowflake | 멀티클라우드, 확장성 | 엔터프라이즈, 복잡한 워크로드 |
| Redshift | AWS 통합, 열 지향 | AWS 환경, 대규모 배치 |
| DuckDB | 로컬, 파일 직접 쿼리 | 개인 분석, 프로토타이핑 |
| PostgreSQL | 오픈소스, 범용 | 소규모, 예산 제한 |

---

## 4. 파티셔닝 & 클러스터링

```sql
-- BigQuery 파티셔닝
CREATE TABLE `project.dataset.events`
PARTITION BY DATE(event_time)  -- 날짜별 파티션
CLUSTER BY user_id, event_type  -- 파티션 내 물리적 정렬
AS SELECT * FROM source_events;

-- 파티션 필터 필수 (비용/성능)
SELECT * FROM `project.dataset.events`
WHERE DATE(event_time) = '2024-03-01'  -- 해당 파티션만 스캔
  AND user_id = '123'

-- Snowflake 클러스터 키
CREATE TABLE orders CLUSTER BY (TO_DATE(created_at), status);
```

---

## 5. 점진적 로드 (Incremental Load)

```sql
-- 전체 재로드 (Full Refresh): 소규모 테이블
TRUNCATE TABLE dim_product;
INSERT INTO dim_product SELECT * FROM source_products;

-- 점진적 로드 (Append): 이벤트 로그
INSERT INTO fact_events
SELECT * FROM staging_events
WHERE event_date = CURRENT_DATE - 1  -- 어제 데이터만

-- UPSERT (Merge): 사용자 프로파일 등
MERGE INTO dim_user AS target
USING staging_users AS source
ON target.user_id = source.user_id
WHEN MATCHED THEN
  UPDATE SET email = source.email, updated_at = NOW()
WHEN NOT MATCHED THEN
  INSERT (user_id, email, created_at) VALUES (source.user_id, source.email, NOW());
```

---

## 6. 데이터 신선도 (Freshness) 관리

```sql
-- 마지막 업데이트 시간 추적
CREATE TABLE pipeline_metadata (
  table_name      VARCHAR,
  last_run_at     TIMESTAMPTZ,
  rows_processed  INT,
  status          VARCHAR  -- success / failed
);

-- 신선도 알림 (SLA 위반)
SELECT table_name, last_run_at,
  EXTRACT(HOURS FROM NOW() - last_run_at) AS hours_since_update
FROM pipeline_metadata
WHERE last_run_at < NOW() - INTERVAL '25 hours'  -- 일별 배치 SLA 위반
  AND status = 'success'
```

---

## 7. 안티패턴

- **운영 DB = 분석 DB**: 분리 필요
- **ELT 없는 직접 쿼리**: 원본 변환 없이 BI에서 복잡한 로직 → 느림
- **스테이징 레이어 없음**: 실패 시 재처리 불가
- **파티션 필터 없는 BigQuery 쿼리**: 전체 테이블 스캔 → 비용 폭탄
- **오래된 통계 정보**: ANALYZE 없이 쿼리 플래너 오판
