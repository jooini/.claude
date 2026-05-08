# Data Visualization

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/data-visualization

---

## 1. 차트 유형 선택 가이드

```
비교:
  항목 수 적음 → 막대 차트 (Bar)
  시간 추세    → 라인 차트 (Line)
  두 변수 관계 → 산점도 (Scatter)

구성:
  부분/전체 비율  → 파이/도넛 차트 (5개 이하만)
  누적 비율 변화  → 누적 막대/면적 차트
  트리맵 (계층)   → Treemap

분포:
  수치 분포     → 히스토그램, 박스플롯
  이상값 탐지   → 박스플롯

관계:
  두 변수 상관  → 산점도
  여러 변수     → 히트맵, 페어플롯
```

---

## 2. Matplotlib / Seaborn

```python
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd

# 기본 스타일 설정
plt.style.use('seaborn-v0_8-whitegrid')
sns.set_palette("husl")
FIGSIZE = (12, 6)

# 라인 차트 — 시계열
fig, ax = plt.subplots(figsize=FIGSIZE)
ax.plot(df['date'], df['revenue'], label='실적', color='#2196F3', linewidth=2)
ax.plot(df['date'], df['target'], label='목표', color='#FF9800', linestyle='--', linewidth=1.5)
ax.fill_between(df['date'], df['revenue'], df['target'],
                where=(df['revenue'] < df['target']), alpha=0.1, color='red')
ax.set_title('월별 매출 실적 vs 목표', fontsize=14, fontweight='bold')
ax.set_xlabel('날짜')
ax.set_ylabel('매출 (억원)')
ax.legend()
ax.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
plt.xticks(rotation=45)
plt.tight_layout()
plt.savefig('revenue_trend.png', dpi=150, bbox_inches='tight')

# 히트맵 — 상관관계
corr_matrix = df[['revenue', 'orders', 'avg_order_value', 'dau']].corr()
fig, ax = plt.subplots(figsize=(8, 6))
sns.heatmap(corr_matrix, annot=True, fmt='.2f', cmap='coolwarm',
            center=0, square=True, ax=ax)
ax.set_title('지표 간 상관관계')
plt.tight_layout()
```

---

## 3. Plotly (인터랙티브)

```python
import plotly.express as px
import plotly.graph_objects as go

# 인터랙티브 라인 차트
fig = px.line(
    df, x='date', y='revenue',
    title='월별 매출 추이',
    labels={'revenue': '매출', 'date': '날짜'},
    template='plotly_white',
)
fig.update_traces(hovertemplate='%{x}<br>매출: %{y:,.0f}원')
fig.show()

# 복합 차트 (막대 + 라인)
fig = go.Figure()
fig.add_trace(go.Bar(
    x=df['month'], y=df['orders'],
    name='주문 수', yaxis='y1'
))
fig.add_trace(go.Scatter(
    x=df['month'], y=df['revenue'],
    name='매출', yaxis='y2', mode='lines+markers'
))
fig.update_layout(
    title='월별 주문 수 및 매출',
    yaxis=dict(title='주문 수'),
    yaxis2=dict(title='매출', overlaying='y', side='right'),
)
fig.write_html('dashboard.html')  # 인터랙티브 HTML로 저장
```

---

## 4. 시각화 디자인 원칙

```
1. 데이터 잉크 비율 극대화
   - 불필요한 장식 제거 (3D 효과, 그라데이션)
   - 배경 격자선 최소화

2. 색상 의미 있게
   - 양수/음수: 초록/빨강
   - 중립: 파랑/회색
   - 색맹 고려: Colorbrewer 팔레트

3. 레이블 명확히
   - 축 제목 + 단위 필수
   - 범례 위치 (차트 안 또는 직접 레이블)

4. 컨텍스트 제공
   - 목표선, 기준선 추가
   - 주요 이벤트 주석
```

---

## 5. 안티패턴

- **파이 차트 남용**: 5개 이상 항목 → 막대 차트로
- **이중 축 혼란**: 단위 다른 두 데이터를 한 차트 → 가독성 저하
- **0 미포함 Y축**: 미미한 차이를 크게 보이게 → 오해 유발
- **색상 과다**: 10가지 색상 → 3~4가지로 제한
- **제목 없는 차트**: 보는 사람이 맥락을 모름
