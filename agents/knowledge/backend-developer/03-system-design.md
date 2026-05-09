# System Design

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/system-design

---

## 1. 시스템 설계 접근법

```
1. 요구사항 명확화
   - 기능 요구사항: 무엇을 해야 하는가
   - 비기능 요구사항: 얼마나 빠르게, 얼마나 안정적으로

2. 규모 추정
   - DAU (Daily Active Users)
   - 읽기/쓰기 비율
   - 데이터 크기

3. 고수준 설계
   - 주요 컴포넌트와 데이터 흐름

4. 상세 설계
   - DB 스키마, API 설계, 알고리즘

5. 병목 파악 및 개선
   - 캐싱, 샤딩, 로드밸런싱
```

---

## 2. 확장성 패턴

### 수직 vs 수평 확장

```
수직 확장 (Scale Up)
  서버 사양 증가 (CPU, RAM)
  → 한계 있음, 비용 급증
  → 빠르고 간단 (단기 해결책)

수평 확장 (Scale Out)
  서버 대수 증가
  → 이론적으로 무한 확장
  → 무상태(Stateless) 설계 필요
```

### 무상태 서버 설계

```ts
// ❌ 서버 메모리에 세션 저장 — 수평 확장 불가
const sessions = new Map<string, Session>()

// ✅ 외부 저장소 (Redis) 사용
@Injectable()
export class SessionService {
  constructor(private readonly redis: Redis) {}

  async set(sessionId: string, data: Session): Promise<void> {
    await this.redis.setex(sessionId, 3600, JSON.stringify(data))
  }

  async get(sessionId: string): Promise<Session | null> {
    const data = await this.redis.get(sessionId)
    return data ? JSON.parse(data) : null
  }
}
```

---

## 3. 데이터베이스 확장

### 읽기 복제 (Read Replica)

```
Writer DB ──┬── Reader DB 1  (조회 트래픽 분산)
            └── Reader DB 2

쓰기: Writer로만
읽기: Reader로 (로드밸런싱)
```

```ts
// TypeORM 읽기/쓰기 분리
TypeOrmModule.forRoot({
  replication: {
    master: { host: process.env.DB_MASTER_HOST, ... },
    slaves: [
      { host: process.env.DB_SLAVE1_HOST, ... },
      { host: process.env.DB_SLAVE2_HOST, ... },
    ],
  },
})
```

### 샤딩 (Sharding)

```
데이터를 여러 DB에 분산
User ID % 4 → 0~3번 샤드 중 하나

주의: 조인, 트랜잭션이 샤드 간 불가
→ 설계 단계에서 샤딩 키 신중하게 결정
```

---

## 4. 캐싱 계층

```
Client
  └── CDN (정적 자산, 엣지 캐시)
        └── API Gateway
              └── Application Cache (Redis)
                    └── Database
```

```ts
// Redis 캐시 패턴
@Injectable()
export class UsersService {
  private readonly CACHE_TTL = 300  // 5분

  async findById(id: string): Promise<User> {
    const cacheKey = `user:${id}`

    // Cache-Aside 패턴
    const cached = await this.redis.get(cacheKey)
    if (cached) return JSON.parse(cached)

    const user = await this.usersRepository.findById(id)
    if (!user) throw new NotFoundException()

    await this.redis.setex(cacheKey, this.CACHE_TTL, JSON.stringify(user))
    return user
  }

  async update(id: string, dto: UpdateUserDto): Promise<User> {
    const user = await this.usersRepository.update(id, dto)
    await this.redis.del(`user:${id}`)  // 캐시 무효화
    return user
  }
}
```

---

## 5. 메시지 큐

동기 → 비동기로 전환해 시스템 결합도 감소, 성능 향상.

```
주문 서비스 → 큐 → 이메일 서비스
                └── 재고 서비스
                └── 포인트 서비스
```

```ts
// BullMQ (Redis 기반)
// 주문 완료 후 비동기 처리
@Injectable()
export class OrdersService {
  constructor(
    @InjectQueue('order-notifications') private queue: Queue,
  ) {}

  async createOrder(dto: CreateOrderDto): Promise<Order> {
    const order = await this.ordersRepository.create(dto)

    // 동기 응답 후 비동기로 처리
    await this.queue.add('order-completed', {
      orderId: order.id,
      userId: order.userId,
      amount: order.total,
    })

    return order
  }
}

// 큐 소비자
@Processor('order-notifications')
export class OrderNotificationsProcessor {
  @Process('order-completed')
  async handleOrderCompleted(job: Job<OrderCompletedPayload>) {
    const { orderId, userId } = job.data
    await this.mailerService.sendOrderConfirmation(userId, orderId)
    await this.pointsService.award(userId, job.data.amount)
  }
}
```

---

## 6. 로드밸런싱

```
클라이언트 → Load Balancer → 서버 1
                           → 서버 2
                           → 서버 3

알고리즘:
- Round Robin: 순서대로
- Least Connection: 연결 수 가장 적은 서버
- IP Hash: 같은 클라이언트 → 같은 서버 (세션 유지)
```

---

## 7. CAP 정리

분산 시스템에서 3가지를 동시에 만족할 수 없다.

```
C (Consistency)    — 모든 노드가 같은 데이터
A (Availability)   — 항상 응답 가능
P (Partition Tolerance) — 네트워크 분리에도 동작

네트워크 분리(P)는 현실에서 반드시 발생
→ CP (일관성 우선): 금융, 재고
→ AP (가용성 우선): SNS 피드, 검색
```

---

## 8. 안티패턴

- **단일 장애점(SPOF)**: DB, 서버 모두 이중화
- **동기 처리 남발**: 이메일 발송, 푸시 알림 등은 큐로 비동기화
- **캐시 없는 조회 집중 API**: DB 병목 → Redis 캐싱
- **트랜잭션 범위 과다**: 긴 트랜잭션 → 데드락, 성능 저하
- **조기 최적화**: 측정 먼저, 최적화는 병목 확인 후
