# shadcn Patterns

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/shadcn-patterns

---

## 1. shadcn/ui란?

Radix UI 기반의 Copy-paste 컴포넌트 라이브러리. 설치하는 의존성이 아니라 **코드를 복사해서 프로젝트에 포함**하는 방식.

**핵심 특징:**
- **Copy-paste 철학**: 컴포넌트 코드가 내 프로젝트에 직접 포함 → 완전한 커스터마이징 가능
- **Radix UI Primitives**: 접근성이 내장된 headless 컴포넌트
- **Tailwind CSS**: 스타일링은 Tailwind 유틸리티 클래스로
- **TypeScript**: 완전한 타입 지원
- **테마**: CSS Variables 기반으로 손쉬운 테마 전환

---

## 2. 디자이너 관점의 shadcn 이해

### 컴포넌트 구조

```
shadcn 컴포넌트
├── Radix Primitive  (behavior + accessibility)
├── Tailwind Classes (styling)
└── Variants (CVA - Class Variance Authority)
```

**예시: Button**
```tsx
// 변형(variants)이 명확히 정의됨
const buttonVariants = cva(
  "inline-flex items-center justify-content...",  // base
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        destructive: "bg-destructive text-destructive-foreground",
        outline: "border border-input bg-background hover:bg-accent",
        secondary: "bg-secondary text-secondary-foreground",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-9 rounded-md px-3",
        lg: "h-11 rounded-md px-8",
        icon: "h-10 w-10",
      },
    },
  }
)
```

### 디자인 토큰 연결

shadcn은 CSS Variables로 테마를 관리:

```css
:root {
  --background: 0 0% 100%;
  --foreground: 222.2 84% 4.9%;
  --primary: 222.2 47.4% 11.2%;
  --primary-foreground: 210 40% 98%;
  --secondary: 210 40% 96.1%;
  /* ... */
}

.dark {
  --background: 222.2 84% 4.9%;
  --foreground: 210 40% 98%;
  /* ... */
}
```

**디자이너에게 중요한 것**: 이 변수들을 Figma의 색상 스타일과 1:1로 매핑하면 디자인-코드 일관성 유지 가능.

---

## 3. 주요 컴포넌트 패턴

### Dialog / Modal

```
Dialog
├── DialogTrigger  ← 열기 트리거
├── DialogContent  ← 모달 본문
│   ├── DialogHeader
│   │   ├── DialogTitle
│   │   └── DialogDescription
│   └── DialogFooter
│       ├── Cancel Button
│       └── Confirm Button
└── (자동 오버레이, 포커스 트랩, ESC 닫기)
```

**접근성 자동 처리**: Radix가 `aria-modal`, `role="dialog"`, 포커스 트랩을 자동으로 처리.

### Form + React Hook Form

shadcn의 Form 컴포넌트는 React Hook Form과 통합:

```
Form
├── FormField
│   ├── FormLabel
│   ├── FormControl  ← Input, Select 등 감싸기
│   ├── FormDescription
│   └── FormMessage  ← 에러 메시지 (자동 연결)
```

**패턴**: `FormMessage`가 `FormField`의 에러 상태를 자동으로 읽어서 표시.

### Command (검색/커맨드 팔레트)

```
Command
├── CommandInput      ← 검색 입력
├── CommandList
│   ├── CommandEmpty  ← 결과 없음
│   ├── CommandGroup
│   │   └── CommandItem  ← 선택 항목
│   └── CommandSeparator
```

`<PopoverContent>`와 조합하여 Combobox 구현 가능.

### DataTable + TanStack Table

```tsx
// 컬럼 정의
const columns: ColumnDef<Payment>[] = [
  { accessorKey: "status", header: "Status" },
  { accessorKey: "amount", header: "Amount" },
  // 정렬, 필터, 선택 등 자동 처리
]
```

TanStack Table의 정렬, 필터, 페이지네이션을 shadcn DataTable 컴포넌트로 구현.

---

## 4. 커스터마이징 패턴

### 컴포넌트 확장

```tsx
// 기본 Button을 확장한 LoadingButton
interface LoadingButtonProps extends ButtonProps {
  loading?: boolean
}

export function LoadingButton({ loading, children, ...props }: LoadingButtonProps) {
  return (
    <Button disabled={loading} {...props}>
      {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
      {children}
    </Button>
  )
}
```

### 테마 커스터마이징

```css
/* globals.css에서 토큰 값만 변경 */
:root {
  --primary: 262.1 83.3% 57.8%;  /* 보라색 브랜드로 변경 */
  --radius: 0.75rem;              /* 더 둥근 모서리 */
}
```

Figma에서 Primary 색상을 변경하면 CSS Variable만 업데이트하면 됨.

---

## 5. 디자이너-개발자 협업 패턴

### Figma에서 shadcn 컴포넌트 표현

shadcn의 변형을 Figma Variants로 1:1 매핑:
- Button variant: `default`, `destructive`, `outline`, `secondary`, `ghost`, `link`
- Button size: `default`, `sm`, `lg`, `icon`

### 커스텀 컴포넌트 추가 시

1. 기존 shadcn 컴포넌트로 해결 가능한지 먼저 확인
2. 불가능하다면 shadcn 패턴을 따라 새 컴포넌트 설계:
   - CVA로 variants 정의
   - CSS Variables로 색상 참조
   - Radix Primitive 활용 (접근성)

---

## 6. 자주 쓰는 조합 패턴

| 패턴 | 사용 컴포넌트 |
|------|-------------|
| 확인 다이얼로그 | AlertDialog |
| 드롭다운 메뉴 | DropdownMenu |
| 자동완성/검색 | Command + Popover |
| 날짜 선택 | Calendar + Popover |
| 폼 + 유효성 | Form + react-hook-form + zod |
| 데이터 테이블 | DataTable + TanStack Table |
| 알림 토스트 | Sonner (또는 shadcn Toast) |
| 로딩 상태 | Skeleton |
| 사이드 패널 | Sheet |

---

## 7. 안티패턴

- **모든 것을 커스터마이징**: shadcn 기본 스타일에서 너무 많이 벗어나면 유지보수 어려움
- **CSS Variables 무시**: `bg-[#3b82f6]` 하드코딩 대신 `bg-primary` 사용
- **접근성 우회**: Radix의 접근성 Props를 제거하지 않기
- **불필요한 컴포넌트 추가**: `npx shadcn@latest add` 남발 → 번들 크기 증가
