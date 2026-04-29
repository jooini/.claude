# Data Cleaning

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/data-cleaning

---

## 1. 데이터 품질 문제 유형

```
완전성(Completeness): NULL, 빈 값
정확성(Accuracy): 잘못된 값 (나이 -5, 연도 9999)
일관성(Consistency): 같은 개념의 다른 표현 ('M', '남', '남성')
유일성(Uniqueness): 중복 행
시의성(Timeliness): 오래된 데이터
유효성(Validity): 형식 오류 (잘못된 이메일 형식)
```

---

## 2. Pandas 데이터 클리닝

```python
import pandas as pd
import numpy as np

df = pd.read_csv('raw_data.csv')

# 1. 기본 탐색
print(df.info())           # 타입, NULL 수
print(df.describe())       # 수치형 통계
print(df.isnull().sum())   # 컬럼별 NULL 수
print(df.duplicated().sum()) # 중복 행 수

# 2. NULL 처리
df['email'] = df['email'].fillna('unknown@example.com')  # 채우기
df['age'] = df['age'].fillna(df['age'].median())          # 중앙값으로
df = df.dropna(subset=['user_id', 'event_type'])          # 필수 컬럼 NULL 삭제

# 3. 중복 제거
df = df.drop_duplicates()                                  # 완전 중복
df = df.drop_duplicates(subset=['user_id'], keep='last')  # 최신 행 유지

# 4. 타입 변환
df['created_at'] = pd.to_datetime(df['created_at'], errors='coerce')
df['amount'] = pd.to_numeric(df['amount'], errors='coerce')  # 변환 실패 → NaN

# 5. 문자열 정제
df['email'] = df['email'].str.lower().str.strip()
df['phone'] = df['phone'].str.replace(r'[^0-9]', '', regex=True)  # 숫자만
df['name'] = df['name'].str.title()  # 첫 글자 대문자

# 6. 이상값 처리
q1, q3 = df['amount'].quantile([0.25, 0.75])
iqr = q3 - q1
lower, upper = q1 - 1.5 * iqr, q3 + 1.5 * iqr
df['amount_clean'] = df['amount'].clip(lower=lower, upper=upper)  # 이상값 클리핑
# 또는 제거
df = df[df['amount'].between(lower, upper)]

# 7. 카테고리 표준화
gender_map = {
    '남': 'M', '남성': 'M', 'male': 'M', 'Male': 'M', 'm': 'M',
    '여': 'F', '여성': 'F', 'female': 'F', 'Female': 'F', 'f': 'F',
}
df['gender'] = df['gender'].map(gender_map).fillna('Unknown')
```

---

## 3. SQL 데이터 클리닝

```sql
-- 문자열 정제
SELECT
  LOWER(TRIM(email))                            AS email,
  REGEXP_REPLACE(phone, '[^0-9]', '', 'g')      AS phone_clean,
  INITCAP(name)                                  AS name_clean

-- 날짜 파싱 (다양한 형식 처리)
SELECT
  CASE
    WHEN created_at ~ '^\d{4}-\d{2}-\d{2}$' THEN created_at::DATE
    WHEN created_at ~ '^\d{2}/\d{2}/\d{4}$' THEN TO_DATE(created_at, 'DD/MM/YYYY')
    ELSE NULL
  END AS date_clean

-- 이상값 처리
SELECT
  user_id,
  CASE
    WHEN age < 0 OR age > 120 THEN NULL  -- 비현실적 값
    ELSE age
  END AS age_clean

-- 중복 처리 (최신 행 유지)
SELECT DISTINCT ON (user_id)
  user_id, email, updated_at
FROM users
ORDER BY user_id, updated_at DESC
```

---

## 4. 데이터 클리닝 파이프라인

```python
from dataclasses import dataclass
from typing import Callable

@dataclass
class CleaningRule:
    column: str
    rule: Callable
    description: str

class DataCleaner:
    def __init__(self, df: pd.DataFrame):
        self.df = df.copy()
        self.cleaning_log = []

    def apply_rule(self, rule: CleaningRule) -> 'DataCleaner':
        before_nulls = self.df[rule.column].isnull().sum()
        self.df[rule.column] = rule.rule(self.df[rule.column])
        after_nulls = self.df[rule.column].isnull().sum()

        self.cleaning_log.append({
            'column': rule.column,
            'rule': rule.description,
            'nulls_before': before_nulls,
            'nulls_after': after_nulls,
        })
        return self

    def report(self) -> pd.DataFrame:
        return pd.DataFrame(self.cleaning_log)

# 사용
cleaner = (
    DataCleaner(raw_df)
    .apply_rule(CleaningRule('email', lambda s: s.str.lower().str.strip(), 'lowercase email'))
    .apply_rule(CleaningRule('amount', lambda s: pd.to_numeric(s, errors='coerce'), 'numeric amount'))
)
print(cleaner.report())
```

---

## 5. 안티패턴

- **원본 수정**: 항상 사본에서 작업, 원본 보존
- **클리닝 로직 미문서화**: 왜 이 값을 버렸는지 기록
- **이상값 무조건 제거**: 비즈니스적 의미 확인 후 처리
- **클리닝 후 검증 없음**: 결과 분포 확인 필수
- **일회성 클리닝**: 파이프라인에 통합, 자동화
