# Regression

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/regression

---

## 1. 선형 회귀 (Linear Regression)

```python
import pandas as pd
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import r2_score, mean_absolute_error, mean_squared_error
import statsmodels.api as sm

# 데이터 준비
X = df[['ad_spend', 'discount_rate', 'season_score']]
y = df['revenue']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# statsmodels — 통계적 해석
X_train_sm = sm.add_constant(X_train)
model = sm.OLS(y_train, X_train_sm).fit()
print(model.summary())
# - Coef: 계수 (각 변수의 영향력)
# - p-value: 통계적 유의성
# - R²: 설명력
# - F-statistic: 모델 전체 유의성

# sklearn — 예측
model_sk = LinearRegression()
model_sk.fit(X_train, y_train)
y_pred = model_sk.predict(X_test)

print(f"R²: {r2_score(y_test, y_pred):.3f}")
print(f"MAE: {mean_absolute_error(y_test, y_pred):,.0f}")
print(f"RMSE: {np.sqrt(mean_squared_error(y_test, y_pred)):,.0f}")
```

---

## 2. 회귀 진단

```python
import matplotlib.pyplot as plt
from scipy import stats

residuals = y_test - y_pred

fig, axes = plt.subplots(2, 2, figsize=(12, 10))

# 1. 잔차 플롯 (임의적이어야 함)
axes[0,0].scatter(y_pred, residuals)
axes[0,0].axhline(0, color='red')
axes[0,0].set_xlabel('예측값'), axes[0,0].set_ylabel('잔차')
axes[0,0].set_title('잔차 플롯')

# 2. Q-Q 플롯 (정규성)
stats.probplot(residuals, plot=axes[0,1])
axes[0,1].set_title('잔차 Q-Q 플롯')

# 3. 스케일-위치 (등분산성)
axes[1,0].scatter(y_pred, np.abs(residuals)**0.5)
axes[1,0].set_title('Scale-Location')

# 4. 실제값 vs 예측값
axes[1,1].scatter(y_test, y_pred, alpha=0.5)
axes[1,1].plot([y_test.min(), y_test.max()], [y_test.min(), y_test.max()], 'r--')
axes[1,1].set_title('실제 vs 예측')

plt.tight_layout()
```

---

## 3. 로지스틱 회귀 (Logistic Regression)

이진 분류 — 전환 여부, 이탈 여부 예측.

```python
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, roc_auc_score, roc_curve

# 이탈 예측 모델
X = df[['days_since_last_order', 'total_orders', 'avg_order_value', 'support_tickets']]
y = df['churned']  # 0 또는 1

model = LogisticRegression(max_iter=1000)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)
y_prob = model.predict_proba(X_test)[:, 1]

print(classification_report(y_test, y_pred))
print(f"ROC-AUC: {roc_auc_score(y_test, y_prob):.3f}")

# 계수 해석 (Odds Ratio)
import pandas as pd
coef_df = pd.DataFrame({
    'feature': X.columns,
    'coefficient': model.coef_[0],
    'odds_ratio': np.exp(model.coef_[0]),
})
print(coef_df.sort_values('odds_ratio', ascending=False))
# odds_ratio > 1: 이탈 가능성 증가
# odds_ratio < 1: 이탈 가능성 감소
```

---

## 4. 다중공선성 확인

```python
from statsmodels.stats.outliers_influence import variance_inflation_factor

# VIF > 10이면 다중공선성 문제
vif_data = pd.DataFrame({
    'feature': X.columns,
    'VIF': [variance_inflation_factor(X.values, i) for i in range(X.shape[1])]
})
print(vif_data.sort_values('VIF', ascending=False))
```

---

## 5. 안티패턴

- **외삽(Extrapolation)**: 학습 범위 밖의 값 예측
- **다중공선성 무시**: VIF 확인 없이 상관된 변수 모두 포함
- **잔차 진단 생략**: 회귀 가정 위반 확인 안 함
- **R²만 보기**: 훈련 데이터 R² 높아도 과적합일 수 있음
- **인과관계로 해석**: 회귀는 상관관계, 인과관계가 아님
