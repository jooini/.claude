# State Management

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/state-management

---

## 1. 상태의 종류

상태 관리 도구를 선택하기 전에 상태의 성격부터 파악.

| 종류 | 설명 | 적합한 도구 |
|------|------|------------|
| **Server State** | 서버에서 가져온 데이터. 캐싱/동기화 필요 | TanStack Query, SWR |
| **Global UI State** | 여러 컴포넌트가 공유하는 UI 상태 (모달, 테마) | Zustand, Jotai |
| **Local UI State** | 단일 컴포넌트 내 상태 (폼 입력, 토글) | useState |
| **URL State** | 필터, 페이지, 탭 등 URL에 반영해야 하는 상태 | useSearchParams |
| **Form State** | 폼 유효성, 제출 상태 | React Hook Form |

**가장 흔한 실수**: Server State를 전역 상태로 관리하는 것.
→ TanStack Query 도입하면 전역 상태 80% 제거 가능.

---

## 2. Server State — TanStack Query

```ts
// 기본 query
const { data, isLoading, error } = useQuery({
  queryKey: ['users', filters],  // 캐시 키 — filters 바뀌면 자동 재요청
  queryFn: () => fetchUsers(filters),
  staleTime: 5 * 60 * 1000,     // 5분간 fresh 유지
})

// mutation
const { mutate, isPending } = useMutation({
  mutationFn: (data: CreateUserDto) => createUser(data),
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['users'] })  // 목록 자동 갱신
    toast.success('사용자가 생성되었습니다')
  },
  onError: (error) => {
    toast.error(error.message)
  },
})
```

**queryKey 설계:**
```ts
// 계층적으로 설계 — 상위 키 invalidate 시 하위도 포함
['users']                    // 전체 users
['users', { status: 'active' }]   // 필터링된 users
['users', userId]            // 특정 user
['users', userId, 'posts']   // 특정 user의 posts
```

---

## 3. Global UI State — Zustand

```ts
// store/ui.store.ts
interface UIStore {
  isModalOpen: boolean
  modalType: 'confirm' | 'alert' | null
  openModal: (type: UIStore['modalType']) => void
  closeModal: () => void
}

export const useUIStore = create<UIStore>((set) => ({
  isModalOpen: false,
  modalType: null,
  openModal: (type) => set({ isModalOpen: true, modalType: type }),
  closeModal: () => set({ isModalOpen: false, modalType: null }),
}))

// 사용
const { openModal } = useUIStore()
const isOpen = useUIStore((state) => state.isModalOpen)  // selector로 리렌더 최적화
```

**Zustand vs Context API:**
- Context는 값이 바뀌면 하위 전체 리렌더 → 성능 이슈
- Zustand는 selector로 구독한 값만 리렌더

---

## 4. Local State — useState / useReducer

```ts
// 단순 상태 → useState
const [isOpen, setIsOpen] = useState(false)

// 복잡한 상태 전환 → useReducer
type Action =
  | { type: 'FETCH_START' }
  | { type: 'FETCH_SUCCESS'; payload: User[] }
  | { type: 'FETCH_ERROR'; payload: string }

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'FETCH_START':
      return { ...state, isLoading: true, error: null }
    case 'FETCH_SUCCESS':
      return { isLoading: false, data: action.payload, error: null }
    case 'FETCH_ERROR':
      return { ...state, isLoading: false, error: action.payload }
  }
}
```

**useState vs useReducer 선택 기준:**
- 상태가 3개 이상 연관되거나 전환 로직이 복잡 → useReducer
- 단순 on/off, 단일 값 → useState

---

## 5. URL State

필터, 페이지, 탭처럼 URL에 반영되어야 북마크/공유 가능한 상태.

```ts
// Next.js App Router
'use client'
import { useSearchParams, useRouter, usePathname } from 'next/navigation'

function FilterPanel() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const pathname = usePathname()

  const status = searchParams.get('status') ?? 'all'

  function setStatus(value: string) {
    const params = new URLSearchParams(searchParams)
    params.set('status', value)
    router.push(`${pathname}?${params.toString()}`)
  }

  return <Select value={status} onValueChange={setStatus} />
}
```

---

## 6. 상태 관리 선택 가이드

```
데이터가 서버에서 오는가?
  → YES: TanStack Query

URL에 반영되어야 하는가?
  → YES: useSearchParams

여러 컴포넌트가 공유하는가?
  → YES: Zustand (또는 Context)
  → NO: useState / useReducer

폼 데이터인가?
  → YES: React Hook Form
```

---

## 7. 안티패턴

- **서버 데이터를 useState로 관리**: 캐싱, 동기화, 로딩 상태를 직접 구현하게 됨
- **전역 상태 남용**: 컴포넌트 내에서 쓰면 되는 것까지 전역으로
- **Context 과도한 사용**: 자주 바뀌는 값을 Context에 → 성능 이슈
- **상태 중복**: 동일한 데이터를 여러 곳에 저장 → 동기화 문제
