# Coverage Analysis

> 참조 링크: https://istanbul.js.org/, https://vitest.dev/guide/coverage.html, https://coverage.readthedocs.io/

---

## 1. 커버리지 유형

| 유형 | 설명 | 중요도 |
|------|------|--------|
| **Line** | 실행된 라인 비율 | 기본 |
| **Branch** | 조건문의 모든 분기 실행 여부 | 높음 |
| **Function** | 호출된 함수 비율 | 보통 |
| **Statement** | 실행된 구문 비율 | 기본 |

**Branch 커버리지**가 가장 의미있다. 라인 커버리지 100%여도 `if`의 한 분기만 테스트할 수 있다.

## 2. Node.js 커버리지 도구

### Jest 커버리지

```bash
# 커버리지 실행
npx jest --coverage

# 특정 파일만
npx jest --coverage --collectCoverageFrom='src/user/**/*.ts'

# 리포터 지정
npx jest --coverage --coverageReporters='text' --coverageReporters='lcov'
```

```typescript
// jest.config.ts
{
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.spec.ts',
    '!src/**/*.d.ts',
    '!src/main.ts',
    '!src/**/*.module.ts',
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80,
    },
    // 특정 디렉토리에 더 높은 기준
    './src/core/': {
      branches: 90,
      lines: 90,
    },
  },
  coverageReporters: ['text', 'text-summary', 'lcov', 'json'],
}
```

### Vitest 커버리지

```bash
# v8 프로바이더 (빠름)
npx vitest run --coverage --coverage.provider=v8

# istanbul 프로바이더 (정확)
npx vitest run --coverage --coverage.provider=istanbul
```

```typescript
// vitest.config.ts
{
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.test.ts', 'src/**/*.d.ts'],
      thresholds: {
        branches: 80,
        functions: 80,
        lines: 80,
        statements: 80,
      },
    },
  },
}
```

## 3. Python 커버리지

### pytest-cov

```bash
# 커버리지 실행
pytest --cov=src --cov-report=term-missing

# HTML 리포트
pytest --cov=src --cov-report=html

# XML (CI용)
pytest --cov=src --cov-report=xml

# 최소 기준 설정
pytest --cov=src --cov-fail-under=80

# 특정 파일 제외
pytest --cov=src --cov-config=.coveragerc
```

```ini
# .coveragerc 또는 pyproject.toml
[tool.coverage.run]
source = ["src"]
omit = [
    "*/tests/*",
    "*/migrations/*",
    "*/__init__.py",
]

[tool.coverage.report]
fail_under = 80
show_missing = true
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "if __name__ == .__main__.",
]
```

## 4. 커버리지 리포트 해석

### 텍스트 리포트

```
----------|---------|----------|---------|---------|-------------------
File      | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
----------|---------|----------|---------|---------|-------------------
All files |   85.71 |    75.00 |   90.00 |   85.71 |
 user.ts  |   80.00 |    66.67 |   85.71 |   80.00 | 45-52,78
 auth.ts  |   95.00 |    90.00 |  100.00 |   95.00 | 112
----------|---------|----------|---------|---------|-------------------
```

- **Uncovered Line #s**: 테스트되지 않은 라인 — 리뷰 시 이 라인을 확인
- **% Branch < % Lines**: 조건문 분기 테스트 부족 신호

### HTML 리포트

```bash
# 생성된 리포트 열기
open coverage/lcov-report/index.html  # macOS
xdg-open coverage/lcov-report/index.html  # Linux
```

## 5. 의미있는 커버리지 기준

### 권장 기준

| 영역 | 라인 | 브랜치 | 비고 |
|------|------|--------|------|
| 비즈니스 로직 (서비스) | 85%+ | 80%+ | 핵심 로직은 높게 |
| 유틸리티 함수 | 90%+ | 85%+ | 단순하고 테스트 쉬움 |
| 컨트롤러/라우터 | 70%+ | 70%+ | 통합 테스트로 보완 |
| 설정/부트스트랩 | 50%+ | — | 낮아도 OK |
| 마이그레이션 | — | — | 커버리지 불필요 |

### 커버리지 함정

- **100% = 버그 없음이 아님**: 라인은 실행되었지만 assertion이 부실할 수 있음
- **커버리지 타겟에만 집중하면**: 의미 없는 테스트로 숫자만 올리게 됨
- **복잡한 조건**: `if (a && b || c)` → 8가지 조합 중 2가지만 테스트해도 라인 커버리지 100%

## 6. 변경 기반 커버리지

새로 작성/수정된 코드의 커버리지만 측정:

```bash
# diff-cover: 변경 라인의 커버리지만 리포트
pip install diff-cover
diff-cover coverage.xml --compare-branch=main --fail-under=80

# Jest: 변경 파일 관련 테스트만
npx jest --changedSince=main --coverage
```

## 7. CI에서 커버리지 리포트

```yaml
# GitHub Actions
- name: Test with coverage
  run: npx jest --coverage --coverageReporters='json-summary'

- name: Coverage comment
  uses: davelosert/vitest-coverage-report-action@v2
  with:
    json-summary-path: coverage/coverage-summary.json
```
