# Type Checking

> 참조 링크: https://www.typescriptlang.org/docs/handbook/compiler-options.html, https://mypy.readthedocs.io/en/stable/

---

## 1. TypeScript (tsc)

### 실행 명령어

```bash
# 타입 체크만 (JS 출력 안 함)
npx tsc --noEmit

# 특정 tsconfig 사용
npx tsc --noEmit -p tsconfig.json

# watch 모드
npx tsc --noEmit --watch

# 빌드 모드 (프로젝트 참조)
npx tsc --build

# 에러 수만 카운트
npx tsc --noEmit 2>&1 | grep "error TS" | wc -l
```

### 주요 컴파일러 옵션 (strict 관련)

```jsonc
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,                    // 아래 모든 strict 옵션 활성화
    "noUncheckedIndexedAccess": true,  // 인덱스 접근 시 undefined 가능성
    "exactOptionalPropertyTypes": true, // undefined와 optional 구분
    "noImplicitOverride": true,        // override 키워드 강제
    "skipLibCheck": true,              // node_modules 타입 체크 스킵 (빌드 속도)
    "forceConsistentCasingInFileNames": true
  }
}
```

### 흔한 타입 에러와 해석

| 에러 코드 | 메시지 패턴 | 원인 | 해결 |
|-----------|-----------|------|------|
| TS2322 | Type 'X' is not assignable to type 'Y' | 타입 불일치 | 타입 수정 또는 타입 가드 추가 |
| TS2345 | Argument of type 'X' is not assignable | 함수 인자 타입 불일치 | 인자 타입 수정 |
| TS2531 | Object is possibly 'null' | null 체크 누락 | optional chaining 또는 null 체크 |
| TS2532 | Object is possibly 'undefined' | undefined 체크 누락 | 타입 가드 추가 |
| TS7006 | Parameter 'x' implicitly has 'any' type | 타입 어노테이션 누락 | 타입 명시 |
| TS2339 | Property 'x' does not exist on type 'Y' | 존재하지 않는 프로퍼티 접근 | 타입 정의 확인 |
| TS2556 | A spread argument must have a tuple type | 스프레드 타입 불일치 | `as const` 또는 튜플 타입 |
| TS18046 | 'x' is of type 'unknown' | unknown 타입 좁히기 필요 | 타입 가드 추가 |
| TS2307 | Cannot find module 'X' | 모듈 경로 오류 또는 타입 미설치 | `@types/X` 설치 또는 경로 확인 |
| TS6133 | 'x' is declared but its value is never read | 미사용 변수 | 제거 또는 `_` prefix |

### 프로젝트 참조 (Monorepo)

```jsonc
// tsconfig.json (루트)
{
  "references": [
    { "path": "./packages/core" },
    { "path": "./packages/api" },
    { "path": "./packages/web" }
  ]
}
```

```bash
# 프로젝트 참조 빌드
npx tsc --build

# 클린 빌드
npx tsc --build --clean
```

## 2. mypy (Python)

### 설정

```toml
# pyproject.toml
[tool.mypy]
python_version = "3.11"
strict = true
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true

# 서드파티 라이브러리 타입 무시
[[tool.mypy.overrides]]
module = ["some_untyped_lib.*"]
ignore_missing_imports = true
```

### 실행 명령어

```bash
# 전체 체크
mypy .

# 특정 디렉토리
mypy src/

# strict 모드
mypy --strict src/

# 캐시 무시
mypy --no-incremental src/

# 에러 코드 표시
mypy --show-error-codes src/

# JSON 출력
mypy --output json src/
```

### 주요 에러와 해석

| 에러 코드 | 의미 | 해결 |
|-----------|------|------|
| `[assignment]` | 타입 불일치 대입 | 타입 수정 |
| `[arg-type]` | 함수 인자 타입 불일치 | 인자 타입 수정 |
| `[return-value]` | 반환 타입 불일치 | 반환 타입 수정 |
| `[name-defined]` | 미정의 이름 | import 추가 또는 오타 수정 |
| `[attr-defined]` | 존재하지 않는 속성 | 타입 정의 확인 |
| `[no-untyped-def]` | 타입 어노테이션 누락 | 타입 추가 |
| `[import]` | import 실패 | 타입 스텁 설치 또는 ignore 설정 |
| `[override]` | 메서드 오버라이드 시그니처 불일치 | 시그니처 수정 |
| `[union-attr]` | Union 타입에서 공통되지 않는 속성 접근 | 타입 가드 추가 |

## 3. pyright (Python)

mypy보다 빠르고, VS Code Python 확장이 내부적으로 사용한다.

```bash
# 설치
pip install pyright

# 실행
pyright

# 특정 디렉토리
pyright src/

# JSON 출력
pyright --outputjson
```

```jsonc
// pyrightconfig.json
{
  "include": ["src"],
  "exclude": ["**/node_modules", "**/__pycache__"],
  "typeCheckingMode": "strict",
  "pythonVersion": "3.11"
}
```

## 4. Go vet / staticcheck

```bash
# go vet — 기본 정적 분석
go vet ./...

# staticcheck — 확장 정적 분석
staticcheck ./...

# golangci-lint — 통합 린터
golangci-lint run
```

## 5. 타입 체크 실행 전략

### CI 통합

```yaml
# GitHub Actions 예시
- name: Type Check (TypeScript)
  run: npx tsc --noEmit

- name: Type Check (Python)
  run: mypy src/ --show-error-codes
```

### 변경 파일 기반 체크

TypeScript의 `tsc`는 파일 단위 체크가 아닌 프로젝트 단위로 동작하므로, 변경 파일만 체크하는 것이 불가능하다. 대신:

1. `tsc --noEmit` 전체 실행 후
2. 에러 발생 파일과 `git diff` 변경 파일을 교차 비교
3. 변경 파일에서 발생한 에러만 새 에러로 분류

Python mypy는 `--follow-imports=skip`으로 특정 파일만 체크 가능:

```bash
mypy --follow-imports=skip $(git diff --name-only HEAD -- '*.py')
```

### 타입 에러 수정 우선순위

1. **TS2307 (모듈 미발견)** → 빌드 자체가 실패하므로 최우선
2. **TS2322/TS2345 (타입 불일치)** → 런타임 에러 가능성
3. **TS2531/TS2532 (null/undefined)** → 런타임 에러 가능성
4. **TS7006 (implicit any)** → 타입 안전성 저하
5. **TS6133 (미사용)** → 코드 정리 수준
