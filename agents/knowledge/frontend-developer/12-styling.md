# Styling

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/styling

---

## 1. 스타일링 방식 비교

| 방식 | 장점 | 단점 | 적합한 상황 |
|------|------|------|------------|
| Tailwind CSS | 빠른 개발, 일관성 | 클래스 길어짐 | 대부분의 프로젝트 |
| CSS Modules | 스코핑, 네이밍 자유 | 파일 분리 | 복잡한 애니메이션 |
| CSS-in-JS | 동적 스타일 | 번들 크기, SSR 복잡 | 테마가 복잡할 때 |

현재 표준: **Tailwind CSS + CSS Variables (토큰)**

---

## 2. Tailwind CSS 핵심 패턴

### 기본 사용

```tsx
// 직관적인 유틸리티 클래스
function Card({ title, children }: CardProps) {
  return (
    <div className="rounded-lg border bg-white p-6 shadow-sm">
      <h2 className="mb-4 text-xl font-semibold text-gray-900">{title}</h2>
      <div className="text-gray-600">{children}</div>
    </div>
  )
}
```

### 반응형

```tsx
// 모바일 퍼스트: sm(640px), md(768px), lg(1024px), xl(1280px)
<div className="
  grid grid-cols-1        // 모바일: 1열
  sm:grid-cols-2          // 640px+: 2열
  lg:grid-cols-3          // 1024px+: 3열
  gap-4
">
```

### 상태 변형

```tsx
<button className="
  bg-blue-500
  hover:bg-blue-600       // 호버
  focus:ring-2            // 포커스
  focus:ring-blue-300
  disabled:opacity-50     // 비활성
  disabled:cursor-not-allowed
  active:scale-95         // 클릭
  transition-all
">
```

### 다크 모드

```tsx
<div className="
  bg-white text-gray-900        // 라이트
  dark:bg-gray-900 dark:text-gray-100  // 다크
">
```

---

## 3. CVA (Class Variance Authority)

컴포넌트 변형을 타입 안전하게 관리.

```tsx
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const buttonVariants = cva(
  // base — 모든 변형에 공통 적용
  'inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        default:     'bg-primary text-primary-foreground hover:bg-primary/90',
        destructive: 'bg-destructive text-destructive-foreground hover:bg-destructive/90',
        outline:     'border border-input bg-background hover:bg-accent',
        ghost:       'hover:bg-accent hover:text-accent-foreground',
      },
      size: {
        sm: 'h-9 px-3',
        md: 'h-10 px-4',
        lg: 'h-11 px-8',
        icon: 'h-10 w-10',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'md',
    },
  }
)

interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  className?: string
}

export function Button({ variant, size, className, ...props }: ButtonProps) {
  return (
    <button
      className={cn(buttonVariants({ variant, size }), className)}
      {...props}
    />
  )
}

// 사용
<Button variant="destructive" size="sm">삭제</Button>
```

### cn 유틸리티

```ts
// lib/utils.ts
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

// clsx: 조건부 클래스 조합
// twMerge: Tailwind 충돌 클래스 해결 (bg-red-500 + bg-blue-500 → bg-blue-500)
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

// 사용
cn('px-4 py-2', isActive && 'bg-blue-500', className)
```

---

## 4. CSS Variables와 테마

```css
/* globals.css */
:root {
  --background: 0 0% 100%;
  --foreground: 222.2 84% 4.9%;
  --primary: 221.2 83.2% 53.3%;
  --primary-foreground: 210 40% 98%;
  --radius: 0.5rem;
}

.dark {
  --background: 222.2 84% 4.9%;
  --foreground: 210 40% 98%;
  --primary: 217.2 91.2% 59.8%;
}
```

```ts
// tailwind.config.ts
export default {
  theme: {
    extend: {
      colors: {
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
      },
    },
  },
}
```

---

## 5. CSS Modules (복잡한 애니메이션)

Tailwind로 표현하기 어려운 복잡한 스타일에만 사용.

```css
/* components/Spinner.module.css */
.spinner {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to   { transform: rotate(360deg); }
}
```

```tsx
import styles from './Spinner.module.css'

export function Spinner() {
  return <div className={cn('h-4 w-4 border-2 rounded-full', styles.spinner)} />
}
```

---

## 6. 안티패턴

- **인라인 style 객체**: `style={{ color: 'red' }}` → Tailwind 클래스로
- **!important 남용**: 명시도 문제 → 구조 개선
- **매직 넘버**: `mt-[17px]` → 디자인 토큰 사용
- **클래스 조건부 처리에 템플릿 리터럴**: `` `bg-${color}-500` `` → Tailwind가 빌드 시 purge → `cn()` + 명시적 클래스로
- **전역 CSS 과다**: 컴포넌트 스코핑 활용
