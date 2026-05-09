# Data Validation

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-data-analyst/data-validation

---

## 1. 검증 유형

```
스키마 검증: 컬럼 존재, 데이터 타입
범위 검증: 최소값, 최대값
형식 검증: 이메일, 전화번호, URL
참조 무결성: FK 관계 유효성
비즈니스 규칙: 환불금액 ≤ 주문금액
통계적 검증: 분포 이상, 급격한 변화
```

---

## 2. Pydantic 스키마 검증

```python
from pydantic import BaseModel, validator, Field
from typing import Optional
from datetime import datetime
from enum import Enum

class OrderStatus(str, Enum):
    PENDING   = 'pending'
    COMPLETED = 'completed'
    CANCELLED = 'cancelled'
    REFUNDED  = 'refunded'

class Order(BaseModel):
    order_id:   str
    user_id:    str
    amount:     float = Field(gt=0, le=10_000_000)
    status:     OrderStatus
    created_at: datetime
    refund_amount: Optional[float] = None

    @validator('refund_amount')
    def refund_not_exceed_amount(cls, v, values):
        if v is not None and v > values.get('amount', 0):
            raise ValueError('환불금액이 주문금액을 초과할 수 없습니다')
        return v

    @validator('created_at')
    def not_future_date(cls, v):
        if v > datetime.now():
            raise ValueError('미래 날짜는 허용되지 않습니다')
        return v

# ETL에서 사용
def validate_orders(raw_data: list[dict]) -> tuple[list[Order], list[dict]]:
    valid, invalid = [], []
    for row in raw_data:
        try:
            valid.append(Order(**row))
        except ValidationError as e:
            invalid.append({'row': row, 'errors': e.errors()})
    return valid, invalid
```

---

## 3. dbt 테스트

```yaml
# schema.yml
models:
  - name: fct_orders
    tests:
      - dbt_utils.expression_is_true:
          expression: "refund_amount <= amount OR refund_amount IS NULL"
          name: refund_not_exceed_amount

      - dbt_utils.recency:
          datepart: hour
          field: created_at
          interval: 25  # 25시간 내 데이터 없으면 실패

      - dbt_utils.equal_rowcount:
          compare_model: ref('stg_orders')  # 소스와 행 수 일치

    columns:
      - name: order_id
        tests:
          - not_null
          - unique

      - name: amount
        tests:
          - dbt_utils.expression_is_true:
              expression: "> 0"
```

---

## 4. 통계적 검증

```python
import pandas as pd
from scipy import stats

def validate_distribution(new_data: pd.Series, reference_data: pd.Series,
                          p_threshold: float = 0.05) -> dict:
    """Kolmogorov-Smirnov 검정으로 분포 변화 탐지"""
    statistic, p_value = stats.ks_2samp(reference_data, new_data)

    return {
        'passed': p_value > p_threshold,
        'p_value': p_value,
        'message': '분포 일치' if p_value > p_threshold else f'분포 이상 탐지 (p={p_value:.4f})'
    }

def validate_volume(today_count: int, historical_avg: float,
                    tolerance: float = 0.3) -> dict:
    """볼륨 이상 탐지 (평균 대비 ±30%)"""
    ratio = today_count / historical_avg
    passed = abs(ratio - 1) <= tolerance

    return {
        'passed': passed,
        'ratio': ratio,
        'message': f'볼륨 정상 ({ratio:.1%})' if passed else f'볼륨 이상! ({ratio:.1%})'
    }
```

---

## 5. 검증 결과 리포트

```python
class ValidationReport:
    def __init__(self):
        self.checks = []

    def add_check(self, name: str, passed: bool, details: str = ''):
        self.checks.append({'name': name, 'passed': passed, 'details': details})

    @property
    def all_passed(self) -> bool:
        return all(c['passed'] for c in self.checks)

    def summary(self) -> str:
        total = len(self.checks)
        passed = sum(1 for c in self.checks if c['passed'])
        status = '✅ PASS' if self.all_passed else '❌ FAIL'
        lines = [f"{status} — {passed}/{total} checks passed"]
        for c in self.checks:
            icon = '✅' if c['passed'] else '❌'
            lines.append(f"  {icon} {c['name']}: {c['details']}")
        return '\n'.join(lines)
```

---

## 6. 안티패턴

- **파이프라인 끝에서만 검증**: 소스, 변환 단계마다 검증
- **검증 실패 무시 계속 진행**: 이후 분석이 오염됨
- **하드코딩된 임계값**: 비즈니스 맥락에 따라 동적으로
- **검증 이력 없음**: "언제부터 품질 문제가 있었나?" 파악 불가
- **검증만 하고 수정 없음**: 검증 → 알림 → 대응 전체 흐름 필요
