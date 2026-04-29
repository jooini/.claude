# Design System

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/design-system

---

## 1. 디자인 시스템이란?

재사용 가능한 컴포넌트, 패턴, 가이드라인의 집합.
목표: **일관성**, **개발 속도**, **디자인-개발 언어 통일**.

---

## 2. 컴포넌트 계층

```
Tokens (색상, 타이포, 간격, 그림자)
  └── Primitives (Button, Input, Icon)
        └── Compositions (Form, Card, Modal)
              └── Patterns (LoginForm, DataTable)
```

---

## 3. 토큰 시스템

```ts
// tokens/colors.ts
export const colors = {
  // 시맨틱 토큰 — 의미 기반
  primary:   { DEFAULT: '#3b82f6', hover: '#2563eb', foreground: '#ffffff' },
  secondary: { DEFAULT: '#6b7280', hover: '#4b5563', foreground: '#ffffff' },
  destructive: { DEFAULT: '#ef4444', hover: '#dc2626', foreground: '#ffffff' },

  // 피드백
  success: '#22c55e',
  warning: '#f59e0b',
  error:   '#ef4444',
  info:    '#3b82f6',

  // 중립
  background: '#ffffff',
  foreground: '#0f172a',
  muted:      '#f1f5f9',
  border:     '#e2e8f0',
}

// tokens/typography.ts
export const typography = {
  fontFamily: {
    sans: ['Inter', 'sans-serif'],
    mono: ['JetBrains Mono', 'monospace'],
  },
  fontSize: {
    xs:   ['0.75rem',  { lineHeight: '1rem' }],
    sm:   ['0.875rem', { lineHeight: '1.25rem' }],
    base: ['1rem',     { lineHeight: '1.5rem' }],
    lg:   ['1.125rem', { lineHeight: '1.75rem' }],
    xl:   ['1.25rem',  { lineHeight: '1.75rem' }],
    '2xl':['1.5rem',   { lineHeight: '2rem' }],
  },
}

// tokens/spacing.ts — 8pt grid
export const spacing = {
  px: '1px',
  0.5: '0.125rem',  // 2px
  1:   '0.25rem',   // 4px
  2:   '0.5rem',    // 8px
  3:   '0.75rem',   // 12px
  4:   '1rem',      // 16px
  6:   '1.5rem',    // 24px
  8:   '2rem',      // 32px
  12:  '3rem',      // 48px
}
```

---

## 4. Primitive 컴포넌트

### Button

```tsx
// 앞선 Styling 섹션의 CVA 패턴 참고
// 모든 상태 구현 필수: default, hover, focus, active, disabled, loading

interface ButtonProps extends VariantProps<typeof buttonVariants> {
  isLoading?: boolean
  leftIcon?: ReactNode
  rightIcon?: ReactNode
}

export function Button({ isLoading, leftIcon, rightIcon, children, ...props }: ButtonProps) {
  return (
    <button className={buttonVariants(props)} disabled={isLoading || props.disabled}>
      {isLoading
        ? <Spinner className="mr-2 h-4 w-4" />
        : leftIcon && <span className="mr-2">{leftIcon}</span>
      }
      {children}
      {rightIcon && <span className="ml-2">{rightIcon}</span>}
    </button>
  )
}
```

### Input

```tsx
const inputVariants = cva(
  'flex w-full rounded-md border bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50',
  {
    variants: {
      state: {
        default: 'border-input',
        error:   'border-destructive focus-visible:ring-destructive',
        success: 'border-success',
      },
    },
    defaultVariants: { state: 'default' },
  }
)

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  state?: 'default' | 'error' | 'success'
  helperText?: string
  errorMessage?: string
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ state, helperText, errorMessage, className, ...props }, ref) => {
    const inputState = errorMessage ? 'error' : state
    return (
      <div className="space-y-1">
        <input ref={ref} className={cn(inputVariants({ state: inputState }), className)} {...props} />
        {errorMessage && <p className="text-sm text-destructive">{errorMessage}</p>}
        {!errorMessage && helperText && <p className="text-sm text-muted-foreground">{helperText}</p>}
      </div>
    )
  }
)
```

---

## 5. Storybook 문서화

```tsx
// Button.stories.tsx
import type { Meta, StoryObj } from '@storybook/react'
import { Button } from './Button'

const meta: Meta<typeof Button> = {
  component: Button,
  tags: ['autodocs'],
  argTypes: {
    variant: { control: 'select' },
    size: { control: 'select' },
  },
}
export default meta

type Story = StoryObj<typeof Button>

export const Default: Story = {
  args: { children: '버튼', variant: 'default', size: 'md' },
}

export const AllVariants: Story = {
  render: () => (
    <div className="flex gap-2">
      <Button variant="default">Default</Button>
      <Button variant="destructive">Destructive</Button>
      <Button variant="outline">Outline</Button>
      <Button variant="ghost">Ghost</Button>
    </div>
  ),
}

export const Loading: Story = {
  args: { children: '저장 중', isLoading: true },
}
```

---

## 6. 버전 관리와 배포

```json
// package.json (디자인 시스템 패키지)
{
  "name": "@company/design-system",
  "version": "1.2.0",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": { "import": "./dist/index.js" },
    "./styles": "./dist/styles.css"
  }
}
```

**Breaking change 관리:**
- Major: 컴포넌트 삭제, props 제거 → MIGRATION.md 작성
- Minor: 새 컴포넌트, 새 props 추가
- Patch: 버그 수정, 스타일 미세 조정

---

## 7. 안티패턴

- **원자 컴포넌트에 비즈니스 로직**: Button에 로그인 로직 X
- **props 폭발**: 20개 넘는 props → 합성으로 분리
- **디자인 토큰 우회**: `#3b82f6` 하드코딩 대신 토큰 사용
- **Storybook 미관리**: 컴포넌트 변경 후 Story 미업데이트
- **접근성 무시**: aria 속성, 키보드 네비게이션 필수
