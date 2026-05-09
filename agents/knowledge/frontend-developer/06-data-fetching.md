# Data Fetching

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/data-fetching

---

## 1. Next.js에서 데이터 페칭 전략

| 방식 | 실행 위치 | 언제 사용 |
|------|----------|----------|
| Server Component fetch | 서버 | 초기 데이터, SEO 필요 |
| TanStack Query | 클라이언트 | 인터랙티브한 데이터, 캐싱 |
| Server Actions | 서버 | 뮤테이션, 폼 제출 |
| Route Handlers | 서버 | 외부에 API 노출 |

---

## 2. Server Component에서 fetch

```tsx
// app/users/page.tsx — 서버 컴포넌트 (기본)
async function UsersPage() {
  // 서버에서 직접 fetch — 클라이언트에 API key 노출 없음
  const users = await fetch('https://api.example.com/users', {
    // Next.js fetch 확장 옵션
    next: {
      revalidate: 60,        // 60초마다 ISR 재검증
      // revalidate: 0       // 항상 최신 (SSR)
      // tags: ['users']     // on-demand revalidation 태그
    },
    cache: 'force-cache',    // 기본값 — 빌드 시 캐시 (SSG)
    // cache: 'no-store'     // 캐시 없음 (SSR)
  }).then(r => r.json())

  return <UserList users={users} />
}
```

### 병렬 fetch

```tsx
async function DashboardPage() {
  // ❌ 순차 — 총 2초
  const users = await fetchUsers()      // 1초
  const stats = await fetchStats()      // 1초

  // ✅ 병렬 — 총 1초
  const [users, stats] = await Promise.all([
    fetchUsers(),
    fetchStats(),
  ])

  return <Dashboard users={users} stats={stats} />
}
```

### Streaming with Suspense

```tsx
import { Suspense } from 'react'

async function DashboardPage() {
  return (
    <div>
      <h1>대시보드</h1>
      {/* 빠른 데이터는 먼저 표시 */}
      <Suspense fallback={<UsersSkeleton />}>
        <UsersSection />   {/* 느린 데이터 — 별도 스트리밍 */}
      </Suspense>
    </div>
  )
}

async function UsersSection() {
  const users = await fetchUsers()  // 이 컴포넌트만 지연
  return <UserList users={users} />
}
```

---

## 3. TanStack Query (클라이언트 사이드)

```tsx
// providers/query-provider.tsx
'use client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60 * 1000,   // 1분
      retry: 1,
    },
  },
})

export function QueryProvider({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
}
```

```ts
// features/users/hooks/useUsers.ts
export function useUsers(filters?: UserFilters) {
  return useQuery({
    queryKey: ['users', filters],
    queryFn: () => usersApi.getUsers(filters),
    select: (data) => data.sort((a, b) => a.name.localeCompare(b.name)),  // 변환
  })
}

export function useUser(id: string) {
  return useQuery({
    queryKey: ['users', id],
    queryFn: () => usersApi.getUser(id),
    enabled: !!id,  // id 없으면 쿼리 실행 안 함
  })
}

export function useCreateUser() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: usersApi.createUser,
    onSuccess: (newUser) => {
      // 낙관적 업데이트 — 서버 응답 전에 UI 먼저 반영
      queryClient.setQueryData(['users'], (old: User[]) => [...old, newUser])
    },
    onError: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })  // 실패 시 롤백
    },
  })
}
```

### Server + Client 하이브리드 (prefetch)

```tsx
// app/users/page.tsx — 서버에서 prefetch
import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query'

async function UsersPage() {
  const queryClient = new QueryClient()
  await queryClient.prefetchQuery({
    queryKey: ['users'],
    queryFn: fetchUsers,
  })

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <UsersClient />  {/* 클라이언트에서 캐시 그대로 사용 */}
    </HydrationBoundary>
  )
}
```

---

## 4. API 레이어 구성

```ts
// lib/api/client.ts — 기본 fetch 래퍼
class ApiClient {
  private baseUrl: string

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl
  }

  async get<T>(path: string, options?: RequestInit): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options?.headers,
      },
    })
    if (!res.ok) throw new ApiError(res.status, await res.json())
    return res.json()
  }

  async post<T>(path: string, body: unknown): Promise<T> {
    return this.get<T>(path, {
      method: 'POST',
      body: JSON.stringify(body),
    })
  }
}

export const apiClient = new ApiClient(process.env.NEXT_PUBLIC_API_URL!)

// features/users/api/users.api.ts
export const usersApi = {
  getUsers: (filters?: UserFilters) =>
    apiClient.get<User[]>('/users', { next: { tags: ['users'] } }),
  getUser: (id: string) =>
    apiClient.get<User>(`/users/${id}`),
  createUser: (data: CreateUserDto) =>
    apiClient.post<User>('/users', data),
}
```

---

## 5. 에러 처리

```ts
class ApiError extends Error {
  constructor(
    public status: number,
    public data: unknown,
  ) {
    super(`API Error: ${status}`)
  }
}

// TanStack Query에서 에러 타입 활용
const { error } = useUsers()
if (error instanceof ApiError && error.status === 401) {
  // 로그인 페이지로
}
```

---

## 6. 안티패턴

- **useEffect + fetch**: TanStack Query로 대체
- **클라이언트에서 민감한 API 호출**: Server Component 또는 Route Handler로
- **waterfall fetch**: 가능하면 Promise.all 병렬화
- **에러 처리 없는 fetch**: 모든 fetch에 에러 핸들링
- **캐시 키 불일치**: 같은 데이터를 다른 키로 캐싱 → 중복 요청
