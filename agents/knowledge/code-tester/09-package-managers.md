# Package Managers

> 참조 링크: https://docs.npmjs.com/cli/v10, https://pnpm.io/cli/install, https://yarnpkg.com/cli, https://bun.sh/docs/cli/install

---

## 1. 패키지 매니저 감지

| Lock 파일 | 매니저 | 실행 명령어 |
|-----------|--------|-----------|
| `package-lock.json` | npm | `npm` |
| `pnpm-lock.yaml` | pnpm | `pnpm` |
| `yarn.lock` | yarn | `yarn` |
| `bun.lockb` | bun | `bun` |

**규칙**: lock 파일이 여러 개 있으면 가장 최근 수정된 것을 우선한다. `packageManager` 필드가 있으면 그것이 최우선.

```jsonc
// package.json — corepack 연동
{
  "packageManager": "pnpm@9.1.0"  // 이 필드가 있으면 확정
}
```

## 2. 명령어 매핑

### 설치

| 동작 | npm | pnpm | yarn | bun |
|------|-----|------|------|-----|
| 전체 설치 | `npm install` | `pnpm install` | `yarn` | `bun install` |
| 프로덕션만 | `npm install --omit=dev` | `pnpm install --prod` | `yarn --production` | `bun install --production` |
| 패키지 추가 | `npm install X` | `pnpm add X` | `yarn add X` | `bun add X` |
| dev 추가 | `npm install -D X` | `pnpm add -D X` | `yarn add -D X` | `bun add -d X` |
| 글로벌 추가 | `npm install -g X` | `pnpm add -g X` | `yarn global add X` | `bun add -g X` |
| 제거 | `npm uninstall X` | `pnpm remove X` | `yarn remove X` | `bun remove X` |

### 실행

| 동작 | npm | pnpm | yarn | bun |
|------|-----|------|------|-----|
| 스크립트 실행 | `npm run X` | `pnpm X` | `yarn X` | `bun run X` |
| npx 대체 | `npx X` | `pnpm dlx X` | `yarn dlx X` | `bunx X` |
| 바이너리 실행 | `npx X` | `pnpm exec X` | `yarn exec X` | `bunx X` |

### 기타

| 동작 | npm | pnpm | yarn | bun |
|------|-----|------|------|-----|
| 캐시 클리어 | `npm cache clean --force` | `pnpm store prune` | `yarn cache clean` | `bun pm cache rm` |
| outdated | `npm outdated` | `pnpm outdated` | `yarn outdated` | — |
| audit | `npm audit` | `pnpm audit` | `yarn audit` | — |
| lock 재생성 | 삭제 후 install | 삭제 후 install | 삭제 후 install | 삭제 후 install |

## 3. Lock 파일 해석

### package-lock.json (npm)

```jsonc
{
  "lockfileVersion": 3,  // npm 9+
  "packages": {
    "node_modules/express": {
      "version": "4.18.2",
      "resolved": "https://registry.npmjs.org/express/-/express-4.18.2.tgz",
      "integrity": "sha512-...",
      "dependencies": { ... }
    }
  }
}
```

### pnpm-lock.yaml

```yaml
lockfileVersion: '9.0'
settings:
  autoInstallPeers: true
packages:
  express@4.18.2:
    resolution: {integrity: sha512-...}
    dependencies:
      accepts: 1.3.8
```

### 충돌 해결

```bash
# lock 파일 충돌 시 — 재생성이 가장 안전
rm package-lock.json  # 또는 해당 lock 파일
npm install           # 또는 해당 매니저

# pnpm — lock 파일만 업데이트
pnpm install --lockfile-only
```

## 4. Workspace (모노레포)

### pnpm workspace

```yaml
# pnpm-workspace.yaml
packages:
  - 'packages/*'
  - 'apps/*'
```

```bash
# 특정 패키지에서 실행
pnpm --filter @myapp/api run build
pnpm --filter @myapp/web add react

# 모든 패키지에서 실행
pnpm -r run build
pnpm -r run test

# 의존성 있는 순서대로
pnpm -r --sort run build
```

### npm workspace

```jsonc
// package.json
{
  "workspaces": ["packages/*", "apps/*"]
}
```

```bash
npm run build -w packages/core
npm run test --workspaces
```

### yarn workspace

```bash
yarn workspace @myapp/api build
yarn workspaces foreach run build
```

## 5. 의존성 문제 해결

### 의존성 충돌

```bash
# npm — peer dependency 충돌
npm install --legacy-peer-deps  # 피어 의존성 무시
npm install --force             # 충돌 강제 해결

# pnpm — strict peer deps
pnpm install --no-strict-peer-dependencies

# 충돌 원인 확인
npm ls <패키지명>
pnpm why <패키지명>
yarn why <패키지명>
```

### node_modules 재설치

```bash
# 클린 재설치
rm -rf node_modules
rm -rf .pnpm-store  # pnpm 로컬 스토어 (보통 불필요)
<매니저> install

# 캐시까지 클리어
npm cache clean --force && rm -rf node_modules && npm install
pnpm store prune && rm -rf node_modules && pnpm install
```

## 6. 스크립트 감지

```bash
# package.json에서 사용 가능한 스크립트 확인
cat package.json | jq '.scripts | keys'

# 일반적인 스크립트명
# "build"   — 프로덕션 빌드
# "dev"     — 개발 서버
# "test"    — 테스트 실행
# "lint"    — 린트 실행
# "start"   — 프로덕션 시작
# "typecheck" — 타입 체크
```
