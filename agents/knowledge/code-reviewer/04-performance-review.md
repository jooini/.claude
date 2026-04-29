# 성능 리뷰

> 참조 링크: https://nodejs.org/en/learn/getting-started/profiling, https://typeorm.io/select-query-builder

---

## 개요

성능 리뷰는 N+1 쿼리, 불필요한 메모리 할당, 알고리즘 복잡도 문제, 캐싱 누락, 메모리 누수 등 프로덕션에서 문제가 되는 성능 이슈를 코드 단계에서 탐지한다.

## 1. N+1 쿼리

### ORM에서의 N+1

```typescript
// ❌ N+1: 주문 목록 조회 후 각 주문의 사용자를 개별 쿼리
const orders = await orderRepo.find(); // SELECT * FROM orders (1 쿼리)
for (const order of orders) {
  const user = await userRepo.findOne({ where: { id: order.userId } });
  // SELECT * FROM users WHERE id = ? (N 쿼리)
  order.userName = user.name;
}

// ✅ JOIN으로 한 번에 조회
const orders = await orderRepo.find({
  relations: ['user'], // LEFT JOIN으로 한 번에 로드
});

// ✅ QueryBuilder 사용
const orders = await orderRepo
  .createQueryBuilder('order')
  .leftJoinAndSelect('order.user', 'user')
  .getMany();
```

### 반복문 내부 쿼리

```typescript
// ❌ 반복문 내부에서 DB 호출
async function enrichProducts(productIds: string[]): Promise<Product[]> {
  const results: Product[] = [];
  for (const id of productIds) {
    const product = await productRepo.findOne({ where: { id } }); // N번 쿼리
    const reviews = await reviewRepo.find({ where: { productId: id } }); // N번 쿼리
    results.push({ ...product, reviews });
  }
  return results;
}

// ✅ 배치 조회
async function enrichProducts(productIds: string[]): Promise<Product[]> {
  const products = await productRepo.findByIds(productIds); // 1번 쿼리
  const reviews = await reviewRepo.find({
    where: { productId: In(productIds) }, // 1번 쿼리
  });

  const reviewMap = new Map<string, Review[]>();
  for (const review of reviews) {
    const existing = reviewMap.get(review.productId) ?? [];
    existing.push(review);
    reviewMap.set(review.productId, existing);
  }

  return products.map(p => ({ ...p, reviews: reviewMap.get(p.id) ?? [] }));
}
```

## 2. 불필요한 할당

### 대량 데이터 복사

```typescript
// ❌ 대형 배열 전체 복사 후 일부만 사용
function getTop10(items: Item[]): Item[] {
  const sorted = [...items].sort((a, b) => b.score - a.score); // 전체 복사 + 정렬
  return sorted.slice(0, 10);
}

// ✅ 부분 정렬 또는 힙 사용 (대량 데이터일 때)
function getTop10(items: Item[]): Item[] {
  if (items.length <= 10) return [...items].sort((a, b) => b.score - a.score);

  // DB 레벨에서 처리가 최선
  // SELECT * FROM items ORDER BY score DESC LIMIT 10
  // 불가피하면 min-heap으로 O(n log k) 가능
  const sorted = [...items].sort((a, b) => b.score - a.score);
  return sorted.slice(0, 10);
}
```

### 불필요한 중간 배열

```typescript
// ❌ 여러 번의 배열 순회 + 중간 배열 생성
const result = users
  .map(u => ({ ...u, fullName: `${u.first} ${u.last}` })) // 새 배열 1
  .filter(u => u.isActive)                                  // 새 배열 2
  .map(u => ({ id: u.id, name: u.fullName }));              // 새 배열 3

// ✅ reduce로 한 번에 처리 (대량 데이터일 때)
const result = users.reduce<{ id: string; name: string }[]>((acc, u) => {
  if (u.isActive) {
    acc.push({ id: u.id, name: `${u.first} ${u.last}` });
  }
  return acc;
}, []);
// 소량 데이터는 가독성 우선 — 체이닝이 더 읽기 좋다
```

### SELECT * 남용

```typescript
// ❌ 필요한 컬럼만 있는데 전체 조회
const users = await userRepo.find(); // SELECT * FROM users — 불필요한 컬럼 포함

// ✅ 필요한 컬럼만 선택
const users = await userRepo.find({
  select: ['id', 'name', 'email'], // 필요한 것만
});

// ✅ QueryBuilder로 정밀 선택
const users = await userRepo
  .createQueryBuilder('user')
  .select(['user.id', 'user.name', 'user.email'])
  .getMany();
```

## 3. 알고리즘 복잡도

### 중첩 루프

```typescript
// ❌ O(n*m) — 대량 데이터에서 느림
function findCommonUsers(listA: User[], listB: User[]): User[] {
  return listA.filter(a => listB.some(b => b.id === a.id));
}

// ✅ O(n+m) — Set 활용
function findCommonUsers(listA: User[], listB: User[]): User[] {
  const setB = new Set(listB.map(b => b.id));
  return listA.filter(a => setB.has(a.id));
}
```

### 반복 계산

```typescript
// ❌ 매 요청마다 동일한 계산 반복
function getPermissions(user: User): Permission[] {
  const allRoles = loadAllRoles();          // 매번 파일/DB 읽기
  const userRoles = allRoles.filter(r => user.roleIds.includes(r.id));
  return userRoles.flatMap(r => r.permissions);
}

// ✅ 캐싱 적용
const roleCache = new Map<string, Role>();

async function getPermissions(user: User): Promise<Permission[]> {
  if (roleCache.size === 0) {
    const roles = await loadAllRoles();
    roles.forEach(r => roleCache.set(r.id, r));
  }
  return user.roleIds
    .map(id => roleCache.get(id))
    .filter(Boolean)
    .flatMap(r => r.permissions);
}
```

## 4. 캐싱 누락

### 반복 호출되는 외부 API

```typescript
// ❌ 매 요청마다 환율 API 호출
async function convertCurrency(amount: number, from: string, to: string): Promise<number> {
  const rate = await fetch(`https://api.exchange.com/rate?from=${from}&to=${to}`);
  // 환율은 분 단위로 변하지 않는데 매번 호출
  return amount * rate;
}

// ✅ TTL 캐싱
async function convertCurrency(amount: number, from: string, to: string): Promise<number> {
  const cacheKey = `rate:${from}:${to}`;
  let rate = await redis.get(cacheKey);

  if (!rate) {
    rate = await fetch(`https://api.exchange.com/rate?from=${from}&to=${to}`);
    await redis.set(cacheKey, rate, 'EX', 300); // 5분 캐싱
  }

  return amount * Number(rate);
}
```

### DB 결과 캐싱 누락

```typescript
// ❌ 자주 조회되지만 거의 변하지 않는 데이터
async function getCategories(): Promise<Category[]> {
  return await categoryRepo.find({ order: { sortOrder: 'ASC' } }); // 매번 DB 조회
}

// ✅ 인메모리 캐싱 + 무효화
let categoriesCache: { data: Category[]; expiry: number } | null = null;

async function getCategories(): Promise<Category[]> {
  if (categoriesCache && categoriesCache.expiry > Date.now()) {
    return categoriesCache.data;
  }
  const data = await categoryRepo.find({ order: { sortOrder: 'ASC' } });
  categoriesCache = { data, expiry: Date.now() + 10 * 60 * 1000 }; // 10분
  return data;
}

function invalidateCategoriesCache(): void {
  categoriesCache = null; // 카테고리 변경 시 호출
}
```

## 5. 메모리 누수

### 이벤트 리스너 미해제

```typescript
// ❌ 이벤트 리스너 등록만 하고 해제 안 함
class WebSocketHandler {
  connect(socket: WebSocket) {
    socket.on('message', this.handleMessage);
    socket.on('error', this.handleError);
    // disconnect 시 리스너 제거 안 함 — 메모리 누수
  }
}

// ✅ 연결 해제 시 리스너 정리
class WebSocketHandler {
  connect(socket: WebSocket) {
    const onMessage = this.handleMessage.bind(this);
    const onError = this.handleError.bind(this);

    socket.on('message', onMessage);
    socket.on('error', onError);
    socket.on('close', () => {
      socket.off('message', onMessage);
      socket.off('error', onError);
    });
  }
}
```

### 무한 증가 컬렉션

```typescript
// ❌ Map/Set이 무한히 커짐
const sessionStore = new Map<string, SessionData>();

function createSession(userId: string): string {
  const sessionId = randomUUID();
  sessionStore.set(sessionId, { userId, createdAt: new Date() });
  // 세션 만료/삭제 로직 없음 — 메모리 무한 증가
  return sessionId;
}

// ✅ TTL + 정리 로직
const sessionStore = new Map<string, SessionData & { expiresAt: number }>();

function createSession(userId: string): string {
  const sessionId = randomUUID();
  sessionStore.set(sessionId, {
    userId,
    createdAt: new Date(),
    expiresAt: Date.now() + 30 * 60 * 1000, // 30분
  });
  return sessionId;
}

// 주기적 정리
setInterval(() => {
  const now = Date.now();
  for (const [key, session] of sessionStore) {
    if (session.expiresAt < now) sessionStore.delete(key);
  }
}, 60 * 1000); // 1분마다
```

### 클로저에 의한 참조 유지

```typescript
// ❌ 클로저가 큰 객체를 참조하여 GC 방해
function processLargeData(data: HugeObject) {
  const summary = extractSummary(data);

  return function getSummary() {
    console.log(data.metadata); // data 전체가 GC되지 않음
    return summary;
  };
}

// ✅ 필요한 것만 캡처
function processLargeData(data: HugeObject) {
  const summary = extractSummary(data);
  const metadata = data.metadata; // 필요한 부분만 추출

  return function getSummary() {
    console.log(metadata); // data 참조 제거 — GC 가능
    return summary;
  };
}
```

## 6. 성능 리뷰 체크리스트

- [ ] 반복문 내부에서 DB/API 호출이 없는가? (N+1)
- [ ] 불필요한 SELECT * 가 없는가?
- [ ] 대량 데이터에서 O(n²) 이상의 알고리즘이 없는가?
- [ ] 자주 호출되는 데이터에 캐싱이 적용되어 있는가?
- [ ] 이벤트 리스너가 적절히 해제되는가?
- [ ] Map/Set 등 컬렉션에 크기 제한/만료 로직이 있는가?
- [ ] 클로저가 불필요하게 큰 객체를 참조하지 않는가?
- [ ] 페이지네이션이 적용되어야 할 곳에 전체 조회가 없는가?
- [ ] 불필요한 데이터 복사(spread, clone)가 없는가?
- [ ] DB 인덱스가 쿼리 패턴에 맞게 설정되어 있는가?
