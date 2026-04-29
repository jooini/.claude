# Auto Fix Patterns

---

## 1. 안전한 자동 수정 기준

자동 수정은 **동작을 변경하지 않는** 변환만 수행해야 한다.

### 안전 레벨

| 레벨 | 설명 | 예시 |
|------|------|------|
| ✅ 안전 | 의미 변화 없음 | import 정렬, 포맷팅, trailing comma |
| ⚠️ 주의 | 대부분 안전하지만 확인 필요 | 미사용 import 제거, `let` → `const` |
| ❌ 위험 | 동작이 변경될 수 있음 | 미사용 변수 제거, 타입 변환 |

## 2. ESLint 자동 수정

### 안전한 규칙 (--fix)

```bash
npx eslint . --fix
```

자동 수정되는 주요 규칙:

```
✅ import/order          — import 순서 정렬
✅ prefer-const          — let → const (재할당 없을 때)
✅ eqeqeq               — == → ===
✅ no-extra-semi         — 불필요한 세미콜론 제거
✅ no-trailing-spaces    — 줄 끝 공백 제거
✅ comma-dangle          — trailing comma 추가/제거
✅ quotes                — 따옴표 통일
✅ semi                  — 세미콜론 추가/제거
✅ arrow-parens          — 화살표 함수 괄호
✅ object-curly-spacing  — 중괄호 간격
```

### 수동 수정 필요한 규칙

```
❌ no-unused-vars              — 변수가 정말 불필요한지 판단 필요
❌ @typescript-eslint/no-explicit-any — 적절한 타입을 직접 지정해야
❌ @typescript-eslint/no-floating-promises — await 추가 위치 판단 필요
❌ no-console                  — 의도적 로깅인지 확인 필요
❌ complexity                  — 리팩토링 방향 판단 필요
```

## 3. Prettier 자동 포맷

```bash
# 포맷 적용
npx prettier --write .

# 체크만 (CI용)
npx prettier --check .

# 특정 파일
npx prettier --write "src/**/*.{ts,tsx}"
```

### 안전성

Prettier는 **코드 의미를 변경하지 않는다**. 순수 포맷팅만 수행하므로 항상 안전하다.

## 4. Ruff 자동 수정 (Python)

### 안전한 수정

```bash
ruff check . --fix
```

안전하게 수정되는 규칙:

```
✅ F401  — 미사용 import 제거 (⚠️ re-export 확인)
✅ I001  — import 정렬
✅ E711  — == None → is None
✅ UP035 — deprecated import 교체
✅ W291  — trailing whitespace
✅ W292  — 파일 끝 빈 줄
✅ C4    — 불필요한 list/dict comprehension 단순화
```

### 안전하지 않은 수정

```bash
# --unsafe-fixes 필요
ruff check . --fix --unsafe-fixes
```

```
⚠️ F841 — 미사용 변수 제거 (부작용 가능)
⚠️ B006 — mutable default → None + if 패턴
⚠️ UP   — Python 버전 업그레이드 관련 변환
```

## 5. TypeScript 관련 자동 수정

### 미사용 import 제거

```bash
# TypeScript 내장 (5.0+)
npx tsc --noEmit  # 에러 확인 후 수동 제거

# eslint로 자동 제거
# eslint.config.js
{
  rules: {
    '@typescript-eslint/no-unused-vars': 'error',
    'unused-imports/no-unused-imports': 'error',  // eslint-plugin-unused-imports
  }
}
npx eslint . --fix  # 미사용 import 자동 제거
```

### organize-imports

```bash
# Biome
npx @biomejs/biome check . --write  # import 정렬 포함

# eslint-plugin-import
npx eslint . --fix  # import/order 규칙
```

## 6. 자동 수정 워크플로우

### 단계별 적용

```bash
# 1단계: 포맷팅 (가장 안전)
npx prettier --write .

# 2단계: 안전한 린트 수정
npx eslint . --fix

# 3단계: import 정리
npx eslint . --fix --rule '{"unused-imports/no-unused-imports": "error"}'

# 4단계: 결과 확인
npx tsc --noEmit
npx jest --bail
```

### Git 기반 안전망

```bash
# 수정 전 스냅샷
git stash

# 자동 수정 적용
npx eslint . --fix
npx prettier --write .

# diff 확인
git diff

# 문제 있으면 롤백
git checkout .
git stash pop
```

## 7. pre-commit 자동 수정

```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx}": [
      "eslint --fix",
      "prettier --write"
    ],
    "*.{json,md,yml}": [
      "prettier --write"
    ],
    "*.py": [
      "ruff check --fix",
      "ruff format"
    ]
  }
}
```

## 8. 자동 수정 후 검증

자동 수정 후 반드시 확인:

1. **타입 체크**: `npx tsc --noEmit` — 자동 수정이 타입 에러를 유발하지 않는지
2. **테스트**: `npx jest` — 동작이 변경되지 않았는지
3. **빌드**: `npm run build` — 프로덕션 빌드 성공 여부
4. **diff 리뷰**: `git diff` — 예상치 못한 변경 없는지
