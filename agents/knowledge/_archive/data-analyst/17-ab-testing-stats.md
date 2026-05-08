# A/B Testing Statistics

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/ab-testing-stats

---

## 1. A/B 테스트 설계

```
실험 설계 체크리스트:

[ ] 가설 명확히: "B 버전이 CTA 버튼 색상을 빨간색으로 변경하면
                  클릭률이 15% 이상 증가할 것이다"
[ ] 지표 결정: Primary KPI (클릭률), Guardrail (이탈률)
[ ] 샘플 크기 계산 (사전 파워 분석)
[ ] 실험 기간 결정 (최소 1주 이상, 전체 사이클 포함)
[ ] 무작위 배정: 사용자 ID 기반, 동일 사용자는 항상 같은 그룹
[ ] AA 테스트: 실험 시작 전 두 그룹이 동일한지 확인
```

---

## 2. 샘플 크기 계산

```python
from scipy import stats
import numpy as np

def calculate_sample_size(
    baseline_rate: float,   # 현재 전환율 (예: 0.05 = 5%)
    min_effect: float,      # 탐지하고 싶은 최소 효과 (예: 0.15 = 15% 상대적 개선)
    alpha: float = 0.05,    # 1종 오류 (유의수준)
    power: float = 0.80,    # 검정력 (1 - 2종 오류)
) -> int:
    p1 = baseline_rate
    p2 = baseline_rate * (1 + min_effect)  # 15% 상대적 개선

    # 효과 크기
    effect_size = abs(p2 - p1) / np.sqrt((p1*(1-p1) + p2*(1-p2)) / 2)

    # 각 그룹 필요 샘플 수
    n = stats.norm.isf(alpha/2) + stats.norm.isf(1 - power)
    n = (n / effect_size) ** 2

    return int(np.ceil(n))

# 예시
n = calculate_sample_size(
    baseline_rate=0.05,  # 기존 전환율 5%
    min_effect=0.20,     # 20% 상대적 개선 탐지 (5% → 6%)
    alpha=0.05,
    power=0.80,
)
print(f"각 그룹 필요 샘플 수: {n:,}명")
```

---

## 3. 통계적 유의성 검정

```python
from scipy import stats
import pandas as pd

def ab_test_proportions(
    control_conversions: int,
    control_total: int,
    treatment_conversions: int,
    treatment_total: int,
    alpha: float = 0.05,
) -> dict:
    """이항 비율 Z-검정"""
    p_control   = control_conversions / control_total
    p_treatment = treatment_conversions / treatment_total

    # 풀링된 비율
    p_pool = (control_conversions + treatment_conversions) / (control_total + treatment_total)

    # Z 통계량
    se = np.sqrt(p_pool * (1 - p_pool) * (1/control_total + 1/treatment_total))
    z = (p_treatment - p_control) / se
    p_value = 2 * (1 - stats.norm.cdf(abs(z)))

    # 신뢰 구간
    ci_diff = stats.norm.isf(alpha/2) * np.sqrt(
        p_control*(1-p_control)/control_total + p_treatment*(1-p_treatment)/treatment_total
    )

    return {
        'control_rate':   round(p_control, 4),
        'treatment_rate': round(p_treatment, 4),
        'relative_uplift': round((p_treatment - p_control) / p_control * 100, 1),
        'z_statistic':    round(z, 3),
        'p_value':        round(p_value, 4),
        'significant':    p_value < alpha,
        'ci_lower':       round((p_treatment - p_control) - ci_diff, 4),
        'ci_upper':       round((p_treatment - p_control) + ci_diff, 4),
    }

result = ab_test_proportions(
    control_conversions=450,   control_total=9000,
    treatment_conversions=540, treatment_total=9000,
)
print(result)
# {'control_rate': 0.05, 'treatment_rate': 0.06, 'relative_uplift': 20.0,
#  'p_value': 0.0015, 'significant': True, ...}
```

---

## 4. 다중 검정 문제

```python
# Bonferroni 보정 — 복수 지표 동시 검정 시
alpha = 0.05
num_tests = 5  # 5개 지표 동시 검정
corrected_alpha = alpha / num_tests  # 0.01

# Benjamini-Hochberg (FDR 제어) — 덜 보수적
from statsmodels.stats.multitest import multipletests

p_values = [0.001, 0.008, 0.039, 0.041, 0.3]
reject, pvals_corrected, _, _ = multipletests(p_values, method='fdr_bh')
```

---

## 5. 베이지안 A/B 테스트

```python
import numpy as np

def bayesian_ab_test(
    control_successes: int, control_total: int,
    treatment_successes: int, treatment_total: int,
    n_samples: int = 100_000,
) -> dict:
    """베타 분포 기반 베이지안 테스트"""
    # Beta 사후 분포 (Prior: Beta(1,1) = 균등 분포)
    control_samples = np.random.beta(
        control_successes + 1, control_total - control_successes + 1, n_samples
    )
    treatment_samples = np.random.beta(
        treatment_successes + 1, treatment_total - treatment_successes + 1, n_samples
    )

    prob_treatment_better = (treatment_samples > control_samples).mean()
    expected_uplift = (treatment_samples - control_samples).mean()

    return {
        'prob_treatment_better': round(prob_treatment_better, 3),
        'expected_uplift': round(expected_uplift, 4),
        'decision': '실험군 채택' if prob_treatment_better > 0.95 else '추가 데이터 필요',
    }
```

---

## 6. 안티패턴

- **피킹(Peeking)**: 중간에 결과 보고 조기 종료 → p-value 인플레이션
- **샘플 크기 미계산**: 작은 샘플로 결론 → 통계적 파워 부족
- **단일 지표만**: Primary + Guardrail 지표 같이 모니터링
- **1회 검정**: 재현 없이 단 한 번 실험 결과로 배포
- **SRM 무시**: Sample Ratio Mismatch — 그룹 배정 비율 의도치 않게 틀어짐
