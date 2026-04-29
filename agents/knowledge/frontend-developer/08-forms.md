# Forms

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/forms

---

## 1. 폼 라이브러리 선택

| 상황 | 권장 |
|------|------|
| 복잡한 폼 (10+ 필드, 동적 필드) | React Hook Form + Zod |
| 단순 폼 (2~3 필드) | useState + 직접 처리 |
| Server Component 폼 | HTML form + Server Actions |

---

## 2. React Hook Form + Zod 기본 세팅

```tsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

// 스키마 정의 — 유효성 규칙
const loginSchema = z.object({
  email: z.string().email('유효한 이메일을 입력하세요'),
  password: z.string().min(8, '비밀번호는 8자 이상'),
})

type LoginFormValues = z.infer<typeof loginSchema>  // 타입 자동 생성

export function LoginForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
    setError,
    reset,
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  })

  async function onSubmit(data: LoginFormValues) {
    try {
      await login(data)
      reset()
    } catch (e) {
      // 서버 에러를 특정 필드에 표시
      setError('email', { message: '이메일 또는 비밀번호가 틀렸습니다' })
    }
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <div>
        <input {...register('email')} type="email" placeholder="이메일" />
        {errors.email && <span className="error">{errors.email.message}</span>}
      </div>
      <div>
        <input {...register('password')} type="password" placeholder="비밀번호" />
        {errors.password && <span className="error">{errors.password.message}</span>}
      </div>
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? '로그인 중...' : '로그인'}
      </button>
    </form>
  )
}
```

---

## 3. shadcn/ui Form 컴포넌트와 통합

```tsx
import { Form, FormField, FormItem, FormLabel, FormControl, FormMessage } from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'

export function LoginForm() {
  const form = useForm<LoginFormValues>({ resolver: zodResolver(loginSchema) })

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem>
              <FormLabel>이메일</FormLabel>
              <FormControl>
                <Input type="email" {...field} />
              </FormControl>
              <FormMessage />  {/* 에러 메시지 자동 표시 */}
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="password"
          render={({ field }) => (
            <FormItem>
              <FormLabel>비밀번호</FormLabel>
              <FormControl>
                <Input type="password" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <Button type="submit" disabled={form.formState.isSubmitting}>
          로그인
        </Button>
      </form>
    </Form>
  )
}
```

---

## 4. Zod 스키마 패턴

```ts
// 복잡한 유효성 검사
const signupSchema = z.object({
  email: z.string().email(),
  password: z.string()
    .min(8)
    .regex(/[A-Z]/, '대문자 포함')
    .regex(/[0-9]/, '숫자 포함'),
  confirmPassword: z.string(),
  age: z.number().min(14, '14세 이상'),
  role: z.enum(['user', 'admin']),
  tags: z.array(z.string()).min(1, '태그를 하나 이상 선택'),
})
// 교차 필드 검증
.refine(data => data.password === data.confirmPassword, {
  message: '비밀번호가 일치하지 않습니다',
  path: ['confirmPassword'],
})

// 선택적 필드
const profileSchema = z.object({
  name: z.string().min(1),
  bio: z.string().max(200).optional(),
  website: z.string().url().optional().or(z.literal('')),
})
```

---

## 5. 동적 필드 (useFieldArray)

```tsx
import { useFieldArray } from 'react-hook-form'

const schema = z.object({
  items: z.array(z.object({
    name: z.string().min(1),
    quantity: z.number().min(1),
  })).min(1, '항목을 하나 이상 추가하세요'),
})

function OrderForm() {
  const form = useForm({ resolver: zodResolver(schema) })
  const { fields, append, remove } = useFieldArray({
    control: form.control,
    name: 'items',
  })

  return (
    <form onSubmit={form.handleSubmit(onSubmit)}>
      {fields.map((field, index) => (
        <div key={field.id}>
          <input {...form.register(`items.${index}.name`)} placeholder="품목" />
          <input {...form.register(`items.${index}.quantity`, { valueAsNumber: true })} type="number" />
          <button type="button" onClick={() => remove(index)}>삭제</button>
        </div>
      ))}
      <button type="button" onClick={() => append({ name: '', quantity: 1 })}>
        항목 추가
      </button>
      <button type="submit">주문</button>
    </form>
  )
}
```

---

## 6. 폼 UX 원칙

**에러 표시:**
- 제출 후 또는 필드에서 벗어날 때(onBlur) 표시 — 타이핑 중엔 표시 자제
- 에러는 필드 바로 아래에 인라인으로
- 에러 색상: 빨간색, 아이콘 함께

**로딩 상태:**
- 제출 버튼 비활성화 + 로딩 인디케이터
- 중복 제출 방지

**접근성:**
```tsx
<input
  {...register('email')}
  id="email"
  aria-describedby={errors.email ? 'email-error' : undefined}
  aria-invalid={!!errors.email}
/>
{errors.email && (
  <span id="email-error" role="alert">{errors.email.message}</span>
)}
```

---

## 7. 안티패턴

- **onChange마다 유효성 검사**: 타이핑 중 에러 → 사용자 경험 저하
- **서버 검증 생략**: 클라이언트 검증은 UX, 서버 검증은 보안
- **모든 상태를 useState로**: React Hook Form이 비제어 방식으로 더 성능 좋음
- **에러 메시지 없음**: "잘못됨" 대신 "이메일 형식이 올바르지 않습니다"
