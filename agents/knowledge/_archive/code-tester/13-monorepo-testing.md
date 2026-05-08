# Monorepo Testing

> 참조 링크: https://turbo.build/repo/docs, https://nx.dev/concepts/affected

---

## 1. 모노레포 테스트 전략

모노레포에서는 **변경 영향 범위**를 파악하여 필요한 패키지만 테스트하는 것이 핵심이다.

## 2. Turborepo

### 영향 범위 기반 실행

```bash
# main 대비 변경된 패키지만 테스트
npx turbo test --filter=...[origin/main]

# 특정 패키지와 그 의존성
npx turbo test --filter=@myapp/api...

# 특정 패키지에 의존하는 패키지들
npx turbo test --filter=...@myapp/core

# 특정 패키지만 (의존성 제외)
npx turbo test --filter=@myapp/web
```

### turbo.json 설정

```jsonc
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],  // 의존 패키지 빌드 먼저
      "outputs": ["dist/**", ".next/**"]
    },
    "test": {
      "dependsOn": ["build"],
      "inputs": ["src/**", "tests/**", "*.config.*"],
      "outputs": ["coverage/**"]
    },
    "lint": {
      "inputs": ["src/**", "*.config.*"]
    },
    "typecheck": {
      "dependsOn": ["^build"],
      "inputs": ["src/**", "tsconfig.json"]
    }
  }
}
```

### 캐시 활용

```bash
# 로컬 캐시 (기본)
npx turbo test  # 변경 없으면 캐시 히트

# 캐시 무시
npx turbo test --force

# 캐시 상태 확인
npx turbo run test --dry-run

# 원격 캐시 (CI 공유)
npx turbo test --remote-cache
```

## 3. Nx

### 영향 범위 분석

```bash
# 변경 영향 받는 프로젝트만 테스트
npx nx affected -t test

# 기준 브랜치 지정
npx nx affected -t test --base=main

# 특정 프로젝트
npx nx test api

# 모든 프로젝트
npx nx run-many -t test

# 의존성 그래프 시각화
npx nx graph
```

### nx.json 설정

```jsonc
{
  "targetDefaults": {
    "test": {
      "inputs": ["default", "^default"],
      "cache": true
    },
    "build": {
      "dependsOn": ["^build"],
      "cache": true
    }
  },
  "affected": {
    "defaultBase": "main"
  }
}
```

## 4. pnpm workspace

```bash
# 특정 패키지 테스트
pnpm --filter @myapp/api test

# 변경된 패키지만 (--filter with git)
pnpm --filter "...[origin/main]" test

# 모든 패키지
pnpm -r test

# 병렬 실행
pnpm -r --parallel test

# 의존성 순서대로
pnpm -r --sort test

# 스트리밍 출력
pnpm -r --stream test
```

## 5. 의존성 그래프 기반 테스트

### 변경 파급 분석

```
packages/
├── core/        ← 변경됨
├── api/         ← core에 의존 → 테스트 필요
├── web/         ← core에 의존 → 테스트 필요
├── admin/       ← api에 의존 → 테스트 필요 (간접)
└── docs/        ← 독립 → 테스트 불필요
```

```bash
# 의존성 확인
pnpm why @myapp/core --filter @myapp/api
# @myapp/api depends on @myapp/core

# Turborepo 의존성 그래프
npx turbo test --filter=...@myapp/core --dry-run
# 실행 대상: core, api, web, admin
```

## 6. CI에서 모노레포 테스트

### GitHub Actions + Turborepo

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # 전체 히스토리 (affected 분석용)
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - name: Test affected packages
        run: npx turbo test --filter=...[origin/main]
```

### 병렬 CI 매트릭스

```yaml
jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      packages: ${{ steps.changes.outputs.packages }}
    steps:
      - uses: actions/checkout@v4
      - id: changes
        run: |
          PACKAGES=$(npx turbo test --filter=...[origin/main] --dry-run=json | jq -c '[.tasks[].package] | unique')
          echo "packages=$PACKAGES" >> $GITHUB_OUTPUT

  test:
    needs: detect-changes
    if: needs.detect-changes.outputs.packages != '[]'
    strategy:
      matrix:
        package: ${{ fromJson(needs.detect-changes.outputs.packages) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pnpm install --frozen-lockfile
      - run: npx turbo test --filter=${{ matrix.package }}
```

## 7. 공유 설정 패턴

### 공통 테스트 설정

```
packages/
├── config/
│   ├── jest-preset/       # 공유 Jest 설정
│   │   └── index.js
│   ├── vitest-preset/     # 공유 Vitest 설정
│   │   └── index.ts
│   └── tsconfig/          # 공유 TypeScript 설정
│       └── base.json
├── api/
│   └── jest.config.ts     # preset 상속
└── web/
    └── vitest.config.ts   # preset 상속
```

```typescript
// packages/api/jest.config.ts
import baseConfig from '@myapp/jest-preset';

export default {
  ...baseConfig,
  testMatch: ['<rootDir>/src/**/*.spec.ts'],
};
```

## 8. 모노레포 테스트 체크리스트

- [ ] 변경 영향 범위 분석 도구 설정 (Turborepo/Nx)
- [ ] 패키지 간 의존성 그래프 정확한지 확인
- [ ] CI에서 affected 패키지만 테스트
- [ ] 빌드 캐시 활용 (로컬 + 원격)
- [ ] 공유 테스트 설정 패키지 분리
- [ ] 루트 레벨에서 전체 테스트 가능하도록 스크립트 구성
