# A/B Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-po/ab-testing

---

## A/B 테스트란?

두 가지 이상의 변형(Variant)을 실제 사용자에게 동시에 노출하여, 어떤 것이 더 나은 결과를 만드는지 **통계적으로 검증**하는 방법.

---

## A/B 테스트 설계

### 1. 가설 수립

```
현재 상태: [baseline 데이터]
변경 사항: [무엇을 바꾸는가]
기대 효과: [어떤 지표가 어떻게 변할 것인가]
측정 지표: [primary metric + secondary + guardrail]
```

예시:
```
현재 상태: 가입 → 첫 프로젝트 생성 전환율 30%
변경 사항: 가입 직후 프로젝트 템플릿 선택 화면 추가
기대 효과: 전환율 30% → 40%
Primary metric: 첫 프로젝트 생성 전환율
Secondary: 7일 retention
Guardrail: 가입 완료율 (저하되면 안 됨)
```

### 2. 변수 설정

| 요소 | 설명 |
|------|------|
| **Independent variable** | 우리가 변경하는 것 (UI, 기능, 카피 등) |
| **Dependent variable** | 측정하는 결과 (전환율, 클릭률 등) |
| **Control** | 현재 버전 (A) |
| **Treatment** | 변경된 버전 (B, C...) |
| **Confounding variables** | 결과에 영향을 주는 외부 요인 (시즌, 이벤트) |

### 3. Primary / Secondary / Guardrail Metrics

```
Primary: 실험의 핵심 성공 지표 (1개)
  → "이 지표가 개선되면 성공"

Secondary: 추가 관찰 지표 (2-3개)
  → "함께 개선되면 더 좋다"

Guardrail: 악화되면 안 되는 지표 (1-2개)
  → "이 지표가 떨어지면 실험 중단"
```

---

## 통계적 유의성

### 핵심 개념

| 개념 | 설명 | 기준값 |
|------|------|--------|
| **p-value** | 차이가 우연일 확률 | <0.05 (95% 신뢰도) |
| **Statistical significance** | 결과가 우연이 아닌 정도 | 95% confidence |
| **Statistical power** | 실제 차이를 감지할 확률 | 80% 이상 |
| **MDE** | 감지하려는 최소 차이 | 비즈니스 의미 있는 수준 |
| **Effect size** | 실제 차이 크기 | 클수록 적은 샘플 필요 |

### Sample Size 계산

```
필요 조건:
- Baseline conversion rate
- Minimum Detectable Effect (MDE)
- Statistical significance (보통 95%)
- Statistical power (보통 80%)

예시:
Baseline: 10% conversion
MDE: 10% relative (10% → 11%)
Significance: 95%, Power: 80%

→ 필요 샘플: ~14,700 per variant (총 ~29,400)
→ 일 트래픽 1,000이면 ~30일 필요
```

### 실험 기간 결정

```
최소 기간 = 필요 샘플 ÷ 일 트래픽
+ 최소 1-2주 (요일별 편차 고려)
+ 참여 후 전환까지 걸리는 시간 (lagging effect)
```

**주의:**
- 2주 미만 실험은 요일 편차로 왜곡 위험
- 결과가 "보기 좋아서" 조기 종료 금지 (peeking problem)

---

## Multi-Armed Bandit

### A/B 테스트 vs Bandit

| | A/B 테스트 | Multi-Armed Bandit |
|--|-----------|-------------------|
| 트래픽 분배 | 고정 (50/50) | 동적 (성과에 따라 조정) |
| 목적 | 학습 | 최적화 |
| 기간 | 고정 | 가변 |
| 적합한 상황 | 명확한 학습 필요 | 기회비용 최소화 필요 |

---

## Feature Flag 기반 실험

### Feature Flag 활용 패턴

```
1. Kill Switch      → 문제 발생 시 기능 즉시 비활성화
2. Gradual Rollout  → 1% → 5% → 25% → 50% → 100% 점진적 확대
3. A/B Test         → flag ON/OFF로 실험 그룹 분리
4. Beta Access      → 특정 사용자/조직에만 기능 공개
5. Ops Toggle       → 운영 환경에서 기능 ON/OFF
```

**도구:** LaunchDarkly, Unleash, Flagsmith / PostHog, Amplitude (분석 통합)

---

## 실험 결과 해석

### 의사결정 매트릭스

| Primary ↑ | Guardrail 유지 | 결정 |
|-----------|--------------|------|
| 통계적 유의 | ✅ | 🟢 출시 |
| 통계적 유의 | ❌ 악화 | 🟡 재검토 — trade-off 분석 |
| 유의하지 않음 | ✅ | 🔴 실패 — 학습 정리 |
| 유의하지 않음 | ❌ | 🔴 즉시 중단 |

### 결과 해석 시 주의사항

1. **Simpson's Paradox**: 전체에서 A가 나은데 세그먼트별론 B가 나을 수 있다 → 세그먼트 분석 필수
2. **Novelty Effect**: 새로운 것에 대한 일시적 관심 → 2주 이상 실행
3. **Primacy Effect**: 기존 사용자의 변화 저항 → 신규 사용자 코호트만 분석
4. **Multiple Testing**: 여러 지표를 동시에 보면 하나쯤은 우연히 유의
5. **Underpowered Tests**: 샘플이 부족하면 유의하지 않음 ≠ 차이 없음

### 실험 결과 문서 템플릿

```markdown
## Experiment Report: [실험명]

### 요약
- **결과**: 🟢 성공 / 🟡 부분 성공 / 🔴 실패
- **Primary metric**: +X% (p=0.0X, 95% CI: [Y%, Z%])
- **결정**: 전체 출시 / 재실험 / 종료

### 결과
| 지표 | Control | Treatment | Change | p-value |
|------|---------|-----------|--------|---------|
| Primary | X% | Y% | +Z% | 0.0X |
| Guardrail | ... | ... | ... | ... |

### 세그먼트 분석
| 세그먼트 | Control | Treatment | 차이 |
|---------|---------|-----------|------|
| 신규 사용자 | ... | ... | ... |
| Mobile | ... | ... | ... |

### 학습
1. [핵심 인사이트 1]

### 다음 스텝
- [구체적 행동]
```

---

## 실험 문화 구축

### 실험 문화의 원칙

1. **실패 = 학습**: 가설이 틀린 것도 성공 (학습했으니까)
2. **데이터 > 직급**: "이사님이 좋아하실 것 같다"보다 "데이터가 보여준다"
3. **작고 빠르게**: 3개월 프로젝트보다 2주 실험
4. **모든 기능은 가설**: 확신이 있어도 측정하고 검증
5. **공유**: 성공/실패 모두 팀 전체와 공유

### 실험 Cadence

- **주간**: 1-2개 실험 진행 중
- **월간**: 실험 결과 리뷰 미팅
- **분기**: 실험에서 배운 것 요약, 다음 분기 실험 방향
