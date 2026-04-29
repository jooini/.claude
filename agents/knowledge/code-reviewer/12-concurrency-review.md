# 동시성 리뷰

> 참조 링크: https://nodejs.org/en/learn/asynchronous-work/overview-of-blocking-vs-non-blocking, https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise

---

## 개요

Node.js는 싱글 스레드 이벤트 루프 기반이지만, 비동기 I/O와 동시 요청 처리로 인해 레이스 컨디션, 공유 상태 오염, 비동기 에러 유실 등 동시성 문제가 발생한다. 특히 DB나 외부 리소스 접근 시 주의가 필요하다.

## 1. 레이스 컨디션

### Check-Then-Act 패턴

```typescript
// ❌ 레이스 컨디션: 확인 → 행동 사이에 다른 요청이 끼어듦
async purchaseItem(userId: string, itemId: string): Promise<void> {
  const item = await this.itemRepo.findOneOrFail({ where: { id: itemId } });

  if (item.stock <= 0) { // 확인 시점: stock = 1
    throw new BadRequestException('재고 없음');
  }

  // 다른 요청이 동시에 여기 도달 → 둘 다 stock = 1로 통과
  item.stock -= 1;
  await this.itemRepo.save(item); // 두 요청 모두 stock = 0 으로 저장 (실제론 -1이어야 함)
}

// ✅ 원자적 업데이트로 레이스 컨디션 방지
async purchaseItem(userId: string, itemId: string): Promise<void> {
  const result = await this.itemRepo
    .createQueryBuilder()
    .update(Item)
    .set({ stock: () => 'stock - 1' })
    .where('id = :id AND stock > 0', { id: itemId }) // 조건부 원자적 업데이트
    .execute();

  if (result.affected === 0) {
    throw new BadRequestException('재고 없음');
  }
}
```

### 분산 환경 레이스 컨디션

```typescript
// ❌ 인메모리 상태로 중복 처리 방지 시도 (멀티 인스턴스에서 무용)
const processingSet = new Set<string>();

async processPayment(paymentId: string): Promise<void> {
  if (processingSet.has(paymentId)) return; // 인스턴스 A에서만 유효
  processingSet.add(paymentId);
  // ...
}

// ✅ 분산 락 사용 (Redis 기반)
async processPayment(paymentId: string): Promise<void> {
  const lockKey = `lock:payment:${paymentId}`;
  const acquired = await this.redis.set(lockKey, '1', 'EX', 30, 'NX');

  if (!acquired) {
    throw new ConflictException('이미 처리 중');
  }

  try {
    await this.executePayment(paymentId);
  } finally {
    await this.redis.del(lockKey);
  }
}
```

### 레이스 컨디션 체크리스트

- [ ] "읽기 → 판단 → 쓰기" 패턴에서 원자성이 보장되는가?
- [ ] 재고, 잔액, 좌석 등 경쟁 리소스에 원자적 업데이트를 사용하는가?
- [ ] 멀티 인스턴스 환경에서 인메모리 상태에 의존하지 않는가?
- [ ] 비관적/낙관적 락이 적절히 사용되고 있는가?

## 2. 데드락

### 데드락 발생 패턴

```typescript
// ❌ 서로 다른 순서로 락 획득 → 데드락
// 요청 A: user 락 → order 락
// 요청 B: order 락 → user 락
async transferA(): Promise<void> {
  await this.dataSource.transaction(async (manager) => {
    await manager.findOne(User, { where: { id: '1' }, lock: { mode: 'pessimistic_write' } });
    await manager.findOne(Order, { where: { id: '2' }, lock: { mode: 'pessimistic_write' } });
  });
}

async transferB(): Promise<void> {
  await this.dataSource.transaction(async (manager) => {
    await manager.findOne(Order, { where: { id: '2' }, lock: { mode: 'pessimistic_write' } });
    await manager.findOne(User, { where: { id: '1' }, lock: { mode: 'pessimistic_write' } });
  });
}

// ✅ 항상 같은 순서로 락 획득
async transferSafe(userIds: string[]): Promise<void> {
  const sortedIds = [...userIds].sort(); // 정렬하여 순서 고정

  await this.dataSource.transaction(async (manager) => {
    for (const id of sortedIds) {
      await manager.findOne(User, {
        where: { id },
        lock: { mode: 'pessimistic_write' },
      });
    }
    // 비즈니스 로직
  });
}
```

### 데드락 체크리스트

- [ ] 여러 테이블/행에 락을 잡을 때 순서가 일관적인가?
- [ ] 트랜잭션 내에서 불필요하게 긴 락을 잡고 있지 않은가?
- [ ] 데드락 발생 시 재시도 로직이 있는가?
- [ ] 트랜잭션 타임아웃이 설정되어 있는가?

## 3. 비동기 에러 전파

### 유실되는 비동기 에러

```typescript
// ❌ 에러가 유실됨 — fire-and-forget
async createUser(dto: CreateUserDto): Promise<User> {
  const user = await this.userRepo.save(dto);
  this.sendWelcomeEmail(user); // await 없음, 에러 발생해도 아무도 모름
  this.trackAnalytics(user);   // 마찬가지
  return user;
}

// ❌ Promise.all에서 부분 실패 처리 안 됨
async processAll(items: Item[]): Promise<void> {
  await Promise.all(items.map(item => this.process(item)));
  // 하나 실패하면 전체 reject, 나머지 결과 유실
}

// ✅ 의도적 fire-and-forget은 에러 핸들링 추가
async createUser(dto: CreateUserDto): Promise<User> {
  const user = await this.userRepo.save(dto);
  this.sendWelcomeEmail(user).catch(err => {
    this.logger.error('Welcome email failed', { userId: user.id, error: err.message });
  });
  return user;
}

// ✅ Promise.allSettled로 부분 실패 허용
async processAll(items: Item[]): Promise<ProcessResult> {
  const results = await Promise.allSettled(items.map(item => this.process(item)));

  const succeeded = results.filter(r => r.status === 'fulfilled');
  const failed = results.filter(r => r.status === 'rejected');

  if (failed.length > 0) {
    this.logger.warn(`${failed.length}/${items.length} items failed`);
  }

  return { succeeded: succeeded.length, failed: failed.length };
}
```

### 이벤트 리스너 에러

```typescript
// ❌ 이벤트 핸들러에서 에러 전파 불가
eventEmitter.on('order.created', async (order: Order) => {
  await this.inventoryService.deduct(order); // 에러 발생 시 unhandledRejection
});

// ✅ 이벤트 핸들러 내 에러 핸들링
eventEmitter.on('order.created', async (order: Order) => {
  try {
    await this.inventoryService.deduct(order);
  } catch (error) {
    this.logger.error('Inventory deduction failed', { orderId: order.id, error });
    await this.alertService.notify('inventory-deduction-failed', { orderId: order.id });
  }
});
```

### 비동기 에러 체크리스트

- [ ] await 없이 호출한 Promise에 `.catch()` 핸들러가 있는가?
- [ ] Promise.all 실패 시 부분 결과가 필요하면 Promise.allSettled를 사용하는가?
- [ ] 이벤트 리스너 내 비동기 작업에 try-catch가 있는가?
- [ ] unhandledRejection 핸들러가 프로세스 레벨에서 등록되어 있는가?

## 4. 공유 상태

### 모듈 레벨 변수 오염

```typescript
// ❌ 모듈 레벨 상태가 요청 간 공유됨
let requestCount = 0; // 모든 요청이 이 변수를 공유
const cache = new Map<string, any>(); // 메모리 누수 + 동시성 이슈

class AnalyticsService {
  async trackRequest(): Promise<void> {
    requestCount++; // 원자적이지 않음 (실제론 문제 드물지만 의도 불명확)
  }
}

// ✅ 요청 스코프 또는 명시적 격리
@Injectable({ scope: Scope.REQUEST }) // NestJS 요청 스코프
class RequestContextService {
  private readonly data = new Map<string, any>();

  set(key: string, value: any): void { this.data.set(key, value); }
  get(key: string): any { return this.data.get(key); }
}

// 캐시는 TTL과 최대 크기 제한
class CacheService {
  private readonly cache = new LRUCache<string, any>({
    max: 1000,
    ttl: 60 * 1000, // 1분
  });
}
```

### Singleton 서비스의 상태

```typescript
// ❌ Singleton 서비스에 요청별 상태 저장
@Injectable() // 기본 Singleton
class ReportService {
  private currentUser: User; // 모든 요청이 공유!

  setUser(user: User): void {
    this.currentUser = user; // 요청 A의 유저가 요청 B에서 보임
  }

  async generateReport(): Promise<Report> {
    return this.buildReport(this.currentUser);
  }
}

// ✅ 상태를 메서드 파라미터로 전달
@Injectable()
class ReportService {
  async generateReport(user: User): Promise<Report> {
    return this.buildReport(user); // 파라미터로 받아서 사용
  }
}
```

### 공유 상태 체크리스트

- [ ] Singleton 서비스에 요청별 상태를 저장하지 않는가?
- [ ] 모듈 레벨 변수가 의도적으로 공유되는 것인가?
- [ ] 인메모리 캐시에 크기 제한과 TTL이 있는가?
- [ ] AsyncLocalStorage 또는 REQUEST 스코프가 적절히 사용되고 있는가?

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| 레이스 컨디션 | 재고/잔액 등 경쟁 리소스의 원자성 | P0 |
| 데이터 오염 | Singleton에 요청별 상태 저장 | P0 |
| 데드락 가능성 | 비일관적 락 순서 | P0 |
| 에러 유실 | await 없는 Promise에 catch 없음 | P1 |
| 메모리 누수 | 크기 제한 없는 인메모리 캐시 | P1 |
| 부분 실패 | Promise.all에서 개별 에러 처리 없음 | P2 |
