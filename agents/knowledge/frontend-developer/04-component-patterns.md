# Component Patterns

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/component-patterns

---

## 1. 컴포넌트 설계 원칙

- **단일 책임**: 컴포넌트 하나는 한 가지 역할
- **최소 props**: 필요한 것만 받기. props가 10개 넘으면 설계 재검토
- **명시적 의존**: 컴포넌트가 무엇에 의존하는지 props로 드러내기
- **합성 우선**: 상속보다 합성(Composition)

---

## 2. 주요 패턴

### Compound Component

연관된 컴포넌트들을 하나의 네임스페이스로 묶는 패턴.
내부 상태를 Context로 공유.

```tsx
// 사용 예
<Select>
  <Select.Trigger>선택하세요</Select.Trigger>
  <Select.Content>
    <Select.Item value="apple">사과</Select.Item>
    <Select.Item value="banana">바나나</Select.Item>
  </Select.Content>
</Select>

// 구현
const SelectContext = createContext<SelectContextType | null>(null)

function Select({ children, onValueChange }: SelectProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [value, setValue] = useState('')

  function handleSelect(val: string) {
    setValue(val)
    onValueChange?.(val)
    setIsOpen(false)
  }

  return (
    <SelectContext.Provider value={{ isOpen, setIsOpen, value, handleSelect }}>
      <div className="select">{children}</div>
    </SelectContext.Provider>
  )
}

Select.Trigger = function Trigger({ children }: { children: ReactNode }) {
  const { isOpen, setIsOpen } = useContext(SelectContext)!
  return <button onClick={() => setIsOpen(!isOpen)}>{children}</button>
}

Select.Item = function Item({ value, children }: ItemProps) {
  const { handleSelect } = useContext(SelectContext)!
  return <div onClick={() => handleSelect(value)}>{children}</div>
}
```

**언제 사용:** Tabs, Accordion, Select, Menu처럼 연관 컴포넌트 그룹

### Render Props

렌더링 로직을 외부에서 주입.

```tsx
// 데이터 로딩 로직을 재사용
function DataLoader<T>({
  queryKey,
  queryFn,
  render,
}: {
  queryKey: string[]
  queryFn: () => Promise<T>
  render: (data: T) => ReactNode
}) {
  const { data, isLoading } = useQuery({ queryKey, queryFn })
  if (isLoading) return <Spinner />
  if (!data) return null
  return <>{render(data)}</>
}

// 사용
<DataLoader
  queryKey={['users']}
  queryFn={fetchUsers}
  render={(users) => <UserList users={users} />}
/>
```

현재는 custom hooks로 대부분 대체 가능. 하지만 렌더링 제어가 필요할 때 여전히 유용.

### Container / Presenter (Smart / Dumb)

```tsx
// Container — 데이터/로직 담당
function UserListContainer() {
  const { data: users, isLoading } = useUsers()
  const { mutate: deleteUser } = useDeleteUser()

  if (isLoading) return <Skeleton />
  return <UserList users={users} onDelete={deleteUser} />
}

// Presenter — 렌더링만 담당
function UserList({ users, onDelete }: UserListProps) {
  return (
    <ul>
      {users.map(user => (
        <li key={user.id}>
          {user.name}
          <button onClick={() => onDelete(user.id)}>삭제</button>
        </li>
      ))}
    </ul>
  )
}
```

### Higher-Order Component (HOC)

컴포넌트를 받아서 기능을 추가한 컴포넌트를 반환.

```tsx
// 인증 가드
function withAuth<P extends object>(Component: ComponentType<P>) {
  return function AuthenticatedComponent(props: P) {
    const { user, isLoading } = useAuth()
    if (isLoading) return <Spinner />
    if (!user) return <Navigate to="/login" />
    return <Component {...props} />
  }
}

// 사용
const ProtectedDashboard = withAuth(Dashboard)
```

현재는 custom hooks + early return 패턴으로 대부분 대체 가능.

---

## 3. Custom Hook 패턴

로직 재사용의 현대적 방법. Render Props/HOC보다 선호.

```ts
// 재사용 가능한 비동기 상태 관리
function useAsync<T>(asyncFn: () => Promise<T>) {
  const [state, setState] = useState<{
    data: T | null
    isLoading: boolean
    error: Error | null
  }>({ data: null, isLoading: false, error: null })

  const execute = useCallback(async () => {
    setState({ data: null, isLoading: true, error: null })
    try {
      const data = await asyncFn()
      setState({ data, isLoading: false, error: null })
    } catch (error) {
      setState({ data: null, isLoading: false, error: error as Error })
    }
  }, [asyncFn])

  return { ...state, execute }
}
```

---

## 4. 컴포넌트 합성 (Composition)

```tsx
// ❌ 상속 방식 (React에서 안티패턴)
class SpecialButton extends Button { ... }

// ✅ 합성 방식
function IconButton({ icon, children, ...props }: IconButtonProps) {
  return (
    <Button {...props}>
      {icon}
      {children}
    </Button>
  )
}

// ✅ children으로 슬롯 제공
function Card({ header, children, footer }: CardProps) {
  return (
    <div className="card">
      {header && <div className="card-header">{header}</div>}
      <div className="card-body">{children}</div>
      {footer && <div className="card-footer">{footer}</div>}
    </div>
  )
}
```

---

## 5. 성능 최적화 패턴

```tsx
// React.memo — props가 바뀌지 않으면 리렌더 스킵
const UserCard = memo(function UserCard({ user }: UserCardProps) {
  return <div>{user.name}</div>
})

// useMemo — 계산 비용이 큰 값 캐싱
const sortedUsers = useMemo(
  () => users.sort((a, b) => a.name.localeCompare(b.name)),
  [users]
)

// useCallback — 함수 참조 안정화 (memo와 함께 사용)
const handleDelete = useCallback(
  (id: string) => deleteUser(id),
  [deleteUser]
)
```

**주의**: memo/useMemo/useCallback은 남발하면 오히려 역효과. 실제 성능 문제가 있을 때 적용.

---

## 6. 안티패턴

- **prop drilling 3단계 이상**: Context 또는 상태 관리로
- **컴포넌트 내 컴포넌트 정의**: 매 렌더마다 새 컴포넌트 생성 → 성능/상태 문제
- **너무 큰 컴포넌트**: 300줄 넘으면 분리 신호
- **불필요한 useEffect**: 이벤트 핸들러로 처리 가능한 것을 effect로
- **key에 index 사용**: 정렬/필터 변경 시 상태 꼬임 → 고유 ID 사용
