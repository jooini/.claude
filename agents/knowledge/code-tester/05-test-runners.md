# Test Runners

> 참조 링크: https://jestjs.io/docs/configuration, https://vitest.dev/config/, https://docs.pytest.org/en/stable/reference/reference.html

---

## 1. Jest

### 설정 감지

```
jest.config.js / jest.config.ts / jest.config.mjs
package.json의 "jest" 필드
```

### 실행 명령어

```bash
# 전체 테스트
npx jest

# 특정 파일
npx jest src/user.service.spec.ts

# 패턴 매칭
npx jest --testPathPattern="user"

# watch 모드
npx jest --watch

# 커버리지
npx jest --coverage

# 실패한 테스트만 재실행
npx jest --onlyFailures

# 병렬 제한 (CI 메모리 부족 시)
npx jest --maxWorkers=2

# verbose 출력
npx jest --verbose

# 특정 테스트명
npx jest -t "should create user"

# JSON 출력 (파싱용)
npx jest --json --outputFile=results.json

# 변경 파일 관련 테스트만
npx jest --changedSince=HEAD~1
```

### 설정 예시

```typescript
// jest.config.ts
import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.spec.ts', '**/*.test.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
    '!src/**/*.spec.ts',
    '!src/main.ts',
  ],
  coverageThresholds: {
    global: { branches: 80, functions: 80, lines: 80, statements: 80 },
  },
  setupFilesAfterSetup: ['<rootDir>/test/setup.ts'],
};

export default config;
```

## 2. Vitest

### 설정 감지

```
vitest.config.ts / vitest.config.js
vite.config.ts의 test 필드
```

### 실행 명령어

```bash
# 전체 테스트
npx vitest run

# watch 모드 (기본)
npx vitest

# 특정 파일
npx vitest run src/user.service.test.ts

# 패턴 매칭
npx vitest run --reporter=verbose user

# 커버리지
npx vitest run --coverage

# UI 모드 (브라우저)
npx vitest --ui

# 타입 테스트
npx vitest typecheck

# 벤치마크
npx vitest bench

# JSON 리포터
npx vitest run --reporter=json --outputFile=results.json

# 스레드 제한
npx vitest run --pool=threads --poolOptions.threads.maxThreads=2
```

### 설정 예시

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.d.ts', 'src/**/*.test.ts'],
    },
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});
```

## 3. pytest

### 설정 감지

```
pytest.ini
pyproject.toml의 [tool.pytest.ini_options]
conftest.py
setup.cfg의 [tool:pytest]
```

### 실행 명령어

```bash
# 전체 테스트
pytest

# 특정 파일
pytest tests/test_user.py

# 특정 테스트 함수
pytest tests/test_user.py::test_create_user

# 특정 클래스의 메서드
pytest tests/test_user.py::TestUserService::test_create

# 키워드 매칭
pytest -k "user and not delete"

# verbose
pytest -v

# 실패 시 즉시 중단
pytest -x

# 처음 N개 실패 후 중단
pytest --maxfail=3

# 커버리지
pytest --cov=src --cov-report=html

# 마지막 실패한 것만 재실행
pytest --lf

# 실패한 것 먼저 실행
pytest --ff

# 병렬 실행 (pytest-xdist)
pytest -n auto

# 마커 필터
pytest -m "not slow"

# 출력 캡처 비활성화
pytest -s

# JSON 출력
pytest --json-report --json-report-file=results.json
```

### 설정 예시

```toml
# pyproject.toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_functions = ["test_*"]
addopts = "-v --strict-markers --tb=short"
markers = [
    "slow: marks tests as slow",
    "integration: integration tests",
    "e2e: end-to-end tests",
]
filterwarnings = [
    "ignore::DeprecationWarning",
]
```

## 4. Go test

```bash
# 전체 테스트
go test ./...

# 특정 패키지
go test ./internal/user/

# verbose
go test -v ./...

# 패턴 매칭
go test -run TestCreateUser ./...

# 커버리지
go test -cover ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# 레이스 컨디션 감지
go test -race ./...

# 벤치마크
go test -bench=. ./...

# 타임아웃
go test -timeout 30s ./...

# 캐시 무시
go test -count=1 ./...
```

## 5. 테스트 실행 전략

### 변경 영향 기반 실행

```bash
# Jest: git 기반 변경 파일 관련 테스트
npx jest --changedSince=main

# Vitest: 변경 감지
npx vitest run --changed HEAD~1

# pytest: 변경 파일과 관련된 테스트 (pytest-picked)
pytest --picked
```

### CI 최적화

```bash
# 분할 실행 (대규모 테스트)
# Jest
npx jest --shard=1/3  # 3개 중 1번
npx jest --shard=2/3
npx jest --shard=3/3

# pytest (pytest-split)
pytest --splits 3 --group 1
```

## 6. 테스트 에러 해석

### 공통 실패 패턴

| 패턴 | 원인 | 대응 |
|------|------|------|
| `Timeout` | 비동기 작업 미완료 | timeout 늘리기 또는 await 확인 |
| `Cannot find module` | import 경로 오류 | moduleNameMapper / alias 확인 |
| `is not a function` | mock 설정 오류 또는 import 문제 | mock 구현 확인 |
| `ECONNREFUSED` | 외부 서비스 미기동 | 테스트용 서비스 구동 또는 mock |
| `Snapshot mismatch` | UI 변경됨 | 의도된 변경이면 스냅샷 업데이트 |
| `Exceeded timeout` | 느린 테스트 | DB 연결, 네트워크 요청 확인 |
