# Concurrency

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/concurrency

---

## 1. 동시성 문제 유형

```
Race Condition   — 여러 요청이 같은 자원을 동시에 수정
Deadlock         — 두 트랜잭션이 서로의 락을 기다림
Stale Read       — 캐시/복제 지연으로 오래된 데이터 읽음
Lost Update      — 동시 수정으로 한쪽 변경 사항이 덮어쓰여짐
```

---

## 2. 데이터베이스 락

### 비관적 락 (Pessimistic Lock)

충돌이 자주 발생하는 경우. 읽을 때부터 락.

```ts
// TypeORM — SELECT FOR UPDATE
const queryRunner = dataSource.createQueryRunner()
await queryRunner.connect()
await queryRunner.startTransaction()

try {
  // 락 획득 — 다른 트랜잭션이 이 행을 수정/읽기(FOR UPDATE) 불가
  const product = await queryRunner.manager
    .createQueryBuilder(ProductEntity, 'p')
    .setLock('pessimistic_write')  // SELECT ... FOR UPDATE
    .where('p.id = :id', { id: productId })
    .getOne()

  if (!product || product.stock < quantity) {
    throw new InsufficientStockException(productId, quantity, product?.stock ?? 0)
  }

  product.stock -= quantity
  await queryRunner.manager.save(product)
  await queryRunner.commitTransaction()
} catch (err) {
  await queryRunner.rollbackTransaction()
  throw err
} finally {
  await queryRunner.release()
}
```

### 낙관적 락 (Optimistic Lock)

충돌이 드문 경우. version 컬럼으로 충돌 감지.

```ts
@Entity()
export class ProductEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string

  @Column()
  stock: number

  @VersionColumn()          // 변경 시 자동 증가
  version: number
}

// 저장 시 version 불일치 → OptimisticLockVersionMismatchError
try {
  const product = await productRepo.findOne({ where: { id } })
  product.stock -= quantity
  await productRepo.save(product)  // version이 DB와 다르면 에러
} catch (err) {
  if (err instanceof OptimisticLockVersionMismatchError) {
    throw new ConflictException('동시 수정이 발생했습니다. 다시 시도해 주세요.')
  }
  throw err
}
```

---

## 3. 분산 락 (Distributed Lock)

여러 서버 인스턴스 간 락 — Redis 사용.

```ts
@Injectable()
export class DistributedLockService {
  constructor(@InjectRedis() private readonly redis: Redis) {}

  async acquire(key: string, ttlMs: number): Promise<string | null> {
    const token = randomUUID()
    // NX: 키 없을 때만 설정 (원자적), PX: 밀리초 TTL
    const result = await this.redis.set(`lock:${key}`, token, 'NX', 'PX', ttlMs)
    return result === 'OK' ? token : null
  }

  async release(key: string, token: string): Promise<void> {
    // Lua 스크립트로 원자적 확인 + 삭제
    const script = `
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    `
    await this.redis.eval(script, 1, `lock:${key}`, token)
  }

  async withLock<T>(key: string, ttlMs: number, fn: () => Promise<T>): Promise<T> {
    const token = await this.acquire(key, ttlMs)
    if (!token) throw new ConflictException('다른 프로세스가 처리 중입니다. 잠시 후 재시도하세요.')

    try {
      return await fn()
    } finally {
      await this.release(key, token)
    }
  }
}

// 사용
async processPayment(orderId: string) {
  return this.lockService.withLock(`payment:${orderId}`, 30000, async () => {
    // 이 블록은 동시에 하나만 실행됨
    const order = await this.orderRepo.findById(orderId)
    await this.paymentGateway.charge(order)
    await this.orderRepo.markPaid(orderId)
  })
}
```

---

## 4. 원자적 연산

```ts
// ❌ Race condition — 읽기 → 계산 → 쓰기 사이에 다른 요청이 끼어들 수 있음
const product = await productRepo.findOne({ where: { id } })
product.stock -= quantity
await productRepo.save(product)  // 다른 요청이 이미 수정했을 수 있음

// ✅ 원자적 감소 — DB 레벨에서 원자적 처리
await productRepo
  .createQueryBuilder()
  .update(ProductEntity)
  .set({ stock: () => `stock - ${quantity}` })
  .where('id = :id AND stock >= :quantity', { id: productId, quantity })
  .execute()

// 영향받은 행 수로 성공 여부 확인
const result = await ...execute()
if (result.affected === 0) {
  throw new InsufficientStockException(productId, quantity, 0)
}

// Redis 원자적 연산
await this.redis.incrby(`stock:${productId}`, -quantity)
```

---

## 5. 큐를 통한 직렬화

동시 요청을 큐로 순차 처리.

```ts
// BullMQ — 동시 처리 수 제한
@Processor('payments', { concurrency: 1 })  // 순차 처리
export class PaymentProcessor {
  @Process()
  async handlePayment(job: Job<PaymentJobData>) {
    const { orderId } = job.data
    await this.processPayment(orderId)
  }
}

// 특정 사용자 요청 순차화 — 같은 userId로 FIFO
await queue.add('payment', { orderId, userId }, {
  jobId: `payment:${orderId}`,       // 중복 방지
  removeOnComplete: true,
})
```

---

## 6. Idempotency (멱등성)

같은 요청을 여러 번 보내도 결과가 동일하게.

```ts
// Idempotency Key 기반
@Post('payments')
async createPayment(
  @Headers('idempotency-key') idempotencyKey: string,
  @Body() dto: CreatePaymentDto,
) {
  if (!idempotencyKey) throw new BadRequestException('Idempotency-Key 헤더 필요')

  // 캐시에서 이미 처리된 요청 확인
  const cached = await this.redis.get(`idem:${idempotencyKey}`)
  if (cached) return JSON.parse(cached)  // 이전 응답 그대로 반환

  const result = await this.paymentsService.create(dto)

  // 결과 캐시 (24시간)
  await this.redis.setex(`idem:${idempotencyKey}`, 86400, JSON.stringify(result))

  return result
}
```

---

## 7. 트랜잭션 격리 수준

```sql
-- READ COMMITTED (PostgreSQL 기본) — 커밋된 데이터만 읽음
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- REPEATABLE READ — 트랜잭션 내 같은 쿼리 결과 동일
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- SERIALIZABLE — 완전한 직렬화 (가장 안전, 가장 느림)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

```ts
// TypeORM에서 격리 수준 지정
await dataSource.transaction('SERIALIZABLE', async manager => {
  // 완전 직렬화된 트랜잭션
})
```

---

## 8. 안티패턴

- **락 없는 재고/포인트 처리**: 원자적 연산 또는 비관적 락
- **너무 긴 트랜잭션**: 락 경합 → 최소 범위로
- **분산 환경에서 로컬 변수로 락**: 서버 재시작/다중 인스턴스에서 무효
- **멱등성 없는 결제 API**: 네트워크 재시도로 중복 결제
- **데드락 미처리**: 재시도 로직 필수
