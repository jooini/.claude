# Causal Inference

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/causal-inference

---

## 1. 상관관계 vs 인과관계

```
상관관계: X와 Y가 함께 움직임
인과관계: X가 Y를 일으킴

아이스크림 판매 ↑ → 익사 사고 ↑
(상관관계 O, 인과관계 X → 더운 날씨가 공통 원인)

교란변수(Confounder):
  X와 Y 모두에 영향을 주는 숨겨진 변수
  올바른 인과 추론의 최대 장애물
```

---

## 2. 무작위 대조 실험 (RCT)

황금 표준. A/B 테스트가 대표적 예.

```python
# 무작위 배정으로 교란변수 제어
import numpy as np

np.random.seed(42)
df['group'] = np.where(
    np.random.random(len(df)) < 0.5, 'treatment', 'control'
)

# 그룹 균형 확인 (공변량 밸런스)
balance_check = df.groupby('group')[
    ['age', 'tenure_days', 'plan_premium']
].mean()
print(balance_check)
# 두 그룹이 유사해야 무작위 배정이 잘 됨
```

---

## 3. 이중차분법 (Difference-in-Differences)

실험이 불가할 때 자연 실험 활용.

```python
# DiD: 처치 전후 변화 - 대조군 전후 변화
# 가정: 처치 없었다면 두 그룹이 평행하게 움직였을 것

import statsmodels.formula.api as smf

# 열: user_id, period (pre/post), treated (0/1), outcome
model = smf.ols(
    'outcome ~ treated * post + C(user_id)',  # 고정 효과
    data=df
).fit(cov_type='HC3')  # 이분산성 강건 표준오차

print(model.summary())
# treated:post 계수 = DiD 추정량 (인과 효과)
```

---

## 4. 성향 점수 매칭 (Propensity Score Matching)

관측 데이터에서 처치군과 대조군 균형 맞추기.

```python
from sklearn.linear_model import LogisticRegression
import pandas as pd

# 1단계: 처치 확률(성향 점수) 추정
X_covariates = df[['age', 'income', 'tenure', 'plan']]
y_treated = df['received_treatment']

ps_model = LogisticRegression()
ps_model.fit(X_covariates, y_treated)
df['propensity_score'] = ps_model.predict_proba(X_covariates)[:, 1]

# 2단계: 성향 점수 기반 매칭
from sklearn.neighbors import NearestNeighbors

treated = df[df['received_treatment'] == 1]
control = df[df['received_treatment'] == 0]

nn = NearestNeighbors(n_neighbors=1)
nn.fit(control[['propensity_score']])
distances, indices = nn.kneighbors(treated[['propensity_score']])

matched_control = control.iloc[indices.flatten()]

# 3단계: 매칭된 그룹 간 비교
ate = treated['outcome'].mean() - matched_control['outcome'].mean()
print(f"Average Treatment Effect (ATE): {ate:.4f}")
```

---

## 5. 회귀 불연속 설계 (RDD)

임계값 전후를 비교해 인과 효과 추정.

```python
import numpy as np
import matplotlib.pyplot as plt

# 예: 신용점수 700 이상이면 대출 승인 → 매출 영향
df['above_threshold'] = (df['credit_score'] >= 700).astype(int)

# 임계값 주변 좁은 범위만 사용
bandwidth = 20
local_df = df[abs(df['credit_score'] - 700) <= bandwidth]

# 불연속성 시각화
fig, ax = plt.subplots()
below = local_df[local_df['credit_score'] < 700]
above = local_df[local_df['credit_score'] >= 700]

ax.scatter(below['credit_score'], below['outcome'], alpha=0.3, color='blue')
ax.scatter(above['credit_score'], above['outcome'], alpha=0.3, color='red')

# 각 그룹 추세선
for subset, color in [(below, 'blue'), (above, 'red')]:
    z = np.polyfit(subset['credit_score'], subset['outcome'], 1)
    p = np.poly1d(z)
    x_range = np.linspace(subset['credit_score'].min(), subset['credit_score'].max(), 100)
    ax.plot(x_range, p(x_range), color=color)

ax.axvline(700, color='black', linestyle='--', label='임계값(700)')
ax.set_title('회귀 불연속 설계')
```

---

## 6. 안티패턴

- **상관관계 → 인과관계**: 교란변수 고려 없이 결론
- **A/B 테스트 없이 출시 후 비교**: Before/After는 계절성, 트렌드 등 혼재
- **성향점수 매칭 후 검증 없음**: 매칭 후 공변량 밸런스 확인 필수
- **단일 방법에 의존**: 여러 방법으로 같은 결론 → 신뢰도 향상
- **외부 타당성 무시**: 실험 환경 ≠ 실제 환경
