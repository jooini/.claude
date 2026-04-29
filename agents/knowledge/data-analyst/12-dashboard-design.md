# Dashboard Design

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/dashboard-design

---

## 1. 대시보드 설계 원칙

```
목적 먼저:
  "이 대시보드로 어떤 결정을 내리는가?"
  → 목적 없는 대시보드 = 보고용 차트 모음

사용자 중심:
  경영진: 핵심 KPI, 한눈에 파악
  분석가: 드릴다운, 필터링
  운영팀: 실시간 모니터링

계층 구조:
  Level 1: 핵심 지표 (5~7개)
  Level 2: 세부 분석
  Level 3: 원시 데이터
```

---

## 2. 레이아웃 패턴

```
F-패턴 (좌상 → 우 → 아래):
  ┌─────────────────────────────────┐
  │  KPI 1  │  KPI 2  │  KPI 3      │  ← 핵심 지표
  ├─────────────────────────────────┤
  │  추세 차트 (큰 영역)            │  ← 주요 트렌드
  ├──────────────┬──────────────────┤
  │  상세 차트 1 │  상세 차트 2     │  ← 세부 분석
  └──────────────┴──────────────────┘

Scorecard 배치:
  - 현재값 + 전월 대비 + 목표 대비
  - 트래픽 라이트 (🟢🟡🔴)
```

---

## 3. Metabase 대시보드 구성

```
카드 유형:
  Metric: 단일 수치 (KPI)
  Line/Bar: 추세, 비교
  Table: 상세 목록
  Map: 지역 분석

필터 설계:
  날짜 범위 (필수)
  카테고리 필터 (선택)
  세그먼트 필터

좋은 필터:
  - 기본값이 가장 많이 쓰는 값
  - 필터 간 연동 (채널 선택 → 관련 지표만)
```

---

## 4. Looker Studio 템플릿

```
페이지 구조:
  Page 1: 종합 현황 (경영진용)
  Page 2: 채널별 분석
  Page 3: 콘텐츠 성과
  Page 4: 원시 데이터

컴포넌트:
  Scorecard: 핵심 수치
  Time Series: 기간 추이
  Bar: 채널 비교
  Table: TOP 10 콘텐츠
  Pie: 트래픽 소스 비중

데이터 신선도 표시:
  마지막 업데이트 시간 항상 표시
```

---

## 5. 인터랙티브 요소

```python
# Streamlit 대시보드 예시
import streamlit as st
import pandas as pd
import plotly.express as px

st.set_page_config(page_title="Sales Dashboard", layout="wide")
st.title("📊 매출 분석 대시보드")

# 필터
col1, col2 = st.columns(2)
with col1:
    date_range = st.date_input("기간", value=[start_date, end_date])
with col2:
    channel = st.multiselect("채널", options=['organic', 'paid', 'email'], default=['organic'])

# 데이터 로딩
df = load_data(date_range, channel)

# KPI 카드
k1, k2, k3 = st.columns(3)
k1.metric("총 매출", f"₩{df['revenue'].sum():,.0f}", f"{mom_growth:+.1f}%")
k2.metric("주문 수", f"{df['orders'].sum():,}", f"{order_growth:+.1f}%")
k3.metric("전환율", f"{df['conversion_rate'].mean():.1%}", f"{cvr_change:+.2%}")

# 차트
fig = px.line(df, x='date', y='revenue', title='일별 매출')
st.plotly_chart(fig, use_container_width=True)
```

---

## 6. 안티패턴

- **지표 과다**: 30개 KPI 대시보드 → 핵심 7개
- **컨텍스트 없는 수치**: 전월 대비, 목표 대비 없음
- **정적 대시보드**: 드릴다운, 필터 없음
- **로딩 느린 대시보드**: 쿼리 최적화 또는 집계 테이블
- **신선도 표시 없음**: 언제 데이터인지 모름
