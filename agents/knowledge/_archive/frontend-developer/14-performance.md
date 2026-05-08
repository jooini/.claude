# Performance

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/performance

---

## 1. 성능 지표 (Core Web Vitals)

| 지표 | 의미 | 목표 |
|------|------|------|
| **LCP** (Largest Contentful Paint) | 주요 콘텐츠 로딩 시간 | < 2.5s |
| **INP** (Interaction to Next Paint) | 인터랙션 응답성 | < 200ms |
| **CLS** (Cumulative Layout Shift) | 레이아웃 안정성 | < 0.1 |
| **FCP** (First Contentful Paint) | 첫 콘텐츠 표시 | < 1.8s |
| **TTFB** (Time to First Byte) | 서버 응답 시간 | < 800ms |

측정 도구: Lighthouse, Chrome DevTools Performance, Vercel Analytics

---

## 2. 렌더링 최적화

### 불필요한 리렌더 방지

```tsx
// React.memo — props가 동일하면 리렌더 스킵
const UserCard = memo(function UserCard({ user }: { user: User }) {
  return <div>{user.name}</div>
})

// useMemo — 무거운 계산 캐싱
const expensiveResult = useMemo(
  () => heavyCalculation(data),
  [data]  // data가 바뀔 때만 재계산
)

// useCallback — 함수 참조 안정화 (memo된 자식에 넘길 때)
const handleDelete = useCallback(
  (id: string) => deleteItem(id),
  [deleteItem]
)
```

**언제 적용할지:**
- `memo`: 컴포넌트가 자주 리렌더되고, 렌더 비용이 클 때
- `useMemo`: 계산에 100ms+ 걸릴 때 (배열 정렬, 필터링 등)
- `useCallback`: memo된 자식 컴포넌트에 함수를 props로 전달할 때

### 상태 위치 최적화

```tsx
// ❌ 부모에 상태 → 자식 전체 리렌더
function Parent() {
  const [count, setCount] = useState(0)  // count 바뀌면 Parent 전체 리렌더
  return (
    <>
      <HeavyComponent />      // count와 무관한데 리렌더됨
      <Counter count={count} onChange={setCount} />
    </>
  )
}

// ✅ 상태를 필요한 곳으로 내리기 (State Colocation)
function Parent() {
  return (
    <>
      <HeavyComponent />   // 리렌더 안 됨
      <Counter />          // 자체적으로 상태 관리
    </>
  )
}
```

---

## 3. 이미지 최적화

```tsx
// Next.js Image 컴포넌트 — 자동 최적화
import Image from 'next/image'

// 고정 크기 이미지
<Image
  src="/hero.jpg"
  alt="히어로 이미지"
  width={1200}
  height={600}
  priority           // LCP 이미지에 적용 — preload
  placeholder="blur" // 로딩 중 블러 효과
/>

// 반응형 이미지
<div className="relative h-64 w-full">
  <Image
    src="/banner.jpg"
    alt="배너"
    fill
    sizes="(max-width: 768px) 100vw, 50vw"  // 브라우저에 크기 힌트
    className="object-cover"
  />
</div>
```

**주의:**
- LCP 대상 이미지에는 반드시 `priority`
- `sizes` 속성으로 불필요한 큰 이미지 다운로드 방지
- SVG 아이콘은 Image 컴포넌트 불필요, 직접 import

---

## 4. 코드 스플리팅

```tsx
import dynamic from 'next/dynamic'
import { lazy, Suspense } from 'react'

// Next.js dynamic import
const HeavyChart = dynamic(() => import('@/components/HeavyChart'), {
  loading: () => <ChartSkeleton />,
  ssr: false,  // 클라이언트 전용 라이브러리 (window 사용 등)
})

// 조건부 로딩 — 모달, 드로어 등 초기 로드 불필요
const AdminPanel = dynamic(() => import('@/components/AdminPanel'))

function Dashboard({ isAdmin }: { isAdmin: boolean }) {
  return (
    <div>
      <MainContent />
      {isAdmin && (
        <Suspense fallback={<Skeleton />}>
          <AdminPanel />
        </Suspense>
      )}
    </div>
  )
}
```

---

## 5. 가상화 (Virtualization)

긴 목록은 화면에 보이는 것만 렌더링.

```tsx
import { useVirtualizer } from '@tanstack/react-virtual'

function VirtualList({ items }: { items: User[] }) {
  const parentRef = useRef<HTMLDivElement>(null)

  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 72,  // 아이템 예상 높이
  })

  return (
    <div ref={parentRef} className="h-[600px] overflow-auto">
      <div style={{ height: virtualizer.getTotalSize() }}>
        {virtualizer.getVirtualItems().map(virtualItem => (
          <div
            key={virtualItem.key}
            style={{
              position: 'absolute',
              top: virtualItem.start,
              height: virtualItem.size,
              width: '100%',
            }}
          >
            <UserRow user={items[virtualItem.index]} />
          </div>
        ))}
      </div>
    </div>
  )
}
```

1000개 이상의 리스트에 적용. 그 이하는 페이지네이션으로도 충분.

---

## 6. 데이터 페칭 최적화

```tsx
// prefetch — 사용자 액션 전에 미리 로딩
function UserLink({ userId }: { userId: string }) {
  const queryClient = useQueryClient()

  return (
    <Link
      href={`/users/${userId}`}
      onMouseEnter={() => {
        // 호버 시 미리 fetch
        queryClient.prefetchQuery({
          queryKey: ['users', userId],
          queryFn: () => fetchUser(userId),
        })
      }}
    >
      프로필 보기
    </Link>
  )
}
```

---

## 7. 안티패턴

- **LCP 이미지에 lazy loading**: 오히려 느려짐 → `priority` 사용
- **memo 과적용**: 모든 컴포넌트에 memo → 메모이제이션 비용 발생
- **큰 번들 그대로 import**: `import _ from 'lodash'` → `import debounce from 'lodash/debounce'`
- **레이아웃 shift 유발 이미지**: width/height 없는 img → CLS 악화
- **불필요한 useEffect**: 이벤트 핸들러로 처리 가능한 것 → INP 악화
