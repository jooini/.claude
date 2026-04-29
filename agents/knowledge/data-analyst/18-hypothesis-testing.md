# Hypothesis Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/hypothesis-testing

---

## 1. 가설 검정 프레임워크

```
1. 귀무가설(H0)과 대립가설(H1) 설정
   H0: "새 기능은 전환율에 영향이 없다" (차이 = 0)
   H1: "새 기능은 전환율을 높인다" (차이 > 0)

2. 유의수준(α) 설정: 보통 0.05 (5%)

3. 적절한 검정 선택

4. p-value 계산

5. 결론: p < α → H0 기각, 통계적으로 유의함
```

---

## 2. 검정 선택 가이드

```
연속형 변수:
  그룹 수 2개:
    정규 분포 O → t-검정
    정규 분포 X → Mann-Whitney U (비모수)
    대응 표본   → Paired t-검정
  그룹 수 3+:
    정규 분포 O → ANOVA
    정규 분포 X → Kruskal-Wallis

범주형 변수:
  비율 비교 → z-검정, Chi-squared
  빈도 비교 → Chi-squared, Fisher's exact

시계열:
  자기상관 → Durbin-Watson
  정상성   → ADF 검정
```

---

## 3. t-검정

```python
from scipy import stats
import numpy as np

# 독립 표본 t-검정 (두 그룹 평균 비교)
control_revenue   = np.array([45000, 52000, 48000, 55000, 43000, ...])
treatment_revenue = np.array([52000, 58000, 54000, 62000, 51000, ...])

# 정규성 검정 먼저 (Shapiro-Wilk, n < 50)
stat_c, p_c = stats.shapiro(control_revenue)
stat_t, p_t = stats.shapiro(treatment_revenue)
print(f"정규성 검정 - 대조군: p={p_c:.3f}, 실험군: p={p_t:.3f}")

# 등분산 검정 (Levene)
stat, p_levene = stats.levene(control_revenue, treatment_revenue)
equal_var = p_levene > 0.05

# t-검정
t_stat, p_value = stats.ttest_ind(
    control_revenue, treatment_revenue,
    equal_var=equal_var
)

print(f"t={t_stat:.3f}, p={p_value:.4f}")
print(f"통계적으로 유의: {p_value < 0.05}")

# 효과 크기 (Cohen's d)
pooled_std = np.sqrt((control_revenue.std()**2 + treatment_revenue.std()**2) / 2)
cohens_d = (treatment_revenue.mean() - control_revenue.mean()) / pooled_std
print(f"Cohen's d = {cohens_d:.2f}")
# 0.2: 작음, 0.5: 중간, 0.8: 큼
```

---

## 4. 카이제곱 검정

```python
from scipy.stats import chi2_contingency
import pandas as pd

# 클릭 여부 × 버튼 색상
contingency = pd.crosstab(df['button_color'], df['clicked'])
chi2, p, dof, expected = chi2_contingency(contingency)

print(f"χ²={chi2:.3f}, df={dof}, p={p:.4f}")
print(f"통계적으로 유의: {p < 0.05}")

# 기대빈도 확인 (5 이상이어야 카이제곱 검정 유효)
print(f"최소 기대빈도: {expected.min():.1f}")
```

---

## 5. 1종 오류 vs 2종 오류

```
1종 오류 (α, False Positive):
  H0가 참인데 기각 → "효과 없는 기능을 있다고 판단"
  → 잘못된 기능 배포
  → α = 0.05 → 5% 확률로 발생

2종 오류 (β, False Negative):
  H0가 거짓인데 기각 못 함 → "효과 있는 기능을 없다고 판단"
  → 좋은 기능 놓침
  → β = 0.20 → 파워(1-β) = 80%

트레이드오프:
  α 낮추면 → β 높아짐 (샘플 크기 늘려야 해결)
```

---

## 6. 안티패턴

- **p-value = 효과 크기**: p < 0.05이지만 효과가 실용적으로 의미 없을 수 있음
- **정규성 검정 생략**: t-검정 사용 전 분포 확인 필수
- **다중 비교 무시**: 10번 검정하면 1번은 우연히 유의
- **단방향 vs 양방향 혼동**: 방향성 가설이면 단방향, 아니면 양방향
- **신뢰구간 무시**: p-value만 보고 신뢰구간 범위 확인 안 함
