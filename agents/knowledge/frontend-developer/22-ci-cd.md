# CI/CD

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/ci-cd

---

## 1. CI/CD 파이프라인 구조

```
PR 생성
  └── CI (자동)
        ├── lint
        ├── type-check
        ├── unit/integration test
        ├── build
        └── preview deploy (Vercel)

main 머지
  └── CD (자동)
        ├── build
        ├── E2E test
        └── production deploy
```

---

## 2. GitHub Actions CI

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main, develop]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Type check
        run: npm run type-check

      - name: Lint
        run: npm run lint

      - name: Unit tests
        run: npm run test -- --coverage

      - name: Build
        run: npm run build
        env:
          NEXT_PUBLIC_API_URL: ${{ secrets.NEXT_PUBLIC_API_URL }}

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
```

---

## 3. E2E 테스트 CI

```yaml
# .github/workflows/e2e.yml
name: E2E

on:
  push:
    branches: [main]

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Install Playwright
        run: npx playwright install --with-deps chromium

      - name: Build
        run: npm run build

      - name: Run E2E
        run: npx playwright test
        env:
          BASE_URL: http://localhost:3000
          TEST_USER_EMAIL: ${{ secrets.TEST_USER_EMAIL }}
          TEST_USER_PASSWORD: ${{ secrets.TEST_USER_PASSWORD }}

      - name: Upload Playwright report
        uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: playwright-report/
```

---

## 4. Vercel 배포 설정

```json
// vercel.json
{
  "buildCommand": "npm run build",
  "framework": "nextjs",
  "regions": ["icn1"],  // 서울 리전
  "env": {
    "NODE_ENV": "production"
  },
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "X-Content-Type-Options", "value": "nosniff" }
      ]
    }
  ],
  "rewrites": [
    { "source": "/api/:path*", "destination": "https://api.example.com/:path*" }
  ]
}
```

---

## 5. 브랜치 전략

```
main        ← 운영 배포
  └── develop ← 스테이징 배포
        ├── feature/login-redesign
        ├── feature/payment-v2
        └── fix/header-overflow
```

**PR 규칙:**
- 직접 main 푸시 금지
- PR = CI 통과 필수
- 리뷰어 1명 이상 승인 필수
- 스쿼시 머지 권장 (히스토리 정리)

---

## 6. 환경 관리

```
운영 (main)      → production 환경 변수
스테이징 (develop) → staging 환경 변수
PR 프리뷰         → preview 환경 변수
```

```bash
# Vercel CLI로 환경 변수 설정
vercel env add DATABASE_URL production
vercel env add DATABASE_URL preview
vercel env add DATABASE_URL development
```

---

## 7. 배포 안전장치

```yaml
# 카나리 배포 — 일부 트래픽만 새 버전으로
# Vercel Edge Config 또는 Feature Flags 활용

# 자동 롤백 조건
- E2E 실패 → 배포 중단
- 에러율 임계치 초과 → 이전 버전으로 롤백
- Lighthouse 점수 하락 → 경고 + 수동 확인
```

---

## 8. 안티패턴

- **테스트 없는 머지**: CI 통과 필수 규칙
- **시크릿 코드에 하드코딩**: GitHub Secrets 사용
- **배포 전 테스트 없음**: 스테이징 → E2E → 운영
- **롤백 계획 없음**: 배포마다 롤백 방법 확인
- **긴 CI 파이프라인**: 10분 넘으면 병렬화 고려
