# Machine Learning Basics

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/machine-learning-basics

---

## 1. ML 문제 유형

```
지도학습 (Supervised):
  회귀: 연속값 예측 (매출, LTV)
  분류: 범주 예측 (이탈 여부, 구매 여부)

비지도학습 (Unsupervised):
  클러스터링: 유사한 그룹 발견 (고객 세그먼트)
  차원 축소: 변수 압축 (PCA)

데이터 분석가가 자주 쓰는 ML:
  - 이탈 예측 (분류)
  - LTV 예측 (회귀)
  - 고객 세그먼테이션 (클러스터링)
  - 이상 탐지 (비지도)
```

---

## 2. ML 파이프라인

```python
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.metrics import classification_report

# 피처 정의
numeric_features = ['age', 'tenure_days', 'total_orders', 'avg_order_value']
categorical_features = ['plan', 'country', 'acquisition_channel']

# 전처리 파이프라인
preprocessor = ColumnTransformer([
    ('num', StandardScaler(), numeric_features),
    ('cat', OneHotEncoder(handle_unknown='ignore'), categorical_features),
])

# 전체 파이프라인
pipeline = Pipeline([
    ('preprocessor', preprocessor),
    ('classifier', RandomForestClassifier(n_estimators=100, random_state=42)),
])

# 학습/검증 분리
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

pipeline.fit(X_train, y_train)

# 평가
y_pred = pipeline.predict(X_test)
print(classification_report(y_test, y_pred))

# 교차 검증
cv_scores = cross_val_score(pipeline, X, y, cv=5, scoring='roc_auc')
print(f"CV ROC-AUC: {cv_scores.mean():.3f} ± {cv_scores.std():.3f}")
```

---

## 3. 피처 중요도

```python
# Random Forest 피처 중요도
feature_names = (
    numeric_features +
    list(pipeline.named_steps['preprocessor']
         .named_transformers_['cat']
         .get_feature_names_out(categorical_features))
)

importances = pipeline.named_steps['classifier'].feature_importances_
feature_importance_df = pd.DataFrame({
    'feature': feature_names,
    'importance': importances
}).sort_values('importance', ascending=False)

print(feature_importance_df.head(10))

# SHAP (모델 불문 해석)
import shap
explainer = shap.TreeExplainer(pipeline.named_steps['classifier'])
X_test_transformed = pipeline.named_steps['preprocessor'].transform(X_test)
shap_values = explainer.shap_values(X_test_transformed)

shap.summary_plot(shap_values[1], X_test_transformed, feature_names=feature_names)
```

---

## 4. 고객 세그먼테이션 (K-Means)

```python
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
import matplotlib.pyplot as plt

# RFM 기반 세그먼테이션
rfm = df.groupby('user_id').agg({
    'order_date':    lambda x: (pd.Timestamp.now() - x.max()).days,  # Recency
    'order_id':      'count',                                          # Frequency
    'order_amount':  'sum',                                            # Monetary
}).rename(columns={'order_date': 'recency', 'order_id': 'frequency', 'order_amount': 'monetary'})

# 스케일링
scaler = StandardScaler()
rfm_scaled = scaler.fit_transform(rfm)

# 최적 클러스터 수 (엘보우 방법)
inertias = []
for k in range(2, 11):
    km = KMeans(n_clusters=k, random_state=42, n_init=10)
    km.fit(rfm_scaled)
    inertias.append(km.inertia_)

plt.plot(range(2, 11), inertias, 'bo-')
plt.xlabel('클러스터 수')
plt.ylabel('Inertia')
plt.title('엘보우 방법')

# 최적 k로 학습
k = 4
km = KMeans(n_clusters=k, random_state=42, n_init=10)
rfm['segment'] = km.fit_predict(rfm_scaled)

# 세그먼트 특성 분석
print(rfm.groupby('segment').agg(['mean', 'count']))
```

---

## 5. 모델 평가 지표

```
분류:
  Accuracy:  (TP + TN) / Total — 불균형 데이터에서 오해 유발
  Precision: TP / (TP + FP)  — 양성 예측의 정확도
  Recall:    TP / (TP + FN)  — 실제 양성을 찾는 비율
  F1:        2 * P * R / (P + R)
  ROC-AUC:   전체 임계값에서 성능 (0.5=랜덤, 1=완벽)

회귀:
  MAE: 평균 절대 오차 (해석 쉬움)
  RMSE: 이상값에 민감 (큰 오차 더 페널티)
  MAPE: 백분율 오차 (단위 독립적)
  R²: 설명력 (0~1)

이탈 예측에서 Recall 중시:
  → 실제 이탈자를 놓치는 비용 > 잘못된 개입 비용
```

---

## 6. 안티패턴

- **데이터 누수(Leakage)**: 미래 정보가 학습 데이터에 포함
- **불균형 데이터 무시**: 이탈율 5%인 데이터 → Accuracy 95% = 의미 없음
- **과적합(Overfitting)**: 교차 검증 없이 학습 데이터 성능만 확인
- **해석 없는 모델**: "블랙박스" → SHAP으로 비즈니스 설명 필수
- **재학습 계획 없음**: 시간이 지나면 데이터 분포 변화 → 모델 성능 저하
