# Message Queues

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/message-queues

---

## 1. 메시지 큐가 필요한 경우

```
동기 처리 → 비동기로 전환
  이메일/SMS 발송
  푸시 알림
  이미지 리사이징
  보고서 생성
  외부 API 연동 (웹훅)

워크로드 평준화 (Load Leveling)
  트래픽 급증 시 큐가 버퍼 역할

서비스 간 결합도 감소
  발행자는 구독자를 몰라도 됨
```

---

## 2. BullMQ (Redis 기반)

```bash
npm install bullmq
```

```ts
// queue.module.ts
import { BullModule } from '@nestjs/bullmq'

BullModule.forRoot({
  connection: {
    host: process.env.REDIS_HOST,
    port: Number(process.env.REDIS_PORT),
  },
})

BullModule.registerQueue(
  { name: 'email' },
  { name: 'image-processing' },
  { name: 'notifications' },
)
```

### 잡 생성

```ts
@Injectable()
export class OrdersService {
  constructor(
    @InjectQueue('email') private emailQueue: Queue,
    @InjectQueue('notifications') private notifQueue: Queue,
  ) {}

  async completeOrder(orderId: string) {
    const order = await this.orderRepo.complete(orderId)

    // 이메일 발송 — 3번 재시도, 지수 백오프
    await this.emailQueue.add(
      'order-confirmation',
      { orderId: order.id, userId: order.userId },
      {
        attempts: 3,
        backoff: { type: 'exponential', delay: 1000 },
        removeOnComplete: 100,  // 완료된 잡 100개만 보관
        removeOnFail: 50,
      },
    )

    // 지연 실행 — 1시간 후 리뷰 요청
    await this.notifQueue.add(
      'review-request',
      { orderId: order.id },
      { delay: 60 * 60 * 1000 },
    )

    return order
  }
}
```

### 잡 처리 (Processor)

```ts
@Processor('email')
export class EmailProcessor {
  private readonly logger = new Logger(EmailProcessor.name)

  @Process('order-confirmation')
  async handleOrderConfirmation(job: Job<OrderConfirmationData>) {
    const { orderId, userId } = job.data

    try {
      const [order, user] = await Promise.all([
        this.orderRepo.findById(orderId),
        this.userRepo.findById(userId),
      ])

      await this.mailerService.sendOrderConfirmation(user.email, order)
      this.logger.log(`Order confirmation sent: ${orderId}`)
    } catch (error) {
      this.logger.error(`Failed to send email for order ${orderId}`, error)
      throw error  // 재시도 트리거
    }
  }

  @OnQueueFailed()
  async onFailed(job: Job, error: Error) {
    // 모든 재시도 실패 후 알림
    if (job.attemptsMade >= job.opts.attempts!) {
      await this.alertService.notify(`Job ${job.name} permanently failed`, error)
    }
  }
}
```

---

## 3. 잡 스케줄링

```ts
// 반복 잡 — cron 형식
await queue.add(
  'daily-report',
  { reportType: 'daily' },
  {
    repeat: { cron: '0 9 * * *' },  // 매일 오전 9시
    jobId: 'daily-report',           // 중복 방지
  },
)

// NestJS @Cron 데코레이터
@Injectable()
export class SchedulerService {
  @Cron('0 0 * * *')  // 매일 자정
  async cleanupExpiredSessions() {
    await this.sessionRepo.deleteExpired()
  }

  @Cron(CronExpression.EVERY_5_MINUTES)
  async processOutbox() {
    await this.outboxService.process()
  }
}
```

---

## 4. 우선순위 큐

```ts
// 높은 priority가 먼저 처리
await queue.add('send-email', data, { priority: 1 })   // 최우선
await queue.add('send-email', data, { priority: 10 })  // 낮은 우선순위
```

---

## 5. 잡 모니터링 — Bull Board

```ts
import { createBullBoard } from '@bull-board/api'
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter'
import { ExpressAdapter } from '@bull-board/express'

const serverAdapter = new ExpressAdapter()
serverAdapter.setBasePath('/admin/queues')

createBullBoard({
  queues: [
    new BullMQAdapter(emailQueue),
    new BullMQAdapter(notifQueue),
  ],
  serverAdapter,
})

app.use('/admin/queues', serverAdapter.getRouter())
// http://localhost:3000/admin/queues — 대시보드
```

---

## 6. Dead Letter Queue (DLQ)

모든 재시도 실패 시 DLQ로 이동. 나중에 수동 검토/재처리.

```ts
@OnQueueFailed()
async onFailed(job: Job, error: Error) {
  if (job.attemptsMade >= (job.opts.attempts ?? 1)) {
    // DLQ에 이동
    await this.dlqQueue.add(job.name, {
      originalData: job.data,
      error: error.message,
      failedAt: new Date(),
      attempts: job.attemptsMade,
    })
    this.logger.error(`Job moved to DLQ: ${job.name} #${job.id}`)
  }
}
```

---

## 7. Kafka (대용량 이벤트 스트리밍)

```ts
// KafkaJS
import { Kafka } from 'kafkajs'

const kafka = new Kafka({
  clientId: 'order-service',
  brokers: process.env.KAFKA_BROKERS!.split(','),
})

// 발행자
const producer = kafka.producer()
await producer.send({
  topic: 'order-events',
  messages: [{
    key: orderId,                          // 같은 키 → 같은 파티션 → 순서 보장
    value: JSON.stringify({ type: 'OrderCompleted', orderId }),
    headers: { 'correlation-id': requestId },
  }],
})

// 소비자 — Consumer Group으로 병렬 처리
const consumer = kafka.consumer({ groupId: 'notification-service' })
await consumer.subscribe({ topic: 'order-events', fromBeginning: false })
await consumer.run({
  eachMessage: async ({ message }) => {
    const event = JSON.parse(message.value!.toString())
    await handleEvent(event)
  },
})
```

---

## 8. 안티패턴

- **재시도 없는 잡**: 네트워크 오류 등 일시적 실패 대비
- **DLQ 없음**: 영구 실패 잡 유실
- **큐 크기 모니터링 안 함**: 적체 시 알림 필요
- **대용량 페이로드**: 큐에는 ID만 저장, 데이터는 DB에서 조회
- **잡 중복 처리 미고려**: 멱등성 있는 잡 처리 필수
