# Growth

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-po/growth

---

## Growth Hacking 프레임워크

### Growth Loop vs Funnel

전통적 퍼널은 선형적이지만, 실제 성장은 **루프**로 작동한다.

```
Funnel (선형):
  Acquisition → Activation → Retention → Revenue
  (각 단계에서 탈락, 다시 맨 위부터)

Growth Loop (순환):
  New User → Core Action → Output → New User
  (아웃풋이 다시 인풋이 됨)
```

### Growth Loop 유형

**1. Viral Loop**
```
사용자 A가 제품 사용 → 다른 사람에게 노출/초대
→ 사용자 B가 가입 → 사용자 B도 노출/초대 → ...
```
예시: Slack(팀원 초대 → 팀 사용 → 다른 팀 전파), Figma(디자인 공유 → 코멘트 → 가입)

**2. Content Loop**
- Notion: 템플릿 공유 → 검색 유입 → 가입

**3. Paid Loop**
- LTV > CAC여야 작동

---

## Product-Led Growth (PLG)

**제품 자체가 acquisition, activation, retention, expansion의 주요 드라이버**인 성장 전략. Sales/Marketing이 아닌 제품 경험이 성장을 이끈다.

### PLG 핵심 원칙

1. **End user가 먼저**: C-level이 아닌 실제 사용자부터 시작
2. **Self-serve**: 영업 없이 가입, 사용, 결제 가능
3. **Time to Value 최소화**: 가입 후 빠르게 가치 경험
4. **Viral by design**: 혼자 쓰면 좋고, 같이 쓰면 더 좋은 제품

### PLG Flywheel

1. **Evaluator** — 무료로 제품 체험
2. **Beginner** — 핵심 기능 사용 시작
3. **Regular** — 습관적 사용 (Aha moment 경험)
4. **Champion** — 팀에 추천, 확산
5. **Expansion** — 더 많은 기능/시트 구매

### PLG 핵심 지표

| 지표 | 설명 | 목표 |
|------|------|------|
| TTV (Time to Value) | 가입→가치 경험 | <5분 |
| Activation Rate | 핵심 행동 수행 비율 | >40% |
| PQL (Product Qualified Lead) | 제품 사용 기반 적격 리드 | 정의 필요 |
| Natural rate of growth | Organic + viral 성장률 | >60% of total |

---

## AARRR Pirate Metrics

Dave McClure의 스타트업 성장 프레임워크:

| 단계 | 질문 | 핵심 지표 |
|------|------|---------|
| **Acquisition** | 어떻게 유입되는가? | CAC, 채널별 전환율 |
| **Activation** | 첫 경험이 좋은가? | Activation rate, TTV |
| **Retention** | 다시 돌아오는가? | D1/D7/D30 retention |
| **Revenue** | 돈을 내는가? | Conversion rate, ARPU |
| **Referral** | 다른 사람을 데려오는가? | Viral coefficient (K factor) |

### K factor (바이럴 계수)

```
K = 초대 수 × 전환율

K > 1: 폭발적 성장 (각 사용자가 1명 이상 데려옴)
K = 1: 정체
K < 1: 자연 감소

예시: 사용자 1명이 평균 5명 초대, 그 중 20%가 가입
K = 5 × 0.2 = 1.0 (정체 구간)
```

---

## Retention 전략

### Retention 곡선 해석

```
Retention (%)
100% |●
     |  ●
 50% |    ●●
     |       ●●●●
  0% |_______________ Time
      D1 D7 D30 D90

- 급격한 초기 감소 → Activation 문제
- 바닥이 0에 수렴 → Product-market fit 없음
- 바닥이 수평 (스마일 커브) → PMF 있음
```

### Retention 개선 전략

**초기 Retention (D1-D7):**
- 온보딩 최적화
- Aha moment 앞당기기
- 빈 상태(Empty state) 개선

**중기 Retention (D7-D30):**
- 습관 형성 루프
- 푸시 알림/이메일 넛지
- 진행 상황 표시

**장기 Retention (D30+):**
- 데이터 누적 (전환 비용 상승)
- 팀/소셜 기능 (네트워크 효과)
- 정기적 가치 제공

---

## Activation 최적화

### Aha Moment 찾기

**방법:**
1. retained 사용자 vs churned 사용자 비교
2. 어떤 행동에서 차이가 나는가?

```
예시 분석:
  D30 retained: 첫 주에 평균 3개 프로젝트 생성
  D30 churned: 첫 주에 평균 0.5개 프로젝트 생성

→ Aha Moment: 첫 주에 3개 프로젝트 생성
→ Activation 목표: 가입 후 7일 내 3개 프로젝트 생성
```

### Onboarding 체크리스트

```
가입 직후:
  □ 환영 메시지 (사람처럼)
  □ 빈 상태 → 예시 데이터 자동 생성
  □ 첫 번째 핵심 행동으로 즉시 유도

첫 세션:
  □ 3분 내 Aha Moment 경험
  □ 진행 상황 표시 (체크리스트)
  □ 첫 성공 경험 축하

첫 주:
  □ 이메일/알림 넛지 (적절한 시점)
  □ 고급 기능 점진적 소개
  □ 팀원 초대 유도
```

---

## Growth Experiment 운영

### Growth 실험 프로세스

```
1. 분석 (Data) → 병목 구간 파악
2. 가설 → "X를 바꾸면 Y가 Z% 개선될 것이다"
3. 우선순위 → ICE 스코어링
4. 실험 → A/B 테스트 또는 빠른 출시
5. 분석 → 결과 측정
6. 반복 → 학습 기반으로 다음 실험
```

### Growth vs Product 팀 구분

| | Growth 팀 | Product 팀 |
|--|-----------|-----------|
| 목표 | 빠른 실험, 지표 이동 | 장기 가치, 사용자 경험 |
| 속도 | 빠름 (주 단위) | 느림 (분기 단위) |
| 범위 | 퍼널의 특정 단계 | 핵심 제품 경험 |
| 방식 | A/B 테스트 중심 | Discovery + Delivery |
