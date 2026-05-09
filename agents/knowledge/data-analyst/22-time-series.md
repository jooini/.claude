# Time Series

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/time-series

---

## 1. 시계열 분해 (Decomposition)

```python
import pandas as pd
from statsmodels.tsa.seasonal import seasonal_decompose
import matplotlib.pyplot as plt

# 시계열 = 추세(Trend) + 계절성(Seasonality) + 잔차(Residual)
df_ts = df.set_index('date')['revenue']

result = seasonal_decompose(df_ts, model='additive', period=7)  # 주별 계절성

fig, axes = plt.subplots(4, 1, figsize=(12, 10))
result.observed.plot(ax=axes[0], title='원시 데이터')
result.trend.plot(ax=axes[1], title='추세')
result.seasonal.plot(ax=axes[2], title='계절성')
result.resid.plot(ax=axes[3], title='잔차')
plt.tight_layout()

# 계절 조정 시계열
df_ts_sa = df_ts - result.seasonal
```

---

## 2. 정상성 검정과 차분

```python
from statsmodels.tsa.stattools import adfuller

def test_stationarity(series):
    """ADF 검정으로 정상성 확인"""
    result = adfuller(series.dropna())
    print(f"ADF 통계량: {result[0]:.4f}")
    print(f"p-value: {result[1]:.4f}")
    print(f"정상 여부: {'✅ 정상' if result[1] < 0.05 else '❌ 비정상 (차분 필요)'}")

test_stationarity(df_ts)

# 비정상이면 차분
df_diff = df_ts.diff()         # 1차 차분
df_diff2 = df_ts.diff().diff() # 2차 차분 (추세 제거)
df_log_diff = np.log(df_ts).diff()  # 로그 차분 (분산 안정화)
```

---

## 3. SARIMA 모델

```python
from statsmodels.tsa.statespace.sarimax import SARIMAX
from pmdarima import auto_arima

# 자동 파라미터 탐색
model_auto = auto_arima(
    df_ts,
    seasonal=True,
    m=7,          # 주별 계절성
    stepwise=True,
    information_criterion='aic',
)
print(model_auto.summary())

# SARIMA 모델 학습
model = SARIMAX(
    df_ts,
    order=(1, 1, 1),         # ARIMA (p, d, q)
    seasonal_order=(1, 1, 1, 7),  # 계절 (P, D, Q, s)
)
result = model.fit()

# 예측
forecast = result.forecast(steps=30)
conf_int = result.get_forecast(steps=30).conf_int()

# 시각화
plt.figure(figsize=(12, 5))
df_ts.plot(label='실제')
forecast.plot(label='예측')
plt.fill_between(conf_int.index, conf_int.iloc[:, 0], conf_int.iloc[:, 1], alpha=0.2)
plt.legend()
plt.title('30일 매출 예측')
```

---

## 4. Prophet (Facebook)

```python
from prophet import Prophet
import pandas as pd

# Prophet 형식: ds (날짜), y (값)
df_prophet = df[['date', 'revenue']].rename(columns={'date': 'ds', 'revenue': 'y'})

model = Prophet(
    seasonality_mode='multiplicative',  # 계절성이 추세에 비례할 때
    yearly_seasonality=True,
    weekly_seasonality=True,
    daily_seasonality=False,
)

# 공휴일 추가
holidays = pd.DataFrame({
    'holiday': 'korean_holiday',
    'ds': ['2024-01-01', '2024-02-09', '2024-02-10'],
    'lower_window': 0,
    'upper_window': 1,
})
model.add_country_holidays(country_name='KR')

model.fit(df_prophet)

# 예측
future = model.make_future_dataframe(periods=90)
forecast = model.predict(future)

fig = model.plot(forecast)
fig2 = model.plot_components(forecast)
```

---

## 5. 이상 탐지 (Time Series)

```python
# 이동 평균 기반
def detect_ts_anomalies(series, window=7, n_std=3):
    rolling_mean = series.rolling(window=window).mean()
    rolling_std  = series.rolling(window=window).std()
    upper = rolling_mean + n_std * rolling_std
    lower = rolling_mean - n_std * rolling_std
    anomalies = (series > upper) | (series < lower)
    return anomalies, upper, lower

anomalies, upper, lower = detect_ts_anomalies(df_ts)
print(f"이상 탐지: {anomalies.sum()}건")
```

---

## 6. 안티패턴

- **정상성 확인 없이 ARIMA**: 비정상 시계열에 직접 적용 → 가성 회귀
- **미래 데이터 누수**: 미래 정보가 학습 데이터에 포함
- **단일 지점 예측만**: 신뢰구간 없이 점 예측 → 불확실성 무시
- **계절성 무시**: 주간 / 월간 패턴 미고려
- **평가 지표 없는 모델**: MAE, RMSE, MAPE로 예측 성능 측정
