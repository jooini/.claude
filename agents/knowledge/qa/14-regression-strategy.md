# Regression Strategy

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/regression-strategy

---

## 1. 회귀 테스트란

새 변경이 기존 기능을 망가뜨리지 않았는지 검증.
변경 후 매 릴리스마다 실행.

---

## 2. 회귀 테스트 범위 전략

### 위험 기반 선택 (Risk-Based)

```
변경 영향 범위 분석 → 관련 테스트만 실행

변경된 코드:
  payment.service.ts
  └── 직접 의존: order.service.ts
      └── 간접 의존: notification.service.ts

회귀 테스트 대상:
  [필수] 결제 관련 모든 테스트
  [필수] 주문 관련 테스트
  [권장] 알림 관련 테스트
  [선택] 관련 없는 사용자 프로필 테스트
```

### 우선순위 기반

```
P1 회귀 (항상 실행):
  - 로그인/회원가입
  - 결제 플로우
  - 핵심 CRUD

P2 회귀 (주요 릴리스마다):
  - 검색, 필터
  - 알림
  - 프로필 관리

P3 회귀 (스프린트마다):
  - 부가 기능
  - 관리자 기능
```

---

## 3. 자동화 회귀 스위트

```ts
// 회귀 테스트 태깅
describe('결제 [regression] [critical]', () => {
  it('[P1] 신규 카드로 결제 성공', ...)
  it('[P1] 저장된 카드로 결제 성공', ...)
  it('[P2] 쿠폰 적용 후 결제', ...)
})

// 태그별 실행
// npx jest --testNamePattern="\[P1\]"
// npx playwright test --grep "@regression"
```

```yaml
# CI 회귀 전략
on:
  pull_request:
    branches: [main]

jobs:
  # PR마다 빠른 회귀 (핵심만, 5분)
  quick-regression:
    runs-on: ubuntu-latest
    steps:
      - run: npm test -- --testPathPattern="critical"

  # main 머지 후 전체 회귀 (30분)
  full-regression:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - run: npm test -- --coverage
      - run: npx playwright test
```

---

## 4. 회귀 테스트 유지 관리

```
추가 기준:
  ✅ 새 기능의 Happy Path
  ✅ 버그 수정 시 재발 방지 테스트
  ✅ 비즈니스 크리티컬 시나리오

제거 기준:
  ❌ 더 이상 존재하지 않는 기능
  ❌ 다른 테스트로 완전히 커버됨
  ❌ 지속적으로 Flaky한 테스트 (수정 후 재추가)

주기적 검토 (분기):
  - 불필요한 테스트 제거
  - 중복 테스트 통합
  - 느린 테스트 최적화
```

---

## 5. Smoke Test vs Regression Test

```
Smoke Test (배포 직후, 5~10분)
  핵심 기능만 빠르게 확인
  "서비스가 살아있는가?"
  → 실패 시 즉시 롤백

Sanity Test (릴리스 후, 15~30분)
  변경된 기능 중심 검증
  "변경한 것이 의도대로 동작하는가?"

Regression Test (릴리스 전, 30분~2시간)
  전체 기능 검증
  "기존 기능이 망가지지 않았는가?"
```

---

## 6. Flaky Test 관리

```ts
// Flaky Test 격리
// jest.config.ts
testPathIgnorePatterns: [
  '/e2e/flaky/',  // 수정 전 격리
]

// 재시도 설정
jest.retryTimes(3)  // 최대 3번 재시도

// Playwright
retries: process.env.CI ? 2 : 0

// Flaky 원인 분석
// - 타이밍 의존 (waitForTimeout → waitForSelector)
// - 테스트 간 상태 공유 (DB 정리 미흡)
// - 외부 서비스 의존 (MSW로 Mock)
// - 랜덤 데이터 사용 (고정값으로 교체)
```

---

## 7. 안티패턴

- **모든 것을 회귀로**: 비용 대비 효율 고려 — 위험 기반 선택
- **Flaky Test 방치**: 신뢰도 저하 → 모든 팀이 무시하게 됨
- **회귀 스위트 업데이트 안 함**: 기능 삭제 후에도 테스트 남아 있음
- **회귀 실패 무시 배포**: 반드시 원인 파악 후 배포
- **수동 회귀만 의존**: 자동화로 반복 작업 제거
