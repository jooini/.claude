# Data Patterns

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/data-patterns

---

## 1. Repository 패턴

데이터 접근 로직을 Service에서 분리.

```ts
// 인터페이스 정의 (도메인 레이어)
interface IUserRepository {
  findById(id: string): Promise<User | null>
  findByEmail(email: string): Promise<User | null>
  findAll(query: GetUsersQuery): Promise<PaginatedResult<User>>
  save(user: User): Promise<User>
  delete(id: string): Promise<void>
}

// TypeORM 구현 (인프라 레이어)
@Injectable()
export class UserRepository implements IUserRepository {
  constructor(
    @InjectRepository(UserEntity)
    private readonly repo: Repository<UserEntity>,
  ) {}

  async findById(id: string): Promise<User | null> {
    const entity = await this.repo.findOne({ where: { id } })
    return entity ? UserMapper.toDomain(entity) : null
  }

  async findAll({ page, limit, search, status }: GetUsersQuery) {
    const qb = this.repo.createQueryBuilder('u')
    if (search) qb.where('u.name ILIKE :search', { search: `%${search}%` })
    if (status) qb.andWhere('u.status = :status', { status })

    const [entities, total] = await qb
      .orderBy('u.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit)
      .getManyAndCount()

    return {
      data: entities.map(UserMapper.toDomain),
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    }
  }
}
```

---

## 2. Unit of Work 패턴

여러 Repository를 하나의 트랜잭션으로 묶기.

```ts
@Injectable()
export class UnitOfWork {
  constructor(private readonly dataSource: DataSource) {}

  async withTransaction<T>(work: (manager: EntityManager) => Promise<T>): Promise<T> {
    return this.dataSource.transaction(work)
  }
}

// 사용
@Injectable()
export class OrdersService {
  constructor(
    private readonly uow: UnitOfWork,
    private readonly orderRepo: OrderRepository,
    private readonly inventoryRepo: InventoryRepository,
  ) {}

  async createOrder(dto: CreateOrderDto): Promise<Order> {
    return this.uow.withTransaction(async manager => {
      const order = await this.orderRepo.create(dto, manager)
      await this.inventoryRepo.decrease(dto.items, manager)
      return order
    })
  }
}
```

---

## 3. CQRS (Command Query Responsibility Segregation)

읽기(Query)와 쓰기(Command)를 분리.

```ts
// Command — 상태 변경
class CreateUserCommand {
  constructor(
    public readonly email: string,
    public readonly name: string,
    public readonly password: string,
  ) {}
}

@CommandHandler(CreateUserCommand)
export class CreateUserHandler implements ICommandHandler<CreateUserCommand> {
  constructor(private readonly userRepo: UserRepository) {}

  async execute(command: CreateUserCommand): Promise<User> {
    const exists = await this.userRepo.existsByEmail(command.email)
    if (exists) throw new ConflictException('이미 사용 중인 이메일')

    return this.userRepo.save(User.create(command))
  }
}

// Query — 데이터 조회
class GetUserQuery {
  constructor(public readonly id: string) {}
}

@QueryHandler(GetUserQuery)
export class GetUserHandler implements IQueryHandler<GetUserQuery> {
  // 읽기 전용 Repository — 복잡한 조인 쿼리 가능
  constructor(private readonly readRepo: UserReadRepository) {}

  async execute(query: GetUserQuery): Promise<UserDetailDto> {
    const user = await this.readRepo.findDetailById(query.id)
    if (!user) throw new NotFoundException()
    return user
  }
}
```

```ts
// NestJS CQRS 모듈
import { CqrsModule, CommandBus, QueryBus } from '@nestjs/cqrs'

@Controller('users')
export class UsersController {
  constructor(
    private readonly commandBus: CommandBus,
    private readonly queryBus: QueryBus,
  ) {}

  @Post()
  create(@Body() dto: CreateUserDto) {
    return this.commandBus.execute(new CreateUserCommand(dto.email, dto.name, dto.password))
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.queryBus.execute(new GetUserQuery(id))
  }
}
```

---

## 4. Event Sourcing

상태 대신 이벤트를 저장. 현재 상태는 이벤트 재생으로 복원.

```ts
// 이벤트 저장소
interface OrderEvent {
  type: 'OrderCreated' | 'ItemAdded' | 'OrderPaid' | 'OrderCompleted'
  aggregateId: string
  payload: Record<string, unknown>
  occurredAt: Date
  version: number
}

// 이벤트로 상태 복원
function replayOrder(events: OrderEvent[]): Order {
  return events.reduce((order, event) => {
    switch (event.type) {
      case 'OrderCreated': return Order.create(event.payload)
      case 'ItemAdded':    return order.addItem(event.payload)
      case 'OrderPaid':    return order.pay()
      case 'OrderCompleted': return order.complete()
    }
  }, null as unknown as Order)
}
```

**언제 사용:** 감사 로그 필수, 시간 여행 디버깅, 복잡한 도메인. 일반 CRUD에는 과도함.

---

## 5. Outbox 패턴

트랜잭션과 이벤트 발행의 원자성 보장.

```
문제: DB 저장 성공 → 이벤트 발행 실패 → 불일치

해결: DB 저장 + Outbox 테이블 저장 (같은 트랜잭션)
     → 별도 프로세스가 Outbox 읽어서 이벤트 발행
```

```ts
// 트랜잭션 내에서 함께 저장
await dataSource.transaction(async manager => {
  const order = await manager.save(OrderEntity, orderData)

  // 같은 트랜잭션에 Outbox 레코드 저장
  await manager.save(OutboxEntity, {
    aggregateId: order.id,
    eventType: 'OrderCreated',
    payload: JSON.stringify({ orderId: order.id, userId: order.userId }),
    status: 'pending',
  })
})

// 별도 스케줄러가 Outbox 폴링
@Cron('*/5 * * * * *')  // 5초마다
async processOutbox() {
  const pending = await this.outboxRepo.findPending(100)
  for (const event of pending) {
    await this.eventBus.publish(event)
    await this.outboxRepo.markProcessed(event.id)
  }
}
```

---

## 6. Saga 패턴

분산 트랜잭션 — 여러 서비스에 걸친 비즈니스 프로세스 조율.

```
주문 Saga:
1. 주문 생성 → 재고 예약 요청
2. 재고 예약 성공 → 결제 요청
3. 결제 성공 → 주문 확정
4. (보상) 결제 실패 → 재고 예약 취소
```

```ts
@Injectable()
export class OrderSaga {
  @Saga()
  orderFlow = (events$: Observable<OrderCreatedEvent>) =>
    events$.pipe(
      ofType(OrderCreatedEvent),
      map(event => new ReserveInventoryCommand(event.orderId, event.items)),
    )

  @Saga()
  inventoryReserved = (events$: Observable<InventoryReservedEvent>) =>
    events$.pipe(
      ofType(InventoryReservedEvent),
      map(event => new ProcessPaymentCommand(event.orderId, event.amount)),
    )

  @Saga()
  paymentFailed = (events$: Observable<PaymentFailedEvent>) =>
    events$.pipe(
      ofType(PaymentFailedEvent),
      map(event => new ReleaseInventoryCommand(event.orderId)),  // 보상 트랜잭션
    )
}
```

---

## 7. 안티패턴

- **Service에 직접 쿼리**: Repository 없이 `@InjectRepository`로 Service에서 직접 사용
- **도메인 로직을 Repository에**: Repository는 데이터 접근만
- **CQRS 오버엔지니어링**: 단순 CRUD에 CQRS 적용 → 불필요한 복잡성
- **Outbox 없는 이벤트 발행**: 트랜잭션 밖 이벤트 발행 → 유실 가능
