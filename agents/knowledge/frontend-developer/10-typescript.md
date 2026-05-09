# TypeScript

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/typescript

---

## 1. strict 설정

```json
// tsconfig.json
{
  "compilerOptions": {
    "strict": true,                      // 아래 모든 옵션 활성화
    "noUncheckedIndexedAccess": true,    // arr[0]의 타입이 T | undefined
    "exactOptionalPropertyTypes": true,  // undefined를 명시적으로 구분
    "noImplicitReturns": true,           // 모든 코드 경로에서 return 강제
    "noFallthroughCasesInSwitch": true,
  }
}
```

---

## 2. 타입 vs 인터페이스

```ts
// interface — 객체 형태, 확장(extends) 가능, 선언 병합 가능
interface User {
  id: string
  name: string
}

interface AdminUser extends User {
  role: 'admin'
}

// type — 유니온, 교차, 조건부 타입 등 복잡한 타입 표현
type Status = 'pending' | 'active' | 'inactive'
type ID = string | number
type UserOrAdmin = User | AdminUser
```

**실용적 기준:**
- 공개 API, props → `interface` (확장 가능)
- 유니온, 유틸리티 타입 → `type`
- 팀 내 일관성이 더 중요. 섞지 말 것

---

## 3. 유용한 유틸리티 타입

```ts
interface User {
  id: string
  name: string
  email: string
  role: 'user' | 'admin'
  createdAt: Date
}

// Partial — 모든 필드 선택적
type UpdateUserDto = Partial<User>

// Required — 모든 필드 필수
type StrictUser = Required<User>

// Pick — 일부 필드만
type UserPreview = Pick<User, 'id' | 'name'>

// Omit — 일부 필드 제외
type CreateUserDto = Omit<User, 'id' | 'createdAt'>

// Record — 키-값 맵
type RolePermissions = Record<User['role'], string[]>

// Readonly — 불변
type ImmutableUser = Readonly<User>

// ReturnType — 함수 반환 타입 추출
async function fetchUser(id: string) { return { id, name: 'John' } }
type FetchUserResult = Awaited<ReturnType<typeof fetchUser>>
```

---

## 4. 제네릭 패턴

```ts
// API 응답 래퍼
interface ApiResponse<T> {
  data: T
  message: string
  success: boolean
}

async function get<T>(url: string): Promise<ApiResponse<T>> {
  const res = await fetch(url)
  return res.json()
}

const { data: users } = await get<User[]>('/users')  // users: User[]

// 제네릭 컴포넌트
interface ListProps<T> {
  items: T[]
  renderItem: (item: T) => ReactNode
  keyExtractor: (item: T) => string
}

function List<T>({ items, renderItem, keyExtractor }: ListProps<T>) {
  return (
    <ul>
      {items.map(item => (
        <li key={keyExtractor(item)}>{renderItem(item)}</li>
      ))}
    </ul>
  )
}

// 사용
<List
  items={users}
  renderItem={user => <span>{user.name}</span>}
  keyExtractor={user => user.id}
/>
```

---

## 5. 타입 가드

```ts
// instanceof
function handleError(error: unknown) {
  if (error instanceof ApiError) {
    console.log(error.status)  // ApiError 타입으로 narrowing
  } else if (error instanceof Error) {
    console.log(error.message)
  }
}

// typeof
function formatValue(value: string | number) {
  if (typeof value === 'string') return value.toUpperCase()
  return value.toFixed(2)
}

// 커스텀 타입 가드
interface Cat { meow(): void }
interface Dog { bark(): void }

function isCat(animal: Cat | Dog): animal is Cat {
  return 'meow' in animal
}

// discriminated union
type Shape =
  | { kind: 'circle'; radius: number }
  | { kind: 'rect'; width: number; height: number }

function area(shape: Shape) {
  switch (shape.kind) {
    case 'circle': return Math.PI * shape.radius ** 2
    case 'rect':   return shape.width * shape.height
  }
}
```

---

## 6. React 타입 패턴

```tsx
// Props 타입
interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary'
  isLoading?: boolean
}

// children 타입
interface LayoutProps {
  children: React.ReactNode  // 모든 React 렌더 가능한 것
}

// ref 전달
const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ ...props }, ref) => <input ref={ref} {...props} />
)

// 이벤트 타입
function handleChange(e: React.ChangeEvent<HTMLInputElement>) {
  console.log(e.target.value)
}

function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
  e.preventDefault()
}

// 커스텀 훅 반환 타입
function useCounter(initial: number): [number, () => void, () => void] {
  const [count, setCount] = useState(initial)
  return [count, () => setCount(c => c + 1), () => setCount(c => c - 1)]
}
```

---

## 7. `any` 대신 `unknown`

```ts
// ❌ any — 타입 안전성 포기
function parseData(data: any) {
  return data.user.name  // 런타임 에러 가능
}

// ✅ unknown — 사용 전 타입 확인 강제
function parseData(data: unknown) {
  if (
    typeof data === 'object' &&
    data !== null &&
    'user' in data &&
    typeof (data as any).user?.name === 'string'
  ) {
    return (data as { user: { name: string } }).user.name
  }
  throw new Error('Invalid data shape')
}

// 또는 Zod로 런타임 파싱
const UserSchema = z.object({ user: z.object({ name: z.string() }) })
const parsed = UserSchema.parse(data)  // 실패 시 throw
```

---

## 8. 안티패턴

- **`any` 남용**: `unknown` + 타입 가드 또는 Zod로
- **`as` 캐스팅 남발**: 타입 가드로 narrowing하는 것이 안전
- **`!` non-null assertion 남발**: `??` 또는 조건 체크로
- **과도한 타입 어노테이션**: TypeScript가 추론 가능하면 생략
- **interface vs type 혼용**: 팀 내 기준 통일
