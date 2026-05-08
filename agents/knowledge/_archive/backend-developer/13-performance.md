# Performance

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/performance

---

## 1. 성능 병목 진단

```
측정 → 분석 → 최적화 → 재측정

도구:
- clinic.js: Node.js 프로파일링
- pino: 고성능 로거 (구조화된 JSON)
- DataDog APM / New Relic: 분산 트레이싱
- EXPLAIN ANALYZE: DB 쿼리 분석
- Artillery / k6: 부하 테스트
```

---

## 2. 데이터베이스 최적화

### 인덱스

```ts
// 자주 조회하는 컬럼에 인덱스
@Entity('orders')
@Index(['userId', 'status'])   // 복합 인덱스
@Index(['createdAt'])
export class OrderEntity {
  @Column()
  @Index()
  userId: string

  @Column()
  status: string

  @CreateDateColumn()
  createdAt: Date
}

// 실행 계획 확인
const result = await dataSource.query(`
  EXPLAIN ANALYZE
  SELECT * FROM orders WHERE user_id = $1 AND status = $2
`, [userId, 'pending'])
```

### N+1 방지

```ts
// ❌ N+1
const orders = await orderRepo.find()
for (const order of orders) {
  order.items = await itemRepo.find({ where: { orderId: order.id } })
}

// ✅ 한 번에 조인
const orders = await orderRepo.find({
  relations: { items: true },
  where: { userId },
})

// 또는 DataLoader 패턴 (GraphQL 등)
const dataloader = new DataLoader<string, OrderItem[]>(async (orderIds) => {
  const items = await itemRepo.findBy({ orderId: In(orderIds as string[]) })
  return orderIds.map(id => items.filter(item => item.orderId === id))
})
```

### 페이지네이션 쿼리 최적화

```ts
// ❌ 느린 OFFSET (데이터 많을수록 느려짐)
SELECT * FROM orders ORDER BY created_at DESC LIMIT 20 OFFSET 10000

// ✅ 커서 기반
SELECT * FROM orders
WHERE created_at < $1  -- 이전 페이지의 마지막 created_at
ORDER BY created_at DESC
LIMIT 20

// ❌ COUNT(*) 전체 스캔
SELECT COUNT(*) FROM orders WHERE user_id = $1

// ✅ 예상 카운트 (정확하지 않아도 될 때)
SELECT reltuples::BIGINT AS estimate
FROM pg_class WHERE relname = 'orders'
```

---

## 3. 쿼리 최적화

```ts
// select 필드 제한 — 불필요한 데이터 전송 줄이기
const users = await userRepo
  .createQueryBuilder('u')
  .select(['u.id', 'u.name', 'u.email'])  // 필요한 것만
  .where('u.status = :status', { status: 'active' })
  .getMany()

// 집계 쿼리는 DB에서 — JS로 가져와서 처리 금지
const stats = await orderRepo
  .createQueryBuilder('o')
  .select('DATE_TRUNC(\'day\', o.created_at)', 'date')
  .addSelect('SUM(o.total)', 'revenue')
  .addSelect('COUNT(*)', 'count')
  .where('o.created_at >= :from', { from: startDate })
  .groupBy('DATE_TRUNC(\'day\', o.created_at)')
  .orderBy('date', 'ASC')
  .getRawMany()

// 대량 Insert — 개별 save보다 훨씬 빠름
await itemRepo
  .createQueryBuilder()
  .insert()
  .into(OrderItemEntity)
  .values(items)
  .execute()
```

---

## 4. 애플리케이션 레이어 최적화

### 병렬 처리

```ts
// ❌ 순차 — 총 합산 시간
const user = await userService.findById(userId)      // 50ms
const orders = await orderService.findByUser(userId) // 80ms
const points = await pointService.findByUser(userId) // 60ms
// 총 190ms

// ✅ 병렬 — 가장 긴 시간
const [user, orders, points] = await Promise.all([
  userService.findById(userId),
  orderService.findByUser(userId),
  pointService.findByUser(userId),
])
// 총 80ms
```

### 응답 스트리밍

```ts
// 대용량 데이터 스트리밍 — 메모리 효율
@Get('export')
@Header('Content-Type', 'text/csv')
@Header('Content-Disposition', 'attachment; filename=users.csv')
async exportUsers(@Res() res: Response) {
  const stream = new PassThrough()
  res.pipe(stream)

  stream.write('id,name,email\n')

  // 커서로 청크 단위 처리
  const cursor = await userRepo
    .createQueryBuilder('u')
    .stream()

  cursor.on('data', (user) => {
    stream.write(`${user.id},${user.name},${user.email}\n`)
  })
  cursor.on('end', () => stream.end())
  cursor.on('error', (err) => stream.destroy(err))
}
```

---

## 5. 캐싱 전략 (성능 관점)

```ts
// 캐시 적합 기준
// - 읽기 빈도 높음
// - 변경 빈도 낮음
// - 계산 비용 높음

// 자주 읽고 거의 안 바뀌는 데이터 — 긴 TTL
@Cacheable('app:config', 3600)  // 1시간
async getAppConfig(): Promise<AppConfig> { ... }

// 사용자별 집계 — 중간 TTL
@Cacheable(userId => `user:${userId}:stats`, 300)  // 5분
async getUserStats(userId: string): Promise<UserStats> { ... }

// 실시간성 필요한 재고 — 짧은 TTL 또는 캐시 안 함
async getStock(productId: string): Promise<number> {
  return this.stockRepo.findByProductId(productId)  // 캐시 없이 직접 조회
}
```

---

## 6. Connection Pool 튜닝

```ts
TypeOrmModule.forRoot({
  type: 'postgres',
  extra: {
    // 기본값 10 — 워커 수 * 2~3 권장
    max: 20,
    // 연결 대기 최대 시간
    connectionTimeoutMillis: 5000,
    // 유휴 연결 유지 시간
    idleTimeoutMillis: 30000,
    // 연결 상태 확인 주기
    keepAlive: true,
  },
})

// Redis 커넥션 풀
const redis = new Redis({
  maxRetriesPerRequest: 3,
  connectTimeout: 5000,
  lazyConnect: true,
})
```

---

## 7. 부하 테스트

```yaml
# k6 스크립트
# k6 run load-test.js
import http from 'k6/http'
import { check, sleep } from 'k6'

export const options = {
  stages: [
    { duration: '30s', target: 50 },   // 50 VU로 증가
    { duration: '1m',  target: 50 },   // 유지
    { duration: '30s', target: 0 },    // 감소
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95%가 500ms 이내
    http_req_failed:   ['rate<0.01'],  // 에러율 1% 미만
  },
}

export default function() {
  const res = http.get('https://api.example.com/users')
  check(res, { 'status 200': r => r.status === 200 })
  sleep(1)
}
```

---

## 8. 안티패턴

- **조기 최적화**: 병목 측정 전 최적화
- **인덱스 없는 FK 컬럼**: 조인/조회 시 풀 스캔
- **트랜잭션 내 외부 API 호출**: 트랜잭션 시간 증가 → 락 경합
- **동기 블로킹 작업**: CPU 집약 작업은 워커 스레드로
- **전체 엔티티 로딩**: 필요한 컬럼만 select
