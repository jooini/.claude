# Routing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/routing

---

## 1. Next.js App Router 기본 구조

```
app/
  layout.tsx          # root layout — 모든 페이지에 적용
  page.tsx            # /
  loading.tsx         # 자동 Suspense 래핑
  error.tsx           # 에러 바운더리
  not-found.tsx       # 404

  dashboard/
    layout.tsx        # /dashboard/* 공통 레이아웃
    page.tsx          # /dashboard
    settings/
      page.tsx        # /dashboard/settings

  (auth)/             # route group — URL에 포함 안 됨
    login/
      page.tsx        # /login
    signup/
      page.tsx        # /signup

  blog/
    [slug]/
      page.tsx        # /blog/:slug (동적 라우트)
    [...slug]/
      page.tsx        # /blog/a/b/c (catch-all)
```

---

## 2. 레이아웃 패턴

### 중첩 레이아웃

```tsx
// app/layout.tsx — root
export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ko">
      <body>
        <Header />
        {children}
        <Footer />
      </body>
    </html>
  )
}

// app/dashboard/layout.tsx — dashboard 전용
export default function DashboardLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex">
      <Sidebar />
      <main className="flex-1">{children}</main>
    </div>
  )
}
```

### Route Groups로 레이아웃 분기

```
app/
  (marketing)/        # 마케팅 레이아웃
    layout.tsx
    page.tsx          # /
    about/page.tsx    # /about

  (app)/              # 앱 레이아웃 (로그인 필요)
    layout.tsx
    dashboard/page.tsx
    settings/page.tsx
```

---

## 3. 동적 라우트

```tsx
// app/users/[id]/page.tsx
interface Props {
  params: { id: string }
  searchParams: { tab?: string }
}

export default async function UserPage({ params, searchParams }: Props) {
  const user = await getUser(params.id)
  const tab = searchParams.tab ?? 'profile'

  return <UserDetail user={user} activeTab={tab} />
}

// 정적 생성 (SSG) — 빌드 타임에 생성할 경로 지정
export async function generateStaticParams() {
  const users = await getUsers()
  return users.map(user => ({ id: user.id }))
}
```

---

## 4. 네비게이션

```tsx
'use client'
import { useRouter, usePathname, useSearchParams } from 'next/navigation'
import Link from 'next/link'

// 선언적 — Link 컴포넌트 (권장)
<Link href="/dashboard">대시보드</Link>
<Link href={{ pathname: '/users', query: { status: 'active' } }}>활성 유저</Link>

// 프로그래매틱 — useRouter
const router = useRouter()
router.push('/dashboard')
router.replace('/login')    // 히스토리 교체 (뒤로가기 불가)
router.back()

// 현재 경로 확인
const pathname = usePathname()   // '/dashboard/settings'
const searchParams = useSearchParams()
const tab = searchParams.get('tab')
```

---

## 5. 라우트 보호 (인증 가드)

```tsx
// middleware.ts — Edge에서 실행, 모든 요청에 적용
import { NextRequest, NextResponse } from 'next/server'

export function middleware(request: NextRequest) {
  const token = request.cookies.get('token')?.value
  const isAuthPage = request.nextUrl.pathname.startsWith('/login')
  const isProtected = request.nextUrl.pathname.startsWith('/dashboard')

  if (isProtected && !token) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  if (isAuthPage && token) {
    return NextResponse.redirect(new URL('/dashboard', request.url))
  }

  return NextResponse.next()
}

export const config = {
  matcher: ['/dashboard/:path*', '/login'],
}
```

---

## 6. Parallel Routes & Intercepting Routes

### Parallel Routes — 동시에 여러 페이지 렌더

```
app/
  @modal/
    (.)photos/[id]/
      page.tsx       # 모달로 표시
  photos/
    [id]/
      page.tsx       # 직접 접근 시 전체 페이지
  layout.tsx         # { children, modal } props
```

```tsx
// app/layout.tsx
export default function Layout({
  children,
  modal,
}: {
  children: ReactNode
  modal: ReactNode
}) {
  return (
    <>
      {children}
      {modal}   {/* 모달은 별도 슬롯 */}
    </>
  )
}
```

---

## 7. 로딩 & 에러 처리

```tsx
// app/dashboard/loading.tsx — 자동으로 Suspense 래핑
export default function Loading() {
  return <DashboardSkeleton />
}

// app/dashboard/error.tsx — 에러 바운더리
'use client'
export default function Error({
  error,
  reset,
}: {
  error: Error
  reset: () => void
}) {
  return (
    <div>
      <p>오류가 발생했습니다: {error.message}</p>
      <button onClick={reset}>다시 시도</button>
    </div>
  )
}
```

---

## 8. 안티패턴

- **useEffect로 리다이렉트**: middleware 또는 서버 컴포넌트에서 처리
- **클라이언트에서 인증 체크**: 깜빡임 발생 → middleware로
- **동적 라우트 params를 문자열 그대로 사용**: 타입 검증 필요
- **레이아웃 중첩 남발**: 불필요한 re-render 유발
