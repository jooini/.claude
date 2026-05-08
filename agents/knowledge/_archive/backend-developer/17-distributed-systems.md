# Distributed Systems

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/distributed-systems

---

## 1. 분산 시스템의 어려움

```
네트워크는 신뢰할 수 없다 — 지연, 패킷 손실, 파티션
시계는 동기화되지 않는다 — NTP 오차, 이벤트 순서 불명확
프로세스는 언제든 죽을 수 있다 — 부분 실패
```

**Fallacies of Distributed Computing (오해들):**
1. 네트워크는 신뢰할 수 있다
2. 지연은 0이다
3. 대역폭은 무한하다
4. 네트워크는 안전하다
5. 토폴로지는 변하지 않는다
6. 관리자는 한 명이다
7. 전송 비용은 0이다
8. 네트워크는 동질하다

---

## 2. 일관성 모델

```
강한 일관성 (Strong Consistency)
  - 모든 읽기가 최신 쓰기를 반영
  - 구현: 단일 마스터, 2PC
  - 성능 저하, 가용성 감소

최종 일관성 (Eventual Consistency)
  - 언젠가는 일관성 도달
  - 구현: 비동기 복제, DNS
  - 성능 우수, 임시 불일치 허용

인과 일관성 (Causal Consistency)
  - 인과 관계가 있는 연산은 순서 보장
  - SNS 댓글 → 대댓글 순서
```

---

## 3. 분산 트랜잭션

### 2PC (Two-Phase Commit)

```
Phase 1 (Prepare):
  Coordinator → 모든 참여자: "커밋 준비됐나?"
  참여자들: 준비 or 거부 응답

Phase 2 (Commit/Rollback):
  모두 준비됐으면: Coordinator → 모든 참여자: "커밋"
  하나라도 거부: Coordinator → 모든 참여자: "롤백"

단점: Coordinator 장애 시 참여자들이 블로킹
```

### Saga 패턴 (권장)

```ts
// 각 단계를 독립 트랜잭션 + 보상 트랜잭션으로
// Choreography 방식 — 이벤트로 통신

// 1. 주문 생성
OrderCreatedEvent → 재고 서비스

// 2. 재고 예약 성공
InventoryReservedEvent → 결제 서비스

// 2-fail. 재고 부족
InventoryFailedEvent → 주문 취소 (보상)

// 3. 결제 성공
PaymentCompletedEvent → 주문 확정

// 3-fail. 결제 실패
PaymentFailedEvent → 재고 해제 (보상) → 주문 취소 (보상)
```

---

## 4. 분산 ID 생성

```ts
// UUID v4 — 랜덤, 정렬 불가
import { randomUUID } from 'crypto'
const id = randomUUID()  // '550e8400-e29b-41d4-a716-446655440000'

// ULID — 시간순 정렬 가능, UUID 호환
import { ulid } from 'ulid'
const id = ulid()  // '01ARZ3NDEKTSV4RRFFQ69G5FAV'

// Snowflake ID — Twitter 방식
// 41bit 타임스탬프 + 10bit 머신 ID + 12bit 시퀀스
// 초당 4096개, 69년간 유니크
class SnowflakeIdGenerator {
  private sequence = 0
  private lastTimestamp = -1

  generate(machineId: number): bigint {
    let timestamp = Date.now()
    if (timestamp === this.lastTimestamp) {
      this.sequence = (this.sequence + 1) & 0xFFF
      if (this.sequence === 0) {
        while (timestamp <= this.lastTimestamp) timestamp = Date.now()
      }
    } else {
      this.sequence = 0
    }
    this.lastTimestamp = timestamp
    return (BigInt(timestamp) << 22n) | (BigInt(machineId) << 12n) | BigInt(this.sequence)
  }
}
```

---

## 5. 분산 캐시 일관성

```ts
// Cache Invalidation 전략

// 1. TTL — 단순하지만 TTL 동안 stale 허용
await redis.setex(key, 300, value)

// 2. Write-Invalidate — 쓰기 시 캐시 삭제
async update(id: string, data: unknown) {
  await db.update(id, data)
  await redis.del(`resource:${id}`)
}

// 3. Write-Through — 쓰기 시 캐시도 함께 업데이트
async update(id: string, data: unknown) {
  const updated = await db.update(id, data)
  await redis.setex(`resource:${id}`, 300, JSON.stringify(updated))
  return updated
}

// 4. 버전 태그 — 관련 캐시 일괄 무효화
async updateUser(userId: string, data: unknown) {
  await db.update(userId, data)
  // 해당 사용자 관련 캐시 태그 버전 증가
  await redis.incr(`cache-version:user:${userId}`)
  // 캐시 키에 버전 포함 → 자동 무효화
}
```

---

## 6. 분산 추적 (Distributed Tracing)

```ts
// OpenTelemetry
import { trace, context, propagation } from '@opentelemetry/api'

const tracer = trace.getTracer('order-service')

async function processOrder(orderId: string) {
  const span = tracer.startSpan('processOrder')

  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      span.setAttribute('order.id', orderId)

      // 하위 서비스 호출 시 trace context 전파
      const headers = {}
      propagation.inject(context.active(), headers)

      const inventory = await inventoryService.reserve(orderId, { headers })

      span.addEvent('inventory.reserved')
      return inventory
    } catch (err) {
      span.recordException(err as Error)
      span.setStatus({ code: SpanStatusCode.ERROR })
      throw err
    } finally {
      span.end()
    }
  })
}
```

---

## 7. 안티패턴

- **분산 트랜잭션에 2PC**: Saga 패턴으로 대체
- **동기 호출 체인**: A→B→C→D — 부분 실패 시 전체 실패. 이벤트 기반으로
- **시계 기반 순서 보장**: NTP 오차 존재 → 논리 시계(Lamport Clock) 사용
- **재시도 없는 외부 서비스 호출**: 네트워크는 불안정
- **Trace ID 없는 로그**: 분산 환경에서 요청 추적 불가
