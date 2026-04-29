# CI Integration

> 참조 링크: https://docs.github.com/en/actions, https://docs.gitlab.com/ee/ci/

---

## 1. GitHub Actions 검증 파이프라인

### 기본 구조

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm typecheck

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm test -- --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/

  build:
    runs-on: ubuntu-latest
    needs: [lint, typecheck, test]  # 모든 검증 통과 후 빌드
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: pnpm build
```

### DB 포함 테스트

```yaml
test:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test
        POSTGRES_DB: testdb
      ports:
        - 5432:5432
      options: >-
        --health-cmd pg_isready
        --health-interval 10s
        --health-timeout 5s
        --health-retries 5
    redis:
      image: redis:7
      ports:
        - 6379:6379
  env:
    DATABASE_URL: postgresql://test:test@localhost:5432/testdb
    REDIS_URL: redis://localhost:6379
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: 20
        cache: 'pnpm'
    - run: pnpm install --frozen-lockfile
    - run: pnpm test:e2e
```

### 캐싱 전략

```yaml
# pnpm 캐시
- uses: actions/setup-node@v4
  with:
    node-version: 20
    cache: 'pnpm'

# Turborepo 캐시
- uses: actions/cache@v4
  with:
    path: .turbo
    key: turbo-${{ runner.os }}-${{ hashFiles('**/pnpm-lock.yaml') }}

# Next.js 빌드 캐시
- uses: actions/cache@v4
  with:
    path: .next/cache
    key: nextjs-${{ runner.os }}-${{ hashFiles('**/pnpm-lock.yaml') }}-${{ hashFiles('**/*.ts', '**/*.tsx') }}
```

## 2. GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - test
  - build

variables:
  NODE_VERSION: "20"

.node-setup:
  image: node:${NODE_VERSION}
  cache:
    key: ${CI_COMMIT_REF_SLUG}
    paths:
      - node_modules/
  before_script:
    - corepack enable
    - pnpm install --frozen-lockfile

lint:
  extends: .node-setup
  stage: validate
  script:
    - pnpm lint

typecheck:
  extends: .node-setup
  stage: validate
  script:
    - pnpm typecheck

test:
  extends: .node-setup
  stage: test
  services:
    - postgres:16
  variables:
    POSTGRES_DB: testdb
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://test:test@postgres:5432/testdb
  script:
    - pnpm test -- --coverage
  coverage: '/Lines\s*:\s*(\d+\.?\d*)%/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

build:
  extends: .node-setup
  stage: build
  script:
    - pnpm build
  artifacts:
    paths:
      - dist/
```

## 3. 모노레포 CI

### Turborepo + GitHub Actions

```yaml
jobs:
  changed:
    runs-on: ubuntu-latest
    outputs:
      packages: ${{ steps.filter.outputs.changes }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            api:
              - 'apps/api/**'
            web:
              - 'apps/web/**'
            core:
              - 'packages/core/**'

  test:
    needs: changed
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pnpm install --frozen-lockfile
      - run: pnpm turbo test --filter=...[origin/main]
```

## 4. Python CI

```yaml
# GitHub Actions
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12']
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - run: pip install poetry
      - run: poetry install
      - run: poetry run ruff check .
      - run: poetry run mypy src/
      - run: poetry run pytest --cov=src --cov-report=xml
```

## 5. CI 실패 진단

### 로컬 재현

```bash
# GitHub Actions를 로컬에서 실행 (act)
act -j test

# 또는 CI와 동일한 환경 구성
docker run -it --rm -v $(pwd):/app -w /app node:20 bash
npm install --frozen-lockfile
npm test
```

### 흔한 CI 전용 실패

| 현상 | 원인 | 해결 |
|------|------|------|
| 로컬 OK, CI 실패 | 캐시된 node_modules | `--frozen-lockfile` 사용 |
| Permission denied | 파일 권한 | `chmod +x` 또는 Git 설정 |
| Out of memory | CI 리소스 제한 | `--max-old-space-size` 또는 `--maxWorkers` 제한 |
| Timeout | 느린 테스트 | timeout 늘리기 또는 병렬화 |
| Flaky test | 비결정적 테스트 | 재시도 또는 격리 |
| Snapshot mismatch | OS 차이 (줄바꿈 등) | 스냅샷 업데이트 또는 정규화 |
