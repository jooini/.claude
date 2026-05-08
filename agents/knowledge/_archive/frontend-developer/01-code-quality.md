# Code Quality

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/code-quality

---

## 1. 코드 품질의 4가지 축

### 가독성 (Readability)
코드는 작성하는 시간보다 읽는 시간이 훨씬 길다.

- **명확한 이름**: 변수/함수명이 의도를 드러내야 한다
  - `d` ❌ → `daysSinceLastLogin` ✅
  - `handleClick` ❌ → `handleSubmitPayment` ✅
- **짧은 함수**: 한 함수는 한 가지 일만. 20줄 넘으면 분리 고려
- **중첩 최소화**: if/for 중첩 3단계 이상이면 early return 또는 함수 추출

```ts
// ❌ 깊은 중첩
function processUser(user) {
  if (user) {
    if (user.isActive) {
      if (user.hasPermission) {
        doSomething()
      }
    }
  }
}

// ✅ early return
function processUser(user) {
  if (!user) return
  if (!user.isActive) return
  if (!user.hasPermission) return
  doSomething()
}
```

### 예측 가능성 (Predictability)
같은 입력에 항상 같은 출력. 사이드 이펙트 최소화.

```ts
// ❌ 예측 불가 — 외부 상태 변경
let total = 0
function addToTotal(n: number) {
  total += n  // 사이드 이펙트
}

// ✅ 순수 함수
function add(a: number, b: number): number {
  return a + b
}
```

### 응집도 (Cohesion)
관련된 것끼리 모아라. 같이 변하는 것은 같은 곳에.

```
features/
  payment/
    PaymentForm.tsx   # UI + 로직 + 타입 + 테스트 한 폴더에
    usePayment.ts
    payment.types.ts
    payment.test.ts
```

### 결합도 (Coupling)
의존성은 단방향, 최소로. 변경의 파급 효과를 제한.

- Props drilling 3단계 이상 → Context 또는 상태 관리 고려
- 컴포넌트가 전역 상태에 직접 접근하지 않고 props/hooks로만 통신

---

## 2. 정적 분석 도구

### ESLint
```json
{
  "extends": [
    "next/core-web-vitals",
    "plugin:@typescript-eslint/recommended"
  ],
  "rules": {
    "no-console": "warn",
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": "error"
  }
}
```

### TypeScript strict mode
```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true
  }
}
```

### Prettier
```json
{
  "semi": false,
  "singleQuote": true,
  "trailingComma": "es5",
  "printWidth": 100
}
```

---

## 3. 코드 리뷰 원칙

**리뷰어:**
- 비판이 아닌 개선 제안: "이렇게 하면 어떨까요?" 형식
- nitpick은 `nit:` 접두어로 (blocking 아님)
- 1회 리뷰에 코멘트가 너무 많으면 PR 분리 요청

**작성자:**
- PR은 400줄 이하 권장
- PR 설명에 "왜" 포함 (what은 코드로 알 수 있음)
- UI 변경 시 스크린샷/영상 첨부

---

## 4. 네이밍 컨벤션

| 대상 | 컨벤션 | 예시 |
|------|--------|------|
| 컴포넌트 | PascalCase | `UserProfile` |
| 함수/변수 | camelCase | `getUserName` |
| 상수 | SCREAMING_SNAKE | `MAX_RETRY_COUNT` |
| 타입/인터페이스 | PascalCase | `UserProps` |
| 파일(컴포넌트) | PascalCase | `UserProfile.tsx` |
| 파일(유틸) | kebab-case | `format-date.ts` |

---

## 5. 주석 원칙

```ts
// ✅ 좋은 주석 — "왜"를 설명
// Safari에서 scroll-behavior: smooth가 position: sticky와 충돌하는 버그 우회
// https://bugs.webkit.org/show_bug.cgi?id=12345
element.scrollTop = targetOffset

// ❌ 나쁜 주석 — 코드만 반복
// i를 1 증가시킨다
i++
```

---

## 6. 안티패턴

- **매직 넘버**: `timeout(3000)` → `timeout(REQUEST_TIMEOUT_MS)`
- **불리언 파라미터**: `render(true)` → `render({ isVisible: true })`
- **God Component**: 500줄 넘는 컴포넌트 → 분리 필요
- **주석 처리된 코드**: 버전 관리 시스템 믿고 삭제
- **TODO 방치**: 날짜와 담당자 없는 TODO는 영원히 안 됨
