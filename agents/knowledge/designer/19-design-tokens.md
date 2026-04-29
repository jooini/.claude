# Design Tokens

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/design-tokens

---

## 1. 디자인 토큰이란?

디자인 결정을 **이름 있는 값(named values)**으로 추상화한 것. 색상, 타이포, 간격, 그림자 등 시각적 속성을 플랫폼/도구 독립적으로 정의.

```
#3b82f6  →  color.blue.500  →  color.primary  →  button.bg
(값)        (primitive)        (semantic)        (component)
```

**왜 토큰인가?**
- **일관성**: 하드코딩된 값 → 중앙 관리 값
- **테마 지원**: 토큰 값만 교체하면 다크모드/브랜드 테마
- **디자인-코드 동기화**: Figma Variables = CSS Custom Properties
- **스케일**: 새 플랫폼 추가 시 토큰만 변환

---

## 2. 토큰 3-Layer 구조

### Layer 1: Primitive Tokens (원시 토큰)

가장 기본적인 값. 색상 팔레트, 폰트 크기 스케일 등 순수한 값.

```css
/* Colors */
--blue-500: #3b82f6;
--red-500: #ef4444;
--gray-50: #f9fafb;
--gray-900: #111827;

/* Typography */
--font-size-xs: 0.75rem;    /* 12px */
--font-size-sm: 0.875rem;   /* 14px */
--font-size-base: 1rem;     /* 16px */
--font-size-lg: 1.125rem;   /* 18px */
--font-size-xl: 1.25rem;    /* 20px */
--font-size-2xl: 1.5rem;    /* 24px */

/* Spacing */
--space-1: 0.25rem;   /* 4px */
--space-2: 0.5rem;    /* 8px */
--space-4: 1rem;      /* 16px */
--space-6: 1.5rem;    /* 24px */
--space-8: 2rem;      /* 32px */

/* Border Radius */
--radius-sm: 0.25rem;
--radius-md: 0.375rem;
--radius-lg: 0.5rem;
--radius-full: 9999px;

/* Shadows */
--shadow-sm: 0 1px 3px 0 rgb(0 0 0 / 0.1);
--shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1);
--shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1);
```

### Layer 2: Semantic Tokens (의미적 토큰)

Primitive에 **의미/용도**를 부여. 테마 전환의 핵심.

```css
:root {
  /* 배경 */
  --color-bg-primary: var(--gray-50);
  --color-bg-secondary: white;
  --color-bg-inverse: var(--gray-900);

  /* 텍스트 */
  --color-text-primary: var(--gray-900);
  --color-text-secondary: var(--gray-500);
  --color-text-inverse: white;

  /* 브랜드 */
  --color-primary: var(--blue-500);
  --color-primary-hover: var(--blue-600);

  /* 상태 */
  --color-success: var(--green-600);
  --color-error: var(--red-600);
  --color-warning: var(--amber-600);

  /* 보더 */
  --color-border: var(--gray-200);
  --color-border-focus: var(--blue-500);
}

.dark {
  --color-bg-primary: var(--gray-950);
  --color-bg-secondary: var(--gray-900);
  --color-text-primary: var(--gray-50);
  --color-text-secondary: var(--gray-400);
  --color-primary: var(--blue-400);  /* 어두운 배경에서 밝은 shade */
  --color-border: var(--gray-800);
}
```

### Layer 3: Component Tokens (선택적)

특정 컴포넌트에 바인딩된 토큰.

```css
/* Button */
--button-bg: var(--color-primary);
--button-bg-hover: var(--color-primary-hover);
--button-text: white;
--button-radius: var(--radius-md);
--button-padding-x: var(--space-4);
--button-padding-y: var(--space-2);
```

---

## 3. Figma Variables와 연동

**Figma Variables = CSS Custom Properties**

```
Figma Collections:
├── Primitive     → CSS :root 변수
├── Semantic      → CSS :root + .dark 변수
└── Component     → 컴포넌트별 CSS 변수
```

**Figma Variable 네이밍:**
- 컬렉션 이름: `primitive`, `semantic`, `component`
- 변수 이름: `color/blue/500`, `color/text/primary`
- 슬래시 구분자 → Figma에서 그룹으로 자동 처리

**모드(Mode) 활용:**
- `Light` 모드와 `Dark` 모드를 같은 변수의 다른 값으로
- Figma 프레임에서 모드 전환 → 전체 디자인 즉시 업데이트

---

## 4. 토큰 관리 도구

| 도구 | 역할 |
|------|------|
| Figma Variables | 디자인 측 토큰 관리 |
| Style Dictionary | 토큰 → CSS/JS/iOS/Android 변환 |
| Theo (Salesforce) | 토큰 변환 |
| Token Studio (Figma 플러그인) | JSON 기반 토큰 관리, 코드 연동 |
| Design Token Community Group | W3C 토큰 표준 (DTCG) |

**토큰 파이프라인 예시:**
```
Figma Variables → Token Studio 플러그인 → tokens.json
→ Style Dictionary 빌드 → CSS Variables / Tailwind config / iOS
```

---

## 5. JSON 토큰 구조 (DTCG 표준)

```json
{
  "color": {
    "blue": {
      "500": {
        "$value": "#3b82f6",
        "$type": "color",
        "$description": "Primary blue"
      }
    },
    "primary": {
      "$value": "{color.blue.500}",
      "$type": "color",
      "$description": "Brand primary color"
    }
  },
  "spacing": {
    "4": {
      "$value": "16px",
      "$type": "dimension"
    }
  }
}
```

---

## 6. 안티패턴

- **토큰 없이 하드코딩**: `color: #3b82f6` 직접 사용. 나중에 수정 불가
- **Primitive를 직접 사용**: `var(--blue-500)` 대신 `var(--color-primary)` 사용
- **너무 많은 Component 토큰**: Layer 3는 꼭 필요할 때만
- **일관성 없는 네이밍**: `btn-color`, `button-bg`, `ButtonBackground` 혼재
- **토큰 업데이트 안 함**: 코드는 업데이트했는데 Figma는 그대로 → 불일치
