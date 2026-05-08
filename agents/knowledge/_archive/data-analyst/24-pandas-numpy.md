# Pandas & NumPy

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/pandas-numpy

---

## 1. Pandas 핵심 패턴

```python
import pandas as pd
import numpy as np

# 데이터 로딩
df = pd.read_csv('data.csv', parse_dates=['created_at'], dtype={'user_id': str})
df = pd.read_parquet('data.parquet')  # 대용량 → parquet 권장

# 기본 탐색
df.shape           # (행, 열)
df.dtypes          # 컬럼별 타입
df.info()          # 메모리, NULL 정보
df.describe()      # 기술통계
df.head(10)
df['col'].value_counts()
df['col'].nunique()
```

---

## 2. 데이터 선택 & 필터링

```python
# 컬럼 선택
df[['col1', 'col2']]
df.filter(like='revenue')    # 이름에 'revenue' 포함된 컬럼

# 조건 필터링
df[df['amount'] > 10000]
df.query("amount > 10000 and status == 'completed'")  # 가독성 좋음

# loc (레이블), iloc (인덱스)
df.loc[df['status'] == 'active', 'email']
df.iloc[0:5, 2:4]

# 복합 조건
mask = (df['amount'] > 10000) & (df['status'] == 'completed')
df[mask]

# NULL 처리
df[df['email'].notna()]
df[df['amount'].between(1000, 100000)]
df[df['status'].isin(['active', 'trial'])]
```

---

## 3. GroupBy & 집계

```python
# 기본 집계
df.groupby('channel')['revenue'].agg(['sum', 'mean', 'count'])

# 복수 컬럼 집계
df.groupby(['channel', 'country']).agg(
    total_revenue=('revenue', 'sum'),
    order_count=('order_id', 'count'),
    avg_order=('revenue', 'mean'),
    unique_users=('user_id', 'nunique'),
)

# 변환 (크기 유지)
df['revenue_pct'] = df.groupby('channel')['revenue'].transform(
    lambda x: x / x.sum() * 100
)

# 필터링 (조건 만족하는 그룹만)
df.groupby('user_id').filter(lambda x: x['revenue'].sum() > 100000)

# 윈도우 함수 (rank, cumsum, etc.)
df['rank'] = df.groupby('channel')['revenue'].rank(ascending=False)
df['cumulative'] = df.groupby('channel')['revenue'].cumsum()
```

---

## 4. 날짜 처리

```python
# 날짜 파싱
df['date'] = pd.to_datetime(df['date_str'])

# 날짜 컴포넌트 추출
df['year']    = df['date'].dt.year
df['month']   = df['date'].dt.month
df['weekday'] = df['date'].dt.day_name()
df['is_weekend'] = df['date'].dt.dayofweek >= 5

# 기간 계산
df['days_since'] = (pd.Timestamp.now() - df['date']).dt.days
df['age_months'] = (pd.Timestamp.now() - df['date']) / pd.Timedelta(days=30)

# 리샘플링 (시계열 집계)
df.set_index('date').resample('W')['revenue'].sum()  # 주별
df.set_index('date').resample('M')['revenue'].agg(['sum', 'count'])  # 월별

# 기간 필터
df[df['date'].between('2024-01-01', '2024-03-31')]
df[df['date'] >= pd.Timestamp.now() - pd.Timedelta(days=30)]
```

---

## 5. NumPy 핵심 패턴

```python
import numpy as np

# 배열 생성
arr = np.array([1, 2, 3, 4, 5])
arr_2d = np.array([[1, 2, 3], [4, 5, 6]])
zeros = np.zeros((3, 4))
ones = np.ones((3, 4))
linspace = np.linspace(0, 1, 100)  # 0~1을 100등분

# 수학 연산
arr * 2          # 벡터 연산 (빠름)
np.sqrt(arr)
np.log(arr)
np.exp(arr)

# 통계
np.mean(arr)
np.median(arr)
np.std(arr)
np.percentile(arr, [25, 75])

# 조건 연산
np.where(arr > 3, 'high', 'low')
np.clip(arr, 1, 4)   # 최소 1, 최대 4로 클리핑

# 브로드캐스팅
matrix = np.random.randn(100, 5)
normalized = (matrix - matrix.mean(axis=0)) / matrix.std(axis=0)  # 컬럼별 정규화
```

---

## 6. 성능 최적화

```python
# Vectorization — 루프 대신 벡터 연산
# ❌ 느림
for i, row in df.iterrows():
    df.at[i, 'discount'] = row['amount'] * 0.1 if row['is_vip'] else 0

# ✅ 빠름
df['discount'] = np.where(df['is_vip'], df['amount'] * 0.1, 0)

# apply 최적화
# ❌ 느림 (Python 루프)
df['grade'] = df['score'].apply(lambda x: 'A' if x >= 90 else 'B')

# ✅ 빠름
df['grade'] = np.where(df['score'] >= 90, 'A', 'B')

# 메모리 최적화
df['status'] = df['status'].astype('category')   # 반복 문자열 → category
df['amount'] = df['amount'].astype('float32')    # float64 → float32

# 청크 처리 (대용량 CSV)
chunk_iter = pd.read_csv('large.csv', chunksize=100_000)
result = pd.concat([process_chunk(chunk) for chunk in chunk_iter])
```

---

## 7. 안티패턴

- **iterrows() 남용**: 느림 → vectorized 연산 사용
- **불필요한 copy()**: 메모리 낭비 → `df.loc` 직접 수정
- **체인 인덱싱**: `df['a']['b'] = val` → `df.loc[:, 'b'] = val`
- **데이터 타입 무시**: 큰 데이터에서 float64 기본값 → float32로
- **모든 데이터를 메모리에**: 대용량은 청크 처리 또는 Polars, DuckDB
