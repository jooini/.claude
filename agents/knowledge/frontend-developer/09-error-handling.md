# Error Handling

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/error-handling

---

## 1. 에러의 종류

| 종류 | 예시 | 처리 방법 |
|------|------|----------|
| **네트워크 에러** | 요청 실패, 타임아웃 | 재시도 + 토스트 |
| **HTTP 에러** | 401, 403, 404, 500 | 상태코드별 처리 |
| **유효성 에러** | 폼 입력 오류 | 인라인 에러 메시지 |
| **런타임 에러** | TypeError, 예외 | Error Boundary |
| **예상치 못한 에러** | JS 버그 | Error Boundary + 로깅 |

---

## 2. Error Boundary

React 컴포넌트 트리의 에러를 잡는 바운더리.

```tsx
// components/error-boundary.tsx
'use client'
import { Component, ReactNode } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
  onError?: (error: Error) => void
}

interface State {
  hasError: boolean
  error: Error | null
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: { componentStack: string }) {
    this.props.onError?.(error)
    // 에러 로깅 서비스로 전송
    logger.error(error, info.componentStack)
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? <DefaultErrorFallback error={this.state.error} />
    }
    return this.props.children
  }
}

// 사용
<ErrorBoundary fallback={<SectionError />}>
  <ComplexWidget />
</ErrorBoundary>
```

### Next.js error.tsx (자동 Error Boundary)

```tsx
// app/dashboard/error.tsx
'use client'
export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    logger.error(error)  // 에러 로깅
  }, [error])

  return (
    <div className="error-container">
      <h2>오류가 발생했습니다</h2>
      <p>{error.message}</p>
      <button onClick={reset}>다시 시도</button>
    </div>
  )
}
```

---

## 3. API 에러 처리

```ts
// lib/api/error.ts
export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message)
    this.name = 'ApiError'
  }
}

// lib/api/client.ts
async function request<T>(url: string, options?: RequestInit): Promise<T> {
  const res = await fetch(url, options)

  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new ApiError(
      res.status,
      body.code ?? 'UNKNOWN',
      body.message ?? '요청 처리 중 오류가 발생했습니다',
    )
  }

  return res.json()
}
```

### TanStack Query에서 에러 처리

```tsx
function UserProfile({ id }: { id: string }) {
  const { data, error, isError } = useUser(id)

  if (isError) {
    if (error instanceof ApiError) {
      if (error.status === 404) return <NotFound />
      if (error.status === 403) return <Forbidden />
    }
    return <GenericError message={error.message} />
  }

  return <Profile user={data} />
}

// 전역 에러 핸들러
const queryClient = new QueryClient({
  queryCache: new QueryCache({
    onError: (error) => {
      if (error instanceof ApiError && error.status === 401) {
        router.push('/login')
      }
    },
  }),
})
```

---

## 4. 토스트 에러 알림

```tsx
// 일시적 에러 (네트워크 실패 등) — 토스트
import { toast } from 'sonner'

const { mutate } = useMutation({
  mutationFn: updateUser,
  onError: (error) => {
    toast.error(
      error instanceof ApiError
        ? error.message
        : '알 수 없는 오류가 발생했습니다'
    )
  },
})
```

**토스트 vs 인라인 에러 사용 기준:**
- 토스트: 일시적 에러, 시스템 알림, 네트워크 실패
- 인라인: 폼 유효성, 필드 수준 에러

---

## 5. 낙관적 업데이트와 롤백

```ts
const { mutate } = useMutation({
  mutationFn: toggleLike,
  onMutate: async (postId) => {
    // 진행 중인 쿼리 취소
    await queryClient.cancelQueries({ queryKey: ['post', postId] })

    // 현재 상태 저장 (롤백용)
    const previous = queryClient.getQueryData(['post', postId])

    // 낙관적으로 UI 업데이트
    queryClient.setQueryData(['post', postId], (old: Post) => ({
      ...old,
      liked: !old.liked,
      likeCount: old.liked ? old.likeCount - 1 : old.likeCount + 1,
    }))

    return { previous }
  },
  onError: (_, postId, context) => {
    // 실패 시 롤백
    queryClient.setQueryData(['post', postId], context?.previous)
    toast.error('좋아요 처리에 실패했습니다')
  },
})
```

---

## 6. 에러 로깅

```ts
// lib/logger.ts
export const logger = {
  error: (error: Error, context?: Record<string, unknown>) => {
    if (process.env.NODE_ENV === 'production') {
      // Sentry, Datadog 등으로 전송
      Sentry.captureException(error, { extra: context })
    } else {
      console.error(error, context)
    }
  },
}
```

---

## 7. 안티패턴

- **빈 catch 블록**: 에러를 삼키면 디버깅 불가
- **모든 에러에 동일한 메시지**: "오류 발생" → 구체적인 안내로
- **에러 로깅 없음**: 운영 환경에서 버그 파악 불가
- **Error Boundary 없음**: 일부 컴포넌트 에러가 전체 앱 크래시
- **재시도 없는 네트워크 에러**: TanStack Query `retry` 옵션 활용
