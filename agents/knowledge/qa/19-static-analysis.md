# Static Analysis

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/static-analysis

---

## 1. 정적 분석이란

코드를 실행하지 않고 소스 코드를 분석해 버그, 보안 취약점, 코드 품질 문제를 탐지.

**장점:** 빠름, 일관성, 자동화 가능, 코드 리뷰 전 사전 탐지

---

## 2. ESLint 설정

```json
// .eslintrc
{
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:@typescript-eslint/recommended-requiring-type-checking",
    "plugin:security/recommended",
    "plugin:sonarjs/recommended"
  ],
  "rules": {
    // TypeScript
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": "error",
    "@typescript-eslint/explicit-function-return-type": "warn",
    "@typescript-eslint/no-floating-promises": "error",
    "@typescript-eslint/await-thenable": "error",

    // 보안
    "security/detect-object-injection": "error",
    "security/detect-non-literal-regexp": "warn",

    // 복잡도
    "complexity": ["warn", 10],
    "max-depth": ["warn", 4],
    "max-lines-per-function": ["warn", { "max": 50 }],

    // 코드 품질
    "sonarjs/cognitive-complexity": ["warn", 15],
    "sonarjs/no-duplicate-string": "warn",
    "no-console": "warn"
  }
}
```

---

## 3. SonarQube / SonarCloud

```yaml
# GitHub Actions — SonarCloud
- name: SonarCloud Scan
  uses: SonarSource/sonarcloud-github-action@master
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

# sonar-project.properties
sonar.projectKey=company_project
sonar.organization=company
sonar.sources=src
sonar.tests=test
sonar.javascript.lcov.reportPaths=coverage/lcov.info
sonar.typescript.tsconfigPath=tsconfig.json

# Quality Gate 기준
sonar.qualitygate.wait=true
# 기본 Quality Gate:
# - 신규 코드 커버리지 80% 이상
# - 신규 코드 중복 3% 이하
# - 버그 0개
# - 취약점 0개
# - Code Smell A등급
```

---

## 4. 코드 복잡도 측정

```ts
// 복잡도 예시
// Cyclomatic Complexity = 조건 분기 수 + 1

// 복잡도 1 (단순)
function add(a: number, b: number): number {
  return a + b
}

// 복잡도 6 (주의)
function processOrder(order: Order): string {
  if (!order) return 'invalid'             // +1
  if (order.status === 'cancelled') {      // +1
    return 'cancelled'
  }
  if (order.total > 100000) {              // +1
    if (order.user.isVip) {               // +1
      return 'vip-large-order'
    }
    return 'large-order'
  }
  for (const item of order.items) {       // +1
    if (item.stock === 0) {               // +1
      return 'out-of-stock'
    }
  }
  return 'processable'
}
// → 리팩토링 권장
```

---

## 5. 의존성 취약점 스캔

```bash
# npm audit
npm audit
npm audit --audit-level=high  # High 이상만

# Snyk
npx snyk test
npx snyk monitor  # 지속 모니터링

# GitHub Dependabot
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 10
    ignore:
      - dependency-name: "lodash"
        versions: ["4.x"]  # 특정 버전 제외
```

---

## 6. Pre-commit 훅

```bash
# .husky/pre-commit
#!/bin/sh
. "$(dirname "$0")/_/husky.sh"

echo "Running static analysis..."
npx lint-staged

# 커밋 전 타입 체크
npm run type-check

echo "Static analysis passed!"
```

```json
// package.json — lint-staged
{
  "lint-staged": {
    "*.{ts,tsx}": [
      "eslint --fix --max-warnings=0",
      "prettier --write"
    ],
    "*.{json,md,yml}": [
      "prettier --write"
    ]
  }
}
```

---

## 7. 안티패턴

- **경고 무시**: `// eslint-disable` 남발 → 진짜 문제 놓침
- **너무 많은 규칙**: 팀이 지키기 어려운 규칙 → 선별적 적용
- **CI에서만 실행**: Pre-commit으로 로컬에서 먼저 잡기
- **정적 분석 결과 방치**: Quality Gate 실패 무시 배포
