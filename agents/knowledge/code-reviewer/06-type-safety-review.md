# 타입 안전성 리뷰

> 참조 링크: https://www.typescriptlang.org/docs/handbook/, https://typescript-eslint.io/rules/

---

## 개요

TypeScript의 타입 시스템을 올바르게 활용하면 런타임 에러를 컴파일 타임에 잡을 수 있다. any 남용, 타입 단언, 런타임 검증 누락, 제네릭 미활용 등 타입 안전성을 해치는 패턴을 리뷰한다.

## 1. any 남용

### any가 전파되는 위험

```typescript
// ❌ any가 타입 체크를 완전히 무력화
function processData(data: any): any {
  return data.items.map((item: any) => item.value.toFixed(2));
  // data.items가 없으면? item.value가 숫자가 아니면? — 런타임 에러
}

// ❌ JSON.parse 결과를 any로 사용
const config = JSON.parse(rawConfig); // 타입: any
const port = config.server.port;       // 어떤 접근도 에러 없이 통과

// ✅ 명시적 타입 정의
interface Config {
  server: {
    port: number;
    host: string;
  };
  database: {
    url: string;
  };
}

function parseConfig(raw: string): Config {
  const parsed = JSON.parse(raw);
  // 런타임 검증 추가 (아래 섹션 참조)
  return parsed as Config;
}

// ✅ unknown 사용 후 타입 좁히기
function processData(data: unknown): string[] {
  if (!isDataResponse(data)) {
    throw new Error('Invalid data format');
  }
  return data.items.map(item => item.value.toFixed(2));
}
```

### any 대신 사용할 타입

```typescript
// 상황별 any 대체
type AnyAlternatives = {
  unknownInput: unknown;        // 타입을 모를 때 — 사용 전 검증 필요
  anyObject: Record<string, unknown>; // 객체지만 구조를 모를 때
  anyFunction: (...args: unknown[]) => unknown; // 함수지만 시그니처를 모를 때
  anyArray: unknown[];          // 배열이지만 요소 타입을 모를 때
  neverReach: never;            // 도달할 수 없는 코드
};
```

## 2. 타입 단언 (Type Assertion) 오용

### 위험한 단언

```typescript
// ❌ 근거 없는 타입 단언
const user = await fetchUser(id) as User; // fetchUser가 null 반환 가능
user.name; // null이면 런타임 에러

// ❌ 이중 단언 — 타입 시스템 완전 우회
const data = rawInput as unknown as SpecificType;

// ❌ non-null assertion 남용
function getUser(map: Map<string, User>, id: string): User {
  return map.get(id)!; // id가 없으면 undefined — ! 가 에러를 숨김
}

// ✅ 타입 가드로 안전하게 좁히기
const user = await fetchUser(id);
if (!user) {
  throw new NotFoundException(`User ${id} not found`);
}
user.name; // 여기서 user는 non-null 보장

// ✅ Map 접근 시 존재 확인
function getUser(map: Map<string, User>, id: string): User {
  const user = map.get(id);
  if (!user) {
    throw new Error(`User ${id} not found in map`);
  }
  return user;
}
```

### 허용되는 단언

```typescript
// ✅ DOM API에서 확실한 경우
const canvas = document.getElementById('canvas') as HTMLCanvasElement;

// ✅ 테스트에서 partial mock
const mockService = {
  findOne: jest.fn(),
} as unknown as UserService; // 테스트에서는 허용 가능

// ✅ 타입 시스템의 한계를 보완할 때 (주석 필수)
// TypeORM의 raw query 결과는 타입 추론이 안 됨
const result = await query.getRawMany() as AggregateResult[];
```

## 3. 런타임 검증 누락

### 외부 입력 검증

```typescript
// ❌ API 입력을 타입만 믿고 사용
@Post('users')
async createUser(@Body() dto: CreateUserDto) {
  // Body의 타입 선언만으로는 런타임 검증이 안 됨
  // { email: 123, age: "not a number" } 도 통과
  return this.userService.create(dto);
}

// ✅ class-validator + ValidationPipe
import { IsEmail, IsInt, Min, Max, IsString, Length } from 'class-validator';

class CreateUserDto {
  @IsEmail()
  email: string;

  @IsString()
  @Length(2, 50)
  name: string;

  @IsInt()
  @Min(0)
  @Max(150)
  age: number;
}

// main.ts에서 전역 ValidationPipe 적용
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,       // DTO에 없는 필드 제거
  forbidNonWhitelisted: true, // 알 수 없는 필드 시 에러
  transform: true,       // 타입 변환 활성화
}));
```

### Zod를 이용한 런타임 검증

```typescript
import { z } from 'zod';

// 스키마 정의
const UserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(2).max(50),
  age: z.number().int().min(0).max(150),
});

// 타입 추론
type User = z.infer<typeof UserSchema>;

// ✅ 런타임 검증
function validateUser(input: unknown): User {
  return UserSchema.parse(input); // 실패 시 ZodError throw
}

// ✅ 안전한 검증 (에러 대신 결과 반환)
function safeValidateUser(input: unknown): { success: true; data: User } | { success: false; error: z.ZodError } {
  return UserSchema.safeParse(input);
}
```

## 4. 제네릭 활용

### 제네릭 미활용

```typescript
// ❌ 반환 타입이 any
function getFirst(arr: any[]): any {
  return arr[0];
}

const item = getFirst([1, 2, 3]); // item은 any — 타입 정보 유실

// ✅ 제네릭으로 타입 보존
function getFirst<T>(arr: T[]): T | undefined {
  return arr[0];
}

const item = getFirst([1, 2, 3]); // item은 number | undefined
```

### 제네릭 제약 조건

```typescript
// ❌ 제약 없는 제네릭 — 런타임 에러 가능
function getProperty<T>(obj: T, key: string): unknown {
  return (obj as any)[key]; // any 캐스팅 필요
}

// ✅ keyof 제약으로 타입 안전
function getProperty<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key]; // 타입 안전, 자동 완성 지원
}

const user = { name: 'Alice', age: 30 };
getProperty(user, 'name');  // string
getProperty(user, 'age');   // number
getProperty(user, 'email'); // 컴파일 에러
```

### 유틸리티 타입 활용

```typescript
// ❌ 수동으로 Optional 타입 정의
interface UpdateUserDto {
  name?: string;
  email?: string;
  age?: number;
}

// ✅ Partial 활용
type UpdateUserDto = Partial<Pick<User, 'name' | 'email' | 'age'>>;

// ❌ 수동 readonly
interface ReadonlyUser {
  readonly name: string;
  readonly email: string;
}

// ✅ Readonly 활용
type ReadonlyUser = Readonly<User>;

// 유용한 유틸리티 타입 조합
type CreateDto = Omit<User, 'id' | 'createdAt' | 'updatedAt'>; // 생성 시 제외할 필드
type UserResponse = Pick<User, 'id' | 'name' | 'email'>;       // 응답에 포함할 필드만
type UserWithOrders = User & { orders: Order[] };                // 확장
```

## 5. Discriminated Union 패턴

```typescript
// ❌ string 상태로 분기 — 타입 안전성 없음
interface ApiResponse {
  status: string;
  data?: unknown;
  error?: string;
}

function handleResponse(res: ApiResponse) {
  if (res.status === 'success') {
    console.log(res.data); // data가 있다는 보장 없음
  }
}

// ✅ Discriminated Union으로 타입 안전한 분기
type ApiResponse<T> =
  | { status: 'success'; data: T }
  | { status: 'error'; error: string; code: number };

function handleResponse<T>(res: ApiResponse<T>): T {
  switch (res.status) {
    case 'success':
      return res.data; // data가 반드시 존재
    case 'error':
      throw new Error(`API Error ${res.code}: ${res.error}`);
    default:
      const _exhaustive: never = res; // 모든 케이스 처리 보장
      throw new Error('Unreachable');
  }
}
```

## 6. 엄격한 tsconfig 설정

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

```typescript
// noUncheckedIndexedAccess의 효과
const arr = [1, 2, 3];
const item = arr[0]; // 타입: number | undefined (안전)

const obj: Record<string, string> = {};
const val = obj['key']; // 타입: string | undefined (안전)
```

## 7. 타입 안전성 리뷰 체크리스트

- [ ] any 사용이 없는가? 있다면 정당한 이유가 있는가?
- [ ] 타입 단언(as)이 최소화되어 있는가?
- [ ] non-null assertion(!)이 정당한 근거 없이 사용되지 않는가?
- [ ] 외부 입력(API body, query, params)에 런타임 검증이 있는가?
- [ ] JSON.parse 결과에 타입 검증이 있는가?
- [ ] 제네릭이 적절히 활용되어 타입 정보가 유지되는가?
- [ ] Discriminated Union으로 상태 분기가 안전한가?
- [ ] tsconfig의 strict 모드가 활성화되어 있는가?
- [ ] 유틸리티 타입(Partial, Pick, Omit)이 적절히 활용되는가?
- [ ] enum 대신 const assertion이나 union type을 고려했는가?
