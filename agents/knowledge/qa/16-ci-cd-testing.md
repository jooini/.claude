# CI/CD Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/ci-cd-testing

---

## 1. CI/CD 테스트 파이프라인

```
PR 생성
  └── 빠른 피드백 (5분 이내)
        ├── lint + type-check
        ├── unit test
        └── integration test (핵심)

main 머지
  └── 완전한 검증 (30분)
        ├── 전체 unit/integration test
        ├── E2E smoke test
        └── staging 배포

스테이징 배포 후
  └── 전체 E2E + 회귀 테스트 (1~2시간)

운영 배포 승인 조건
  └── 모든 테스트 통과 + 수동 QA 승인
```

---

## 2. GitHub Actions 설정

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main, develop]

jobs:
  fast-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci

      - name: Lint & Type Check
        run: |
          npm run lint
          npm run type-check

      - name: Unit Tests
        run: npm test -- --coverage --passWithNoTests
        env:
          NODE_ENV: test

      - name: Upload Coverage
        uses: codecov/codecov-action@v4

  integration-tests:
    runs-on: ubuntu-latest
    needs: fast-checks
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-retries 5
      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 5s

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci

      - name: Run Migrations
        run: npm run migration:run
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/testdb

      - name: Integration Tests
        run: npm run test:integration
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/testdb
          REDIS_URL: redis://localhost:6379

  e2e-smoke:
    runs-on: ubuntu-latest
    needs: integration-tests
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npx playwright install --with-deps chromium

      - name: E2E Smoke Tests
        run: npx playwright test --grep "@smoke"
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}

      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: playwright-report/
```

---

## 3. 테스트 병렬화

```yaml
# 매트릭스 전략으로 병렬 실행
jobs:
  e2e:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]  # 4개 병렬
    steps:
      - run: npx playwright test --shard=${{ matrix.shard }}/4
```

```ts
// playwright.config.ts
export default defineConfig({
  workers: process.env.CI ? 2 : '50%',
  fullyParallel: true,
})
```

---

## 4. 테스트 결과 리포팅

```yaml
# Allure 리포트 생성 및 GitHub Pages 배포
- name: Generate Allure Report
  if: always()
  run: npx allure generate allure-results --clean

- name: Deploy to GitHub Pages
  if: always()
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: allure-report
```

---

## 5. 배포 게이트

```yaml
# 배포 조건 — 모든 테스트 통과 시만
deploy:
  needs: [fast-checks, integration-tests, e2e-smoke]
  if: success()
  runs-on: ubuntu-latest
  environment:
    name: staging
    url: https://staging.example.com
  steps:
    - name: Deploy to Staging
      run: ./scripts/deploy.sh staging
```

---

## 6. 실패 알림

```yaml
- name: Notify on Failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    channel-id: '#ci-alerts'
    slack-message: |
      :x: CI 실패
      브랜치: ${{ github.ref_name }}
      PR: ${{ github.event.pull_request.html_url }}
      실패 단계: ${{ job.status }}
      로그: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

---

## 7. 안티패턴

- **CI 없는 자동화 테스트**: 로컬에서만 실행 → 팀 공유 안 됨
- **너무 느린 CI**: 30분+ → 개발자가 기다리다 컨텍스트 전환
- **실패 무시 배포**: 테스트 실패를 skip하고 배포
- **테스트 환경 불일치**: 로컬과 CI의 DB 버전, 환경 변수 다름
- **병렬화 없는 E2E**: 순차 실행으로 1시간+ → 샤딩으로 분산
