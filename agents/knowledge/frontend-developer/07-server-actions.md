# Server Actions

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/server-actions

---

## 1. Server Actions란?

Next.js 13.4+에서 도입. 서버에서 실행되는 함수를 클라이언트에서 직접 호출 가능.
API Route를 만들지 않고 서버 로직 실행 가능.

**적합한 사용처:**
- 폼 제출
- DB 직접 접근 (API 레이어 없이)
- 파일 업로드
- 캐시 revalidation

**부적합한 사용처:**
- 자주 호출되는 데이터 조회 (TanStack Query 사용)
- 외부에 API를 노출해야 하는 경우 (Route Handlers 사용)

---

## 2. 기본 사용법

```ts
// app/actions/user.actions.ts
'use server'  // 이 파일의 모든 함수가 Server Action

import { revalidatePath, revalidateTag } from 'next/cache'
import { redirect } from 'next/navigation'

export async function createUser(formData: FormData) {
  const name = formData.get('name') as string
  const email = formData.get('email') as string

  // 서버에서 직접 DB 접근
  await db.user.create({ data: { name, email } })

  revalidateTag('users')      // 캐시 무효화
  redirect('/users')          // 리다이렉트
}
```

### HTML form과 사용

```tsx
// Server Component에서 — JS 없이도 동작 (Progressive Enhancement)
export default function CreateUserPage() {
  return (
    <form action={createUser}>
      <input name="name" required />
      <input name="email" type="email" required />
      <button type="submit">생성</button>
    </form>
  )
}
```

---

## 3. React Hook Form + Server Actions

```tsx
'use client'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useTransition } from 'react'
import { createUser } from '@/app/actions/user.actions'

const schema = z.object({
  name: z.string().min(2, '이름은 2자 이상'),
  email: z.string().email('유효한 이메일'),
})

type FormValues = z.infer<typeof schema>

export function CreateUserForm() {
  const [isPending, startTransition] = useTransition()
  const form = useForm<FormValues>({ resolver: zodResolver(schema) })

  function onSubmit(data: FormValues) {
    startTransition(async () => {
      const formData = new FormData()
      formData.set('name', data.name)
      formData.set('email', data.email)
      await createUser(formData)
    })
  }

  return (
    <form onSubmit={form.handleSubmit(onSubmit)}>
      <input {...form.register('name')} />
      {form.formState.errors.name && <span>{form.formState.errors.name.message}</span>}
      <input {...form.register('email')} />
      <button type="submit" disabled={isPending}>
        {isPending ? '처리 중...' : '생성'}
      </button>
    </form>
  )
}
```

---

## 4. 응답 처리 (useActionState)

```tsx
'use server'
// 상태를 반환하는 Server Action
export async function createUser(
  prevState: { error: string | null; success: boolean },
  formData: FormData,
) {
  try {
    await db.user.create({ ... })
    revalidateTag('users')
    return { error: null, success: true }
  } catch (e) {
    return { error: '생성 실패', success: false }
  }
}

// 클라이언트
'use client'
import { useActionState } from 'react'

export function CreateUserForm() {
  const [state, action, isPending] = useActionState(createUser, {
    error: null,
    success: false,
  })

  return (
    <form action={action}>
      {state.error && <p className="text-red-500">{state.error}</p>}
      {state.success && <p className="text-green-500">생성 완료!</p>}
      <input name="name" />
      <button disabled={isPending}>생성</button>
    </form>
  )
}
```

---

## 5. 유효성 검사

```ts
'use server'
import { z } from 'zod'

const CreateUserSchema = z.object({
  name: z.string().min(2).max(50),
  email: z.string().email(),
})

export async function createUser(formData: FormData) {
  // 서버에서도 반드시 검증 (클라이언트 검증만 믿지 말 것)
  const parsed = CreateUserSchema.safeParse({
    name: formData.get('name'),
    email: formData.get('email'),
  })

  if (!parsed.success) {
    return { error: parsed.error.flatten().fieldErrors }
  }

  await db.user.create({ data: parsed.data })
  revalidatePath('/users')
}
```

---

## 6. 인증 확인

```ts
'use server'
import { auth } from '@/lib/auth'

export async function deleteUser(userId: string) {
  // Server Action에서도 반드시 인증/권한 확인
  const session = await auth()
  if (!session?.user) throw new Error('Unauthorized')
  if (session.user.role !== 'admin') throw new Error('Forbidden')

  await db.user.delete({ where: { id: userId } })
  revalidateTag('users')
}
```

---

## 7. 안티패턴

- **클라이언트 검증만 믿기**: Server Action에서도 Zod로 재검증
- **인증 없이 민감한 작업**: 모든 Server Action에서 session 확인
- **대용량 데이터 조회에 사용**: 조회는 TanStack Query, 변경만 Server Actions
- **에러 처리 누락**: try-catch로 에러 상태 반환
