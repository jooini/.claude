# Domain-Driven Design

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/domain-driven-design

---

## 1. DDD 핵심 개념

복잡한 비즈니스 도메인을 코드로 표현하는 설계 방법론.

**핵심 원칙:** 코드가 비즈니스 언어를 반영해야 한다.

```
도메인 전문가가 "주문을 완료한다" → Order.complete()
도메인 전문가가 "재고가 부족하다" → InsufficientStockException
```

---

## 2. 빌딩 블록

### Entity

고유한 식별자를 가지는 객체. 식별자가 같으면 같은 객체.

```ts
// ❌ 빈약한 도메인 모델 (Anemic Domain Model)
class Order {
  id: string
  status: string
  items: OrderItem[]
  total: number
  // 로직이 없고 데이터만 있음
}

// ✅ 풍부한 도메인 모델 (Rich Domain Model)
class Order {
  private constructor(
    public readonly id: OrderId,
    private status: OrderStatus,
    private items: OrderItem[],
  ) {}

  static create(customerId: CustomerId, items: OrderItem[]): Order {
    if (items.length === 0) throw new DomainException('주문 항목이 없습니다')
    return new Order(OrderId.generate(), OrderStatus.PENDING, items)
  }

  complete(): void {
    if (this.status !== OrderStatus.PAID) {
      throw new DomainException('결제 완료 후 주문을 확정할 수 있습니다')
    }
    this.status = OrderStatus.COMPLETED
    this.addDomainEvent(new OrderCompletedEvent(this.id))
  }

  get total(): Money {
    return this.items.reduce((sum, item) => sum.add(item.subtotal), Money.zero())
  }
}
```

### Value Object

식별자 없이 값으로 동등성을 판단. 불변.

```ts
class Money {
  private constructor(
    private readonly amount: number,
    private readonly currency: string,
  ) {}

  static of(amount: number, currency: string): Money {
    if (amount < 0) throw new DomainException('금액은 0 이상이어야 합니다')
    return new Money(amount, currency)
  }

  add(other: Money): Money {
    if (this.currency !== other.currency) throw new DomainException('통화가 다릅니다')
    return new Money(this.amount + other.amount, this.currency)
  }

  equals(other: Money): boolean {
    return this.amount === other.amount && this.currency === other.currency
  }
}

class Email {
  private constructor(private readonly value: string) {}

  static of(value: string): Email {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
      throw new DomainException('유효하지 않은 이메일')
    }
    return new Email(value)
  }

  toString(): string { return this.value }
}
```

### Aggregate

연관된 Entity/Value Object의 묶음. 루트를 통해서만 접근.

```ts
// Order가 Aggregate Root
// OrderItem은 Order를 통해서만 접근/수정

class Order {  // Aggregate Root
  private items: OrderItem[] = []

  addItem(productId: ProductId, quantity: number, price: Money): void {
    // 비즈니스 규칙: 같은 상품 중복 추가 방지
    const existing = this.items.find(i => i.productId.equals(productId))
    if (existing) {
      existing.increaseQuantity(quantity)
    } else {
      this.items.push(OrderItem.create(productId, quantity, price))
    }
  }

  removeItem(productId: ProductId): void {
    this.items = this.items.filter(i => !i.productId.equals(productId))
  }
}

// ❌ Aggregate 내부 직접 조작
order.items.push(newItem)              // items가 public이면 규칙 우회 가능

// ✅ Aggregate Root를 통해서만
order.addItem(productId, quantity, price)
```

---

## 3. Domain Events

도메인에서 발생한 사건. 느슨한 결합 실현.

```ts
// 이벤트 정의
class OrderCompletedEvent {
  constructor(
    public readonly orderId: string,
    public readonly customerId: string,
    public readonly total: number,
    public readonly occurredAt: Date = new Date(),
  ) {}
}

// Aggregate에서 이벤트 발행
class Order {
  private domainEvents: DomainEvent[] = []

  complete(): void {
    this.status = OrderStatus.COMPLETED
    this.domainEvents.push(
      new OrderCompletedEvent(this.id.value, this.customerId.value, this.total.amount)
    )
  }

  pullDomainEvents(): DomainEvent[] {
    const events = [...this.domainEvents]
    this.domainEvents = []
    return events
  }
}

// Application Service에서 이벤트 처리
class CompleteOrderUseCase {
  async execute(orderId: string): Promise<void> {
    const order = await this.orderRepository.findById(orderId)
    order.complete()

    await this.orderRepository.save(order)

    // 이벤트 발행 (이메일, 포인트, 재고 차감 등은 이벤트 핸들러에서)
    const events = order.pullDomainEvents()
    await Promise.all(events.map(e => this.eventBus.publish(e)))
  }
}
```

---

## 4. Repository 패턴

```ts
// 도메인 인터페이스 (infrastructure 독립)
interface OrderRepository {
  findById(id: OrderId): Promise<Order | null>
  findByCustomerId(customerId: CustomerId): Promise<Order[]>
  save(order: Order): Promise<void>
  delete(id: OrderId): Promise<void>
}

// TypeORM 구현체
@Injectable()
class TypeOrmOrderRepository implements OrderRepository {
  constructor(
    @InjectRepository(OrderEntity)
    private readonly repo: Repository<OrderEntity>,
    private readonly mapper: OrderMapper,
  ) {}

  async findById(id: OrderId): Promise<Order | null> {
    const entity = await this.repo.findOne({
      where: { id: id.value },
      relations: ['items'],
    })
    return entity ? this.mapper.toDomain(entity) : null
  }

  async save(order: Order): Promise<void> {
    const entity = this.mapper.toEntity(order)
    await this.repo.save(entity)
  }
}
```

---

## 5. Bounded Context

대규모 시스템에서 도메인을 명시적 경계로 분리.

```
주문 컨텍스트        결제 컨텍스트       배송 컨텍스트
─────────────      ─────────────     ─────────────
Order               Payment           Shipment
OrderItem           Invoice           TrackingInfo
Customer(주문 관점)  Customer(청구 관점) Customer(배송 관점)
```

같은 "Customer"라도 컨텍스트마다 다른 속성/행위를 가진다.
컨텍스트 간 통신은 이벤트 또는 API를 통해.

---

## 6. NestJS에서 DDD 적용

```
src/
  modules/
    orders/
      domain/                  # 도메인 레이어
        entities/
          order.entity.ts      # Aggregate Root
          order-item.entity.ts
        value-objects/
          order-id.vo.ts
          money.vo.ts
        events/
          order-completed.event.ts
        repositories/
          order.repository.ts  # 인터페이스
      application/             # 애플리케이션 레이어
        use-cases/
          create-order.use-case.ts
          complete-order.use-case.ts
      infrastructure/          # 인프라 레이어
        persistence/
          typeorm-order.repository.ts
          order.mapper.ts
          order.orm-entity.ts
      presentation/            # 프레젠테이션 레이어
        orders.controller.ts
        dto/
```

---

## 7. 안티패턴

- **Anemic Domain Model**: 엔티티에 로직 없이 Service에 모든 로직
- **Aggregate 직접 접근**: Root를 우회해 내부 수정
- **DB 스키마 = 도메인 모델**: ORM Entity를 도메인 모델로 사용
- **도메인 레이어의 인프라 의존**: 도메인에서 TypeORM, Redis 직접 사용
- **너무 큰 Aggregate**: 트랜잭션/동시성 이슈 → 작게 유지
