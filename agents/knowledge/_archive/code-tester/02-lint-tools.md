# Lint Tools

> 참조 링크: https://eslint.org/docs/latest/, https://docs.astral.sh/ruff/, https://biomejs.dev/guides/getting-started/

---

## 1. ESLint (JavaScript / TypeScript)

### 설정 형식

ESLint 9+는 **Flat Config**(`eslint.config.js`)가 기본이다. 레거시 `.eslintrc.*`도 아직 사용 가능.

```javascript
// eslint.config.js (Flat Config)
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
    },
  },
  {
    ignores: ['dist/', 'node_modules/', '.next/'],
  }
);
```

### 실행 명령어

```bash
# 전체 프로젝트 린트
npx eslint .

# 특정 파일/디렉토리
npx eslint src/

# 자동 수정 가능한 것만 수정
npx eslint . --fix

# 특정 규칙만 확인
npx eslint . --rule '{"no-console": "error"}'

# 캐시 사용 (재실행 시 빠름)
npx eslint . --cache

# 포맷: JSON 출력 (파싱용)
npx eslint . --format json

# 변경된 파일만 (git과 조합)
npx eslint $(git diff --name-only --diff-filter=ACMR HEAD -- '*.ts' '*.tsx')
```

### 주요 에러 패턴과 해석

| 에러 | 의미 | 자동 수정 |
|------|------|----------|
| `no-unused-vars` | 미사용 변수 | ❌ (삭제 판단 필요) |
| `@typescript-eslint/no-explicit-any` | any 타입 사용 | ❌ |
| `@typescript-eslint/no-floating-promises` | await 없는 Promise | ❌ |
| `import/order` | import 순서 | ✅ `--fix` |
| `no-console` | console.log 잔존 | ❌ |
| `prefer-const` | let → const | ✅ `--fix` |
| `eqeqeq` | `==` → `===` | ✅ `--fix` |

### ESLint + Prettier 공존

```javascript
// eslint.config.js — Prettier와 충돌 규칙 끄기
import eslintConfigPrettier from 'eslint-config-prettier';

export default [
  // ... 다른 설정
  eslintConfigPrettier, // 반드시 마지막에 배치
];
```

## 2. Biome (JavaScript / TypeScript)

ESLint + Prettier 대체를 목표로 한 올인원 도구. 린트 + 포맷을 하나로 처리한다.

### 설정

```jsonc
// biome.json
{
  "$schema": "https://biomejs.dev/schemas/1.9.0/schema.json",
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "complexity": {
        "noExcessiveCognitiveComplexity": "warn"
      },
      "suspicious": {
        "noExplicitAny": "warn"
      }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  }
}
```

### 실행 명령어

```bash
# 린트만
npx @biomejs/biome lint .

# 포맷만
npx @biomejs/biome format . --write

# 린트 + 포맷 + import 정렬 한번에
npx @biomejs/biome check . --write

# CI용 (수정 없이 체크만)
npx @biomejs/biome ci .
```

## 3. Ruff (Python)

Python 린터 + 포매터. Flake8, isort, Black 등을 대체한다. Rust로 작성되어 매우 빠르다.

### 설정

```toml
# pyproject.toml
[tool.ruff]
target-version = "py311"
line-length = 120

[tool.ruff.lint]
select = [
    "E",    # pycodestyle errors
    "W",    # pycodestyle warnings
    "F",    # pyflakes
    "I",    # isort
    "B",    # flake8-bugbear
    "C4",   # flake8-comprehensions
    "UP",   # pyupgrade
    "SIM",  # flake8-simplify
]
ignore = ["E501"]  # line-too-long (formatter가 처리)

[tool.ruff.lint.isort]
known-first-party = ["myproject"]

[tool.ruff.format]
quote-style = "double"
```

### 실행 명령어

```bash
# 린트 체크
ruff check .

# 린트 자동 수정
ruff check . --fix

# 안전하지 않은 수정까지 포함
ruff check . --fix --unsafe-fixes

# 포맷
ruff format .

# 포맷 체크만 (CI용)
ruff format . --check

# 변경된 파일만
ruff check $(git diff --name-only --diff-filter=ACMR HEAD -- '*.py')
```

### 주요 에러 패턴

| 코드 | 의미 | 자동 수정 |
|------|------|----------|
| `F401` | 미사용 import | ✅ |
| `F841` | 미사용 변수 | ❌ |
| `E711` | `== None` → `is None` | ✅ |
| `I001` | import 순서 | ✅ |
| `B006` | mutable default argument | ❌ |
| `UP035` | deprecated import 교체 | ✅ |
| `SIM108` | if-else → 삼항 연산자 | ✅ |

## 4. Stylelint (CSS / SCSS)

```bash
# 실행
npx stylelint "**/*.css"
npx stylelint "**/*.scss"

# 자동 수정
npx stylelint "**/*.css" --fix
```

## 5. 린트 실행 전략

### 변경 파일만 린트하기

```bash
# staged 파일만 (pre-commit)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR)

# TypeScript 파일만 필터
TS_FILES=$(echo "$STAGED_FILES" | grep -E '\.(ts|tsx)$')
[ -n "$TS_FILES" ] && npx eslint $TS_FILES

# Python 파일만 필터
PY_FILES=$(echo "$STAGED_FILES" | grep -E '\.py$')
[ -n "$PY_FILES" ] && ruff check $PY_FILES
```

### CI에서 린트 결과 파싱

```bash
# ESLint JSON 출력 → 에러 수 카운트
npx eslint . --format json 2>/dev/null | jq '[.[] | .errorCount] | add'

# Ruff JSON 출력
ruff check . --output-format json 2>/dev/null | jq '. | length'
```

### lint-staged 연동

```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx}": ["eslint --fix", "prettier --write"],
    "*.{css,scss}": ["stylelint --fix", "prettier --write"],
    "*.py": ["ruff check --fix", "ruff format"]
  }
}
```

## 6. 에러 심각도 분류

| 심각도 | ESLint | Ruff | 대응 |
|--------|--------|------|------|
| Error | `"error"` / `2` | `select`에 포함 | 반드시 수정 |
| Warning | `"warn"` / `1` | 별도 설정 | 가능하면 수정 |
| Off | `"off"` / `0` | `ignore`에 포함 | 무시 |

### 새 에러 vs 기존 에러 구분

린트 결과에서 **변경된 파일의 변경된 라인**에서만 발생한 에러를 새 에러로 분류한다. `git diff`의 라인 범위와 린트 에러 라인을 교차 비교한다.
