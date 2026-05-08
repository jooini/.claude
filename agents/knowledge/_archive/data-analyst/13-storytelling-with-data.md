# Storytelling with Data

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/storytelling-with-data

---

## 1. 데이터 스토리텔링이란

숫자를 나열하는 것이 아닌, 청중이 이해하고 행동할 수 있도록 데이터를 이야기로 전달하는 것.

```
나쁜 분석: "3월 MAU는 125,000입니다."
좋은 분석: "3월 MAU는 125,000으로 목표 대비 104% 달성했습니다.
           특히 신규 획득보다 기존 유저 리텐션 개선(+8%p)이
           주요 동인이었으며, 이는 2월에 출시한 알림 기능 덕분입니다.
           이 추세가 지속되면 Q2 목표 달성 가능성이 높습니다."
```

---

## 2. SCQA 스토리 구조

```
Situation (상황):
  "현재 어떤 상황인가?"
  → 청중이 이미 아는 맥락

Complication (문제):
  "그런데 어떤 문제가 있는가?"
  → 긴장감 형성

Question (질문):
  "그렇다면 어떻게 해야 하는가?"
  → 청중의 질문을 대신

Answer (답변):
  "이것이 해결책이다."
  → 명확한 행동 제안

예시:
  S: "지난 분기 광고 비용을 20% 증가시켰습니다."
  C: "그러나 전환율이 오히려 5% 하락했습니다."
  Q: "어디서 예산을 낭비하고 있을까요?"
  A: "분석 결과 모바일 광고의 ROAS가 데스크탑의 절반입니다.
      모바일 랜딩 페이지 개선이 최우선 과제입니다."
```

---

## 3. 피라미드 원칙

```
결론 먼저 (Bottom Line Up First):

경영진 발표:
  1. 결론: "Q1 목표 달성. 그러나 4월 리스크 존재."
  2. 근거: "매출 +18%, 사용자 +12%, 수익성 개선"
  3. 세부: 채널별 성과, 리스크 상세, 대응 방안

청중이 원하는 것:
  "그래서 어쩌라는 건데?" → 결론부터
  "왜?" → 근거
  "구체적으로?" → 세부
```

---

## 4. 효과적인 차트 활용

```python
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

# 주목할 데이터 포인트 강조
fig, ax = plt.subplots(figsize=(12, 6))
ax.plot(df['month'], df['revenue'], color='lightgray', linewidth=1.5)

# 이상 시점 강조
anomaly_month = df[df['is_anomaly']]['month'].iloc[0]
anomaly_value = df[df['is_anomaly']]['revenue'].iloc[0]
ax.scatter([anomaly_month], [anomaly_value], color='red', s=100, zorder=5)
ax.annotate(
    '구글 알고리즘 업데이트\n→ 트래픽 -23%',
    xy=(anomaly_month, anomaly_value),
    xytext=(anomaly_month, anomaly_value * 1.1),
    arrowprops=dict(arrowstyle='->', color='red'),
    color='red', fontsize=9,
)

# 중요 기간 음영
ax.axvspan('2024-02', '2024-03', alpha=0.1, color='green',
           label='캠페인 기간')

ax.set_title('월별 매출 — 주요 이벤트와 함께', fontsize=14)
```

---

## 5. 발표 구조

```markdown
## 분석 발표 구조 (15분 기준)

1. 한 줄 요약 (1분)
   "이번 분석의 핵심 결론은 ___입니다."

2. 배경 및 목적 (2분)
   "왜 이 분석을 했는가?"

3. 핵심 발견 3가지 (9분, 각 3분)
   각각: 발견 → 데이터 → 의미

4. 권고 사항 (2분)
   구체적 액션 + 기대 효과

5. Q&A 준비
   예상 질문: "데이터 기간은?", "이건 상관관계 아닌가?"
```

---

## 6. 안티패턴

- **데이터 덤프**: "여기 모든 데이터가 있습니다" → 인사이트 없음
- **결론 없는 발표**: 모든 것을 설명하고 결론 없이 끝남
- **청중 무시**: 경영진에게 기술적 세부사항 나열
- **차트만 보여주기**: 차트가 말하는 것을 설명해야 함
- **상관관계를 인과관계로**: "A가 증가하자 B도 증가" ≠ A 때문에 B
