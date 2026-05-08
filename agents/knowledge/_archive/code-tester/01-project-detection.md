# Project Detection

> 참조 링크: https://docs.npmjs.com/cli/v10/configuring-npm/package-json, https://python-poetry.org/docs/pyproject/, https://go.dev/doc/modules/gomod-ref

---

## 1. 감지 전략 개요

프로젝트의 언어, 프레임워크, 빌드 도구를 **설정 파일 존재 여부**로 판별한다. 파일 시스템 탐색 한 번으로 스택 전체를 파악하는 것이 목표다.

### 감지 우선순위

1. **Lock 파일** → 패키지 매니저 확정
2. **프레임워크 설정 파일** → 프레임워크 확정
3. **package.json / pyproject.toml** → 언어 + 의존성 확정
4. **tsconfig.json / .eslintrc** → 부가 도구 확정

## 2. Node.js / TypeScript 감지

### 패키지 매니저 판별

| 파일 | 패키지 매니저 |
|------|-------------|
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `package-lock.json` | npm |
| `bun.lockb` | bun |

```typescript
// 패키지 매니저 감지 로직
const detectPackageManager = (files: string[]): string => {
  if (files.includes('pnpm-lock.yaml')) return 'pnpm';
  if (files.includes('yarn.lock')) return 'yarn';
  if (files.includes('bun.lockb')) return 'bun';
  if (files.includes('package-lock.json')) return 'npm';
  return 'npm'; // fallback
};
```

### 프레임워크 감지

| 파일 | 프레임워크 |
|------|-----------|
| `next.config.js` / `next.config.mjs` / `next.config.ts` | Next.js |
| `nuxt.config.ts` | Nuxt |
| `vite.config.ts` | Vite |
| `angular.json` | Angular |
| `nest-cli.json` | NestJS |
| `remix.config.js` | Remix |
| `astro.config.mjs` | Astro |

### TypeScript 여부

- `tsconfig.json` 존재 → TypeScript 프로젝트
- `package.json`의 `devDependencies`에 `typescript` 포함 → TypeScript

### 모노레포 감지

| 파일 | 도구 |
|------|------|
| `turbo.json` | Turborepo |
| `nx.json` | Nx |
| `lerna.json` | Lerna |
| `pnpm-workspace.yaml` | pnpm workspace |
| `package.json`의 `workspaces` 필드 | npm/yarn workspace |

## 3. Python 감지

### 패키지 매니저 / 프로젝트 도구

| 파일 | 도구 |
|------|------|
| `pyproject.toml` + `poetry.lock` | Poetry |
| `pyproject.toml` + `uv.lock` | uv |
| `Pipfile` + `Pipfile.lock` | pipenv |
| `requirements.txt` | pip |
| `setup.py` / `setup.cfg` | setuptools |
| `conda.yaml` / `environment.yml` | Conda |

### 프레임워크 감지

```python
# pyproject.toml 또는 requirements.txt에서 의존성 확인
PYTHON_FRAMEWORKS = {
    'django': 'Django',
    'flask': 'Flask',
    'fastapi': 'FastAPI',
    'starlette': 'Starlette',
    'celery': 'Celery',
    'pytest': 'pytest',  # 테스트 프레임워크
}
```

### Python 버전 감지

- `.python-version` → pyenv 관리
- `pyproject.toml`의 `[tool.poetry.dependencies].python` 필드
- `runtime.txt` → Heroku 등 PaaS

## 4. Go 감지

| 파일 | 의미 |
|------|------|
| `go.mod` | Go 모듈 (버전 + 의존성) |
| `go.sum` | 의존성 체크섬 |
| `Makefile` | 빌드 스크립트 (Go 프로젝트에서 흔함) |

## 5. Rust 감지

| 파일 | 의미 |
|------|------|
| `Cargo.toml` | Rust 프로젝트 |
| `Cargo.lock` | 의존성 잠금 |

## 6. Docker / 인프라 감지

| 파일 | 의미 |
|------|------|
| `Dockerfile` | Docker 빌드 |
| `docker-compose.yml` / `docker-compose.yaml` / `compose.yml` | Docker Compose |
| `.dockerignore` | Docker 빌드 컨텍스트 제외 |
| `Makefile` | 빌드/배포 자동화 |

## 7. CI/CD 감지

| 디렉토리/파일 | CI 도구 |
|-------------|---------|
| `.github/workflows/` | GitHub Actions |
| `.gitlab-ci.yml` | GitLab CI |
| `Jenkinsfile` | Jenkins |
| `.circleci/config.yml` | CircleCI |
| `bitbucket-pipelines.yml` | Bitbucket Pipelines |

## 8. 테스트 도구 감지

### Node.js 테스트 도구

| 감지 방법 | 도구 |
|----------|------|
| `jest.config.*` 또는 `package.json`의 `jest` 필드 | Jest |
| `vitest.config.*` 또는 의존성에 `vitest` | Vitest |
| `.mocharc.*` 또는 의존성에 `mocha` | Mocha |
| `playwright.config.*` | Playwright |
| `cypress.config.*` 또는 `cypress/` 디렉토리 | Cypress |

### Python 테스트 도구

| 감지 방법 | 도구 |
|----------|------|
| `pytest.ini` / `pyproject.toml`의 `[tool.pytest]` / `conftest.py` | pytest |
| `tox.ini` | tox |
| `noxfile.py` | nox |

## 9. 린트/포맷 도구 감지

| 파일 | 도구 |
|------|------|
| `.eslintrc.*` / `eslint.config.*` / `package.json`의 `eslintConfig` | ESLint |
| `.prettierrc.*` / `prettier.config.*` | Prettier |
| `biome.json` / `biome.jsonc` | Biome |
| `.stylelintrc.*` | Stylelint |
| `ruff.toml` / `pyproject.toml`의 `[tool.ruff]` | Ruff |
| `.flake8` / `setup.cfg`의 `[flake8]` | Flake8 |
| `mypy.ini` / `pyproject.toml`의 `[tool.mypy]` | mypy |

## 10. 통합 감지 알고리즘

```typescript
interface ProjectStack {
  language: 'typescript' | 'javascript' | 'python' | 'go' | 'rust';
  packageManager: string;
  framework: string | null;
  testRunner: string | null;
  linter: string | null;
  formatter: string | null;
  isMonorepo: boolean;
  ciTool: string | null;
}

// 1단계: 루트 디렉토리 파일 목록 수집
// 2단계: lock 파일로 패키지 매니저 확정
// 3단계: 설정 파일로 프레임워크 확정
// 4단계: package.json / pyproject.toml 의존성으로 테스트/린트 도구 확정
// 5단계: 모노레포 여부 판별
// 6단계: CI 도구 판별
```

### 감지 시 주의사항

- **모노레포**: 루트와 각 패키지의 설정이 다를 수 있다. 패키지별로 감지를 반복해야 한다
- **설정 파일 우선순위**: 전용 설정 파일 > package.json 내장 설정
- **Flat config 전환**: ESLint 9+는 `eslint.config.js`를 사용한다. `.eslintrc.*`가 없다고 ESLint 미사용이 아님
- **복합 프로젝트**: 하나의 레포에 Node.js + Python이 공존할 수 있다. 언어 감지를 배타적으로 하지 않는다
