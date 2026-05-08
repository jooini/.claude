# Async Patterns

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/async-patterns

---

## 1. Promise 패턴

```ts
// 병렬 실행
const [users, products] = await Promise.all([
  fetchUsers(),
  fetchProducts(),
])

// 일부 실패 허용 — 각각 결과/에러 확인
const results = await Promise.allSettled([
  fetchUsers(),
  fetchProducts(),
])
results.forEach(result => {
  if (result.status === 'fulfilled') console.log(result.value)
  else console.error(result.reason)
})

// 가장 빠른 것만 — 레이스
const fastest = await Promise.race([
  fetchFromServer1(),
  fetchFromServer2(),
])

// 하나라도 성공하면 — any
const first = await Promise.any([
  fetchFromMirror1(),
  fetchFromMirror2(),
])
```

---

## 2. 에러 처리 패턴

```ts
// try-catch보다 명시적인 Result 패턴
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E }

async function fetchUser(id: string): Promise<Result<User>> {
  try {
    const user = await api.getUser(id)
    return { ok: true, value: user }
  } catch (error) {
    return { ok: false, error: error as Error }
  }
}

// 사용 — 에러 처리 강제
const result = await fetchUser(id)
if (!result.ok) {
  showError(result.error.message)
  return
}
console.log(result.value.name)  // 타입 안전하게 User
```

---

## 3. 재시도 (Retry)

```ts
async function withRetry<T>(
  fn: () => Promise<T>,
  options: { maxAttempts?: number; delay?: number; backoff?: boolean } = {}
): Promise<T> {
  const { maxAttempts = 3, delay = 1000, backoff = true } = options

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn()
    } catch (error) {
      if (attempt === maxAttempts) throw error

      const waitTime = backoff ? delay * 2 ** (attempt - 1) : delay
      await sleep(waitTime)
    }
  }
  throw new Error('unreachable')
}

const user = await withRetry(() => fetchUser(id), {
  maxAttempts: 3,
  delay: 500,
  backoff: true,  // 500ms → 1000ms → 2000ms
})
```

---

## 4. 타임아웃

```ts
function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  const timeout = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error(`Timeout after ${ms}ms`)), ms)
  )
  return Promise.race([promise, timeout])
}

const user = await withTimeout(fetchUser(id), 5000)  // 5초 초과 시 에러
```

---

## 5. 취소 (AbortController)

```ts
// fetch 요청 취소
function useUser(id: string) {
  const [user, setUser] = useState<User | null>(null)

  useEffect(() => {
    const controller = new AbortController()

    fetch(`/api/users/${id}`, { signal: controller.signal })
      .then(r => r.json())
      .then(setUser)
      .catch(err => {
        if (err.name === 'AbortError') return  // 취소된 요청 무시
        console.error(err)
      })

    return () => controller.abort()  // cleanup 시 취소
  }, [id])

  return user
}

// TanStack Query는 자동으로 처리
useQuery({
  queryKey: ['user', id],
  queryFn: ({ signal }) => fetch(`/api/users/${id}`, { signal }).then(r => r.json()),
})
```

---

## 6. 디바운스 & 스로틀

```ts
import { useMemo, useCallback } from 'react'
import { debounce, throttle } from 'lodash-es'

// 디바운스 — 마지막 호출 후 N ms 뒤 실행 (검색 입력)
function SearchInput() {
  const debouncedSearch = useMemo(
    () => debounce((query: string) => searchApi(query), 300),
    []
  )

  useEffect(() => () => debouncedSearch.cancel(), [debouncedSearch])

  return <input onChange={e => debouncedSearch(e.target.value)} />
}

// 스로틀 — N ms마다 최대 1번 실행 (스크롤, 리사이즈)
function ScrollTracker() {
  const throttledScroll = useMemo(
    () => throttle(() => trackScrollPosition(), 100),
    []
  )

  useEffect(() => {
    window.addEventListener('scroll', throttledScroll)
    return () => {
      window.removeEventListener('scroll', throttledScroll)
      throttledScroll.cancel()
    }
  }, [throttledScroll])
}
```

---

## 7. 큐 (Queue) 패턴

동시 요청 제한 또는 순차 처리.

```ts
class AsyncQueue {
  private queue: (() => Promise<void>)[] = []
  private running = 0
  private readonly concurrency: number

  constructor(concurrency = 3) {
    this.concurrency = concurrency
  }

  async add<T>(fn: () => Promise<T>): Promise<T> {
    return new Promise((resolve, reject) => {
      this.queue.push(async () => {
        try { resolve(await fn()) }
        catch (e) { reject(e) }
        finally { this.running--; this.run() }
      })
      this.run()
    })
  }

  private run() {
    while (this.running < this.concurrency && this.queue.length > 0) {
      const task = this.queue.shift()!
      this.running++
      task()
    }
  }
}

// 동시에 최대 3개 요청
const queue = new AsyncQueue(3)
await Promise.all(imageIds.map(id => queue.add(() => uploadImage(id))))
```

---

## 8. 안티패턴

- **await in loop**: `for (const id of ids) { await fetch(id) }` → `Promise.all` 병렬화
- **에러 처리 없는 async/await**: 반드시 try-catch
- **취소 없는 fetch**: 컴포넌트 언마운트 시 메모리 누수
- **무한 재시도**: maxAttempts 설정 필수
- **debounce 없는 검색 입력**: 키 입력마다 API 호출
