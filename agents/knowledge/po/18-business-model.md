# Business Model

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-po/business-model

---

## SaaS Business Model

**핵심 특성:**
- **구독 기반 수익**: MRR / ARR
- **높은 Gross Margin**: 70-90% (소프트웨어는 복제 비용이 거의 없음)
- **예측 가능한 매출**: 구독 → 미래 매출 예측 가능
- **확장 수익(Expansion)**: 기존 고객에서 추가 매출 (upsell, cross-sell)

### SaaS 핵심 지표

```
MRR = 월간 반복 매출
ARR = MRR × 12

Net Revenue Retention (NRR)
  = (시작 MRR + Expansion - Churn - Contraction) / 시작 MRR

Gross Revenue Retention (GRR)
  = (시작 MRR - Churn - Contraction) / 시작 MRR

좋은 SaaS 기준:
  NRR > 120% (확장이 이탈을 넘어섬)
  GRR > 90%
  Gross Margin > 70%
  CAC Payback < 12개월
```

### SaaS Growth 공식

```
ARR Growth = New ARR + Expansion ARR - Churned ARR

New ARR: 신규 고객
Expansion ARR: 기존 고객 업셀/크로스셀
Churned ARR: 이탈 고객
```

---

## B2B vs B2C vs B2B2C

| | B2B | B2C | B2B2C |
|--|-----|-----|-------|
| **고객** | 기업 | 개인 | 기업을 통해 개인 |
| **의사결정** | 복잡 (다수 관여) | 단순 (개인) | 중간 |
| **세일즈 사이클** | 길다 (월-년) | 짧다 (분-일) | 다양 |
| **ACV** | 높음 ($5K-$1M+) | 낮음 ($5-$200) | 중간 |
| **Churn** | 낮음 (2-5%/년) | 높음 (5-10%/월) | 중간 |
| **GTM** | Sales-led 또는 PLG | Marketing-led | Partnership |
| **성공 지표** | ARR, NRR, ACV | MAU, Conversion, LTV | GMV, Take rate |

**B2B 특수성:**
- Multi-stakeholder: 사용자 ≠ 구매자 ≠ 결정자
- Enterprise sales: RFP, 보안 심사, 계약 협상
- Integration: 기존 시스템과의 연동 필수
- SLA: 가용성, 지원 수준 보장 필요

---

## Revenue Models

### Subscription (구독)

```
Free → Pro ($19/월) → Business ($49/월) → Enterprise (협상)

장점: 예측 가능, 안정적
단점: 초기 수익화 느림
적합: 정기적으로 사용하는 SaaS
```

### Freemium

```
무료 (제한된 기능)
  └── 한계에 도달하면 유료로 전환

전환 트리거:
  - 기능 제한 (파일 수, 프로젝트 수)
  - 용량 제한 (저장 공간)
  - 협업 제한 (팀원 수)
  - 고급 기능 (분석, 자동화)

전환율 벤치마크: 2-5% (Freemium → Paid)
```

### Usage-Based (사용량 기반)

```
예: Stripe (거래 금액의  %), AWS (사용한 만큼), OpenAI (토큰 수)

장점: 성장과 매출이 자연스럽게 연동
단점: 매출 예측 어려움
적합: 인프라, API, 처리량 기반 서비스
```

### Marketplace / Transaction Fee

```
거래 금액의 X% 수수료

예: Airbnb 3% + 6-12%, Shopify 0.5-2%

장점: 고객 성공 = 우리 성공 (정렬)
단점: 규모가 커지면 수수료 우회 시도
```

### Hybrid Model

대부분의 성숙한 SaaS는 복합 모델:

```
Base subscription + Usage overage
  예: $99/월 기본 + 1,000 API call 초과 시 $0.01/call

Seat-based + Platform fee
  예: $50/user/월 + $500/월 플랫폼 기본료
```

---

## Unit Economics

### LTV / CAC 비율

```
LTV = ARPU × Gross Margin × (1 / Churn Rate)
CAC = 영업+마케팅 비용 / 신규 고객 수

좋은 비율:
  LTV:CAC > 3:1 (최소)
  LTV:CAC > 5:1 (건강)
  
CAC Payback < 12개월 (소비자)
CAC Payback < 18개월 (기업)
```

### Cohort별 Unit Economics

```
Month 0: -$500 (CAC)
Month 6: 손익분기점
Month 12: +$200 누적 이익
Month 24: +$1,000 누적 이익 (LTV)

→ CAC Payback = 6개월
→ 24개월 LTV = $1,000
→ LTV:CAC = 2:1 (개선 필요)
```

---

## Pricing Strategy

### 가격 결정 기준

1. **Cost-based**: 원가 + 마진 → SaaS에 부적합
2. **Competitor-based**: 경쟁사 대비 포지셔닝 → 차별화 어려움
3. **Value-based**: 고객이 얻는 가치에 기반 → 권장

### Value-based Pricing 프로세스

```
1. 고객이 우리 제품으로 얻는 가치 정량화
   예: "시간 절약 10시간/주 × $50/시간 = $500/주 = $2,000/월 가치"

2. 그 가치의 일부를 가격으로 설정
   예: 가치의 10-20% → $200-400/월

3. 세그먼트별 차별화
   소규모팀 < 중간팀 < 엔터프라이즈
```

### Pricing Page 모범 사례

- 3-4개 플랜 (선택 마비 방지)
- 가장 인기 있는 플랜 강조
- 연간 결제 할인 (20%) 유도
- 엔터프라이즈는 "문의하기"로 별도 처리
- Free trial > Freemium (전환율이 높음)
