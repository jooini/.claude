# 버그 탐지 패턴

> 참조 링크: https://owasp.org/www-community/vulnerabilities/, https://cwe.mitre.org/top25/archive/2023/2023_top25_list.html

---

## 개요

코드 리뷰에서 버그를 탐지하는 핵심 패턴을 다룬다. 로직 에러, off-by-one, null 미처리, 레이스 컨디션, 경계 조건 등 실무에서 자주 발생하는 버그 유형과 탐지 기법을 정리한다.

## 1. 로직 에러

### 조건문 논리 오류

```typescript
// ❌ 논리 연산자 실수 — OR을 써야 할 곳에 AND
function isEligible(user: User): boolean {
  return user.age >= 18 && user.age <= 65 && user.country === 'KR' && user.country === 'US';
  // country가 동시에 KR이면서 US일 수 없음 — 항상 false
}

// ✅ 올바른 로직
function isEligible(user: User): boolean {
  return user.age >= 18 && user.age <= 65 && (user.country === 'KR' || user.country === 'US');
}
```

### 부정 조건 혼동

```typescript
// ❌ 이중 부정으로 인한 혼란
if (!user.isNotVerified) { // 이중 부정: "검증되지 않은 것이 아니면"
  grantAccess(user);
}

// ✅ 명확한 조건
if (user.isVerified) {
  grantAccess(user);
}
```

### 단락 평가(Short-circuit) 실수

```typescript
// ❌ 단락 평가로 중요한 부수효과가 실행 안 됨
const isValid = validateFormat(input) && logValidation(input) && saveAuditLog(input);
// validateFormat이 false면 logValidation, saveAuditLog 실행 안 됨

// ✅ 부수효과는 별도로 실행
const formatValid = validateFormat(input);
logValidation(input);
saveAuditLog(input);
if (formatValid) { /* 진행 */ }
```

## 2. Off-by-One 에러

### 배열 인덱스

```typescript
// ❌ 배열 길이를 인덱스로 사용
function getLastItem<T>(arr: T[]): T {
  return arr[arr.length]; // undefined — 마지막 인덱스는 length - 1
}

// ✅ 올바른 접근
function getLastItem<T>(arr: T[]): T | undefined {
  return arr[arr.length - 1];
}
```

### 반복문 경계

```typescript
// ❌ <= 사용으로 배열 범위 초과
for (let i = 0; i <= items.length; i++) {
  process(items[i]); // items[items.length]는 undefined
}

// ✅ < 사용
for (let i = 0; i < items.length; i++) {
  process(items[i]);
}
```

### 페이지네이션 오프셋

```typescript
// ❌ 페이지 계산 실수
function getOffset(page: number, pageSize: number): number {
  return page * pageSize; // page가 1-based면 첫 페이지 데이터 건너뜀
}

// ✅ 1-based page 처리
function getOffset(page: number, pageSize: number): number {
  return (page - 1) * pageSize; // page 1 → offset 0
}
```

## 3. Null/Undefined 미처리

### Optional Chaining 누락

```typescript
// ❌ 중첩 객체 접근 시 null 체크 없음
function getUserCity(user: User): string {
  return user.address.city; // address가 null이면 TypeError
}

// ✅ Optional chaining + 기본값
function getUserCity(user: User): string {
  return user.address?.city ?? 'Unknown';
}
```

### 배열 메서드 반환값

```typescript
// ❌ find 결과를 바로 사용
function getAdminEmail(users: User[]): string {
  const admin = users.find(u => u.role === 'admin');
  return admin.email; // admin이 undefined면 TypeError
}

// ✅ null 체크
function getAdminEmail(users: User[]): string {
  const admin = users.find(u => u.role === 'admin');
  if (!admin) {
    throw new NotFoundException('Admin user not found');
  }
  return admin.email;
}
```

### Falsy 값 혼동

```typescript
// ❌ 0, '' 등 유효한 falsy 값 무시
function getCount(value: number | undefined): number {
  return value || 10; // value가 0이면 10을 반환 — 의도하지 않은 동작
}

// ✅ nullish coalescing 사용
function getCount(value: number | undefined): number {
  return value ?? 10; // undefined/null만 기본값 적용, 0은 유지
}
```

### Map/Object 접근

```typescript
// ❌ Map에서 값 접근 후 바로 메서드 호출
const userMap = new Map<string, User>();
const name = userMap.get(userId).name; // get이 undefined 반환 가능

// ✅ 존재 확인 후 접근
const user = userMap.get(userId);
if (!user) {
  throw new Error(`User ${userId} not found`);
}
const name = user.name;
```

## 4. 레이스 컨디션

### 비동기 상태 변경

```typescript
// ❌ check-then-act 패턴 — 레이스 컨디션 취약
async function withdrawMoney(accountId: string, amount: number): Promise<void> {
  const account = await accountRepo.findById(accountId);
  if (account.balance >= amount) {       // 확인 시점
    account.balance -= amount;           // 변경 시점 — 사이에 다른 요청이 끼어들 수 있음
    await accountRepo.save(account);
  }
}

// ✅ 비관적 락 또는 원자적 연산
async function withdrawMoney(accountId: string, amount: number): Promise<void> {
  await dataSource.transaction(async (manager) => {
    const account = await manager
      .createQueryBuilder(Account, 'a')
      .setLock('pessimistic_write')      // FOR UPDATE 락
      .where('a.id = :id', { id: accountId })
      .getOneOrFail();

    if (account.balance < amount) {
      throw new InsufficientBalanceError();
    }
    account.balance -= amount;
    await manager.save(account);
  });
}
```

### 이벤트 핸들러 경합

```typescript
// ❌ 공유 상태에 동시 접근
let requestCount = 0;

app.use((req, res, next) => {
  requestCount++;                // 읽기-수정-쓰기가 원자적이지 않음
  req.requestId = requestCount;
  next();
});

// ✅ 원자적 카운터 사용
import { randomUUID } from 'crypto';

app.use((req, res, next) => {
  req.requestId = randomUUID(); // 고유 ID 생성 — 경합 없음
  next();
});
```

### 캐시 스탬피드

```typescript
// ❌ 캐시 만료 시 동시 다수 요청이 DB 접근
async function getPopularItems(): Promise<Item[]> {
  const cached = await redis.get('popular-items');
  if (cached) return JSON.parse(cached);

  const items = await db.query('SELECT * FROM items ORDER BY views DESC LIMIT 100');
  await redis.set('popular-items', JSON.stringify(items), 'EX', 60);
  return items;
}

// ✅ 뮤텍스로 보호
async function getPopularItems(): Promise<Item[]> {
  const cached = await redis.get('popular-items');
  if (cached) return JSON.parse(cached);

  const lockKey = 'lock:popular-items';
  const acquired = await redis.set(lockKey, '1', 'EX', 10, 'NX');

  if (!acquired) {
    await sleep(100); // 다른 요청이 캐시 갱신 중 — 잠시 대기 후 재시도
    return getPopularItems();
  }

  try {
    const items = await db.query('SELECT * FROM items ORDER BY views DESC LIMIT 100');
    await redis.set('popular-items', JSON.stringify(items), 'EX', 60);
    return items;
  } finally {
    await redis.del(lockKey);
  }
}
```

## 5. 경계 조건

### 빈 컬렉션

```typescript
// ❌ 빈 배열 미고려
function calculateAverage(numbers: number[]): number {
  const sum = numbers.reduce((a, b) => a + b, 0);
  return sum / numbers.length; // 빈 배열이면 NaN (0/0)
}

// ✅ 빈 배열 처리
function calculateAverage(numbers: number[]): number {
  if (numbers.length === 0) {
    throw new Error('Cannot calculate average of empty array');
  }
  const sum = numbers.reduce((a, b) => a + b, 0);
  return sum / numbers.length;
}
```

### 정수 오버플로우

```typescript
// ❌ JavaScript 정수 한계 미고려
function calculateTotal(prices: number[]): number {
  return prices.reduce((sum, price) => sum + price, 0);
  // Number.MAX_SAFE_INTEGER (2^53 - 1) 초과 시 정밀도 손실
}

// ✅ 금액 계산은 BigInt 또는 정수(센트 단위) 사용
function calculateTotal(pricesInCents: bigint[]): bigint {
  return pricesInCents.reduce((sum, price) => sum + price, 0n);
}
```

### 문자열 경계

```typescript
// ❌ 빈 문자열, 공백만 있는 문자열 미처리
function createSlug(title: string): string {
  return title.toLowerCase().replace(/\s+/g, '-');
  // title이 '' 이면 빈 slug, '   '이면 '-'
}

// ✅ 유효성 검증 포함
function createSlug(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) {
    throw new Error('Title cannot be empty');
  }
  return trimmed.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
}
```

## 6. 리뷰어 관점 버그 탐지 체크리스트

- [ ] 조건문의 논리 연산자(&&, ||)가 의도대로인가?
- [ ] 반복문 경계가 정확한가? (off-by-one)
- [ ] null/undefined가 발생할 수 있는 모든 경로를 처리하는가?
- [ ] 비동기 작업에서 레이스 컨디션이 없는가?
- [ ] 빈 배열, 빈 문자열, 0 등 경계값을 처리하는가?
- [ ] 부동소수점 연산이 금액 계산에 사용되지 않는가?
- [ ] find, get 등 실패 가능한 메서드의 반환값을 검증하는가?
- [ ] falsy 값(0, '', false)과 null/undefined를 구분하는가?
- [ ] check-then-act 패턴에서 동시성 보호가 있는가?
- [ ] 타입 강제 변환(==)이 아닌 엄격 비교(===)를 사용하는가?
