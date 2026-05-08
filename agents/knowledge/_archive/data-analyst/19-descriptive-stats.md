# Descriptive Statistics

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/descriptive-stats

---

## 1. 중심 경향 측도

```python
import pandas as pd
import numpy as np
from scipy import stats

data = pd.Series([12000, 15000, 18000, 22000, 95000, 16000, 14000])

print(f"평균(Mean):     {data.mean():,.0f}")     # 이상값에 민감
print(f"중앙값(Median): {data.median():,.0f}")   # 이상값에 강건
print(f"최빈값(Mode):   {data.mode()[0]:,.0f}")  # 가장 자주 나타나는 값

# 평균 vs 중앙값 차이 → 분포 비대칭성 신호
# 평균 > 중앙값 → 우편향 (소득, 매출처럼 극단값이 오른쪽)
# 평균 < 중앙값 → 좌편향

# 절사평균 (상하위 X% 제외)
trimmed_mean = stats.trim_mean(data, proportiontocut=0.1)
print(f"절사평균(10%):  {trimmed_mean:,.0f}")
```

---

## 2. 산포 측도

```python
# 범위
print(f"범위: {data.max() - data.min():,.0f}")

# 분산 / 표준편차
print(f"표준편차: {data.std():,.0f}")
print(f"분산:     {data.var():,.0f}")

# IQR (사분위 범위) — 이상값에 강건
q1, q3 = data.quantile([0.25, 0.75])
iqr = q3 - q1
print(f"IQR: {iqr:,.0f}")

# 변동계수 (CV) — 단위 다른 분포 비교
cv = data.std() / data.mean() * 100
print(f"변동계수: {cv:.1f}%")

# 백분위수
percentiles = data.quantile([0.05, 0.25, 0.50, 0.75, 0.95])
print(percentiles)
```

---

## 3. 분포 형태

```python
from scipy import stats

# 왜도 (Skewness): 0=대칭, >0=우편향, <0=좌편향
skewness = data.skew()
print(f"왜도: {skewness:.2f}")

# 첨도 (Kurtosis): 0=정규, >0=뾰족, <0=납작
kurtosis = data.kurtosis()
print(f"첨도: {kurtosis:.2f}")

# 정규성 검정
stat, p_value = stats.shapiro(data)
print(f"Shapiro-Wilk p={p_value:.4f} → {'정규분포' if p_value > 0.05 else '비정규분포'}")

# 시각화
import matplotlib.pyplot as plt
fig, axes = plt.subplots(1, 2, figsize=(12, 4))
data.hist(ax=axes[0], bins=20, edgecolor='black')
axes[0].set_title('히스토그램')
stats.probplot(data, dist='norm', plot=axes[1])
axes[1].set_title('Q-Q 플롯 (정규성 확인)')
plt.tight_layout()
```

---

## 4. 이상값 탐지

```python
# IQR 방법
lower = q1 - 1.5 * iqr
upper = q3 + 1.5 * iqr
outliers_iqr = data[(data < lower) | (data > upper)]
print(f"IQR 이상값: {outliers_iqr.tolist()}")

# Z-score 방법 (정규분포 가정)
z_scores = np.abs(stats.zscore(data))
outliers_z = data[z_scores > 3]
print(f"Z-score 이상값: {outliers_z.tolist()}")

# 수정된 Z-score (비정규분포에 강건)
mad = np.median(np.abs(data - np.median(data)))
modified_z = 0.6745 * (data - np.median(data)) / mad
outliers_mz = data[np.abs(modified_z) > 3.5]
```

---

## 5. 기술통계 리포트

```python
def describe_column(series: pd.Series, name: str) -> dict:
    """종합 기술통계 요약"""
    return {
        'column': name,
        'count': len(series),
        'missing': series.isnull().sum(),
        'missing_pct': f"{series.isnull().mean():.1%}",
        'mean': series.mean(),
        'median': series.median(),
        'std': series.std(),
        'min': series.min(),
        'p25': series.quantile(0.25),
        'p75': series.quantile(0.75),
        'max': series.max(),
        'skewness': series.skew(),
        'outliers_iqr': ((series < series.quantile(0.25) - 1.5*(series.quantile(0.75)-series.quantile(0.25)))
                        | (series > series.quantile(0.75) + 1.5*(series.quantile(0.75)-series.quantile(0.25)))).sum()
    }
```

---

## 6. 안티패턴

- **평균만 보고**: 이상값이 있으면 중앙값이 더 대표값
- **시각화 없이 수치만**: 분포 형태를 파악하지 못함
- **이상값 무조건 제거**: 비즈니스적 의미 확인 (VIP 고객의 고액 주문)
- **표준편차만으로 비교**: 단위 다른 변수는 변동계수(CV)로
- **정규성 가정 검증 없음**: 분포 형태에 따라 적절한 통계량 선택
