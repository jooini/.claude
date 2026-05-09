# 리팩토링 가이드

> 참조 링크: https://refactoring.guru/refactoring/techniques, https://martinfowler.com/books/refactoring.html

---

## 개요

리팩토링은 외부 동작을 변경하지 않으면서 내부 구조를 개선하는 작업이다. 리뷰어는 리팩토링이 안전하게 수행되었는지, 기능 변경과 혼재되지 않았는지, 점진적으로 진행되는지를 검토한다.

## 1. 안전한 리팩토링 기법

### Extract Method

```typescript
// ❌ 리팩토링 전: 한 메서드에 여러 관심사
async processOrder(dto: CreateOrderDto): Promise<Order> {
  // 유효성 검증
  if (!dto.items || dto.items.length === 0) {
    throw new BadRequestException('주문 항목이 비어있습니다');
  }
  for (const item of dto.items) {
    const product = await this.productRepo.findOne({ where: { id: item.productId } });
    if (!product) throw new NotFoundException(`상품 ${item.productId}을 찾을 수 없습니다`);
    if (product.stock < item.quantity) {
      throw new BadRequestException(`상품 ${product.name}의 재고가 부족합니다`);
    }
  }

  // 가격 계산
  let total = 0;
  for (const item of dto.items) {
    const product = await this.productRepo.findOne({ where: { id: item.productId } });
    total += product.price * item.quantity;
  }

  // 주문 생성
  const order = this.orderRepo.create({
    userId: dto.userId,
    items: dto.items,
    total,
    status: 'pending',
  });
  return this.orderRepo.save(order);
}

// ✅ 리팩토링 후: 관심사별 메서드 분리
async processOrder(dto: CreateOrderDto): Promise<Order> {
  await this.validateOrderItems(dto.items);
  const total = await this.calculateTotal(dto.items);
  return this.createOrder(dto.userId, dto.items, total);
}

private async validateOrderItems(items: OrderItemDto[]): Promise<void> {
  if (!items || items.length === 0) {
    throw new BadRequestException('주문 항목이 비어있습니다');
  }

  for (const item of items) {
    const product = await this.productRepo.findOne({ where: { id: item.productId } });
    if (!product) throw new NotFoundException(`상품 ${item.productId}을 찾을 수 없습니다`);
    if (product.stock < item.quantity) {
      throw new BadRequestException(`상품 ${product.name}의 재고가 부족합니다`);
    }
  }
}

private async calculateTotal(items: OrderItemDto[]): Promise<number> {
  let total = 0;
  for (const item of items) {
    const product = await this.productRepo.findOne({ where: { id: item.productId } });
    total += product.price * item.quantity;
  }
  return total;
}

private async createOrder(userId: string, items: OrderItemDto[], total: number): Promise<Order> {
  const order = this.orderRepo.create({ userId, items, total, status: 'pending' });
  return this.orderRepo.save(order);
}
```

### Replace Conditional with Polymorphism

```typescript
// ❌ 타입별 분기가 여러 곳에 반복
class NotificationService {
  async send(notification: Notification): Promise<void> {
    switch (notification.type) {
      case 'email':
        await this.sendEmail(notification);
        break;
      case 'sms':
        await this.sendSms(notification);
        break;
      case 'push':
        await this.sendPush(notification);
        break;
      default:
        throw new Error(`Unknown type: ${notification.type}`);
    }
  }

  getTemplate(notification: Notification): string {
    switch (notification.type) { // 같은 switch 반복
      case 'email': return this.getEmailTemplate(notification);
      case 'sms': return this.getSmsTemplate(notification);
      case 'push': return this.getPushTemplate(notification);
    }
  }
}

// ✅ 다형성으로 분기 제거
interface NotificationChannel {
  send(notification: Notification): Promise<void>;
  getTemplate(notification: Notification): string;
}

class EmailChannel implements NotificationChannel {
  async send(notification: Notification): Promise<void> { /* 이메일 전송 */ }
  getTemplate(notification: Notification): string { /* 이메일 템플릿 */ }
}

class SmsChannel implements NotificationChannel {
  async send(notification: Notification): Promise<void> { /* SMS 전송 */ }
  getTemplate(notification: Notification): string { /* SMS 템플릿 */ }
}

class NotificationService {
  constructor(
    private readonly channels: Map<string, NotificationChannel>,
  ) {}

  async send(notification: Notification): Promise<void> {
    const channel = this.channels.get(notification.type);
    if (!channel) throw new Error(`Unknown type: ${notification.type}`);
    await channel.send(notification);
  }
}
```

### Introduce Parameter Object

```typescript
// ❌ 파라미터가 너무 많음
async searchOrders(
  userId: string,
  status: OrderStatus,
  startDate: Date,
  endDate: Date,
  minTotal: number,
  maxTotal: number,
  page: number,
  limit: number,
  sortBy: string,
  sortOrder: 'asc' | 'desc',
): Promise<PaginatedResult<Order>> {
  // ...
}

// ✅ 파라미터 객체로 묶음
interface SearchOrdersQuery {
  userId: string;
  status?: OrderStatus;
  dateRange?: { start: Date; end: Date };
  totalRange?: { min: number; max: number };
  pagination: { page: number; limit: number };
  sort?: { by: string; order: 'asc' | 'desc' };
}

async searchOrders(query: SearchOrdersQuery): Promise<PaginatedResult<Order>> {
  // ...
}
```

### 안전한 리팩토링 체크리스트

- [ ] 리팩토링 전후 테스트가 동일하게 통과하는가?
- [ ] 외부에서 관찰 가능한 동작이 변경되지 않았는가?
- [ ] 각 리팩토링 단계가 독립적으로 빌드/테스트 가능한가?
- [ ] 메서드 시그니처 변경 시 모든 호출부가 업데이트되었는가?

## 2. 점진적 개선

### Strangler Fig Pattern

```typescript
// 기존 레거시 코드를 한번에 교체하지 않고, 점진적으로 새 코드로 대체

// Step 1: 기존 코드를 래핑하는 새 인터페이스 도입
interface UserRepository {
  findById(id: string): Promise<User | null>;
  save(user: User): Promise<User>;
}

// Step 2: 레거시 구현체 (기존 코드를 위임)
class LegacyUserRepository implements UserRepository {
  async findById(id: string): Promise<User | null> {
    return this.legacyDb.query(`SELECT * FROM users WHERE id = ?`, [id]); // 레거시 raw 쿼리
  }
  async save(user: User): Promise<User> {
    return this.legacyDb.query(`INSERT INTO users ...`);
  }
}

// Step 3: 새 구현체 (하나씩 교체)
class TypeOrmUserRepository implements UserRepository {
  async findById(id: string): Promise<User | null> {
    return this.repo.findOne({ where: { id } }); // 새 ORM 사용
  }
  async save(user: User): Promise<User> {
    return this.repo.save(user);
  }
}

// Step 4: 기능 플래그로 점진적 전환
class UserRepositoryProxy implements UserRepository {
  constructor(
    private readonly legacy: LegacyUserRepository,
    private readonly modern: TypeOrmUserRepository,
    private readonly featureFlag: FeatureFlagService,
  ) {}

  async findById(id: string): Promise<User | null> {
    if (this.featureFlag.isEnabled('use-typeorm-user-repo')) {
      return this.modern.findById(id);
    }
    return this.legacy.findById(id);
  }
}
```

### Branch by Abstraction

```typescript
// 대규모 리팩토링을 메인 브랜치에서 점진적으로 수행

// Step 1: 추상화 계층 도입 (기존 코드 감싸기)
interface PaymentProcessor {
  process(order: Order): Promise<PaymentResult>;
}

// Step 2: 기존 구현을 추상화 뒤에 배치
class CurrentPaymentProcessor implements PaymentProcessor {
  async process(order: Order): Promise<PaymentResult> {
    // 기존 결제 로직 그대로
    return this.oldPaymentLogic(order);
  }
}

// Step 3: 새 구현 개발 (병렬로, 메인 브랜치에서)
class NewPaymentProcessor implements PaymentProcessor {
  async process(order: Order): Promise<PaymentResult> {
    // 새 결제 로직
    return this.newPaymentLogic(order);
  }
}

// Step 4: 기존 → 새 구현으로 전환 (DI 설정만 변경)
// Step 5: 기존 구현 코드 삭제
```

### 점진적 개선 체크리스트

- [ ] 대규모 변경을 한 PR로 하지 않고 단계별로 나누었는가?
- [ ] 각 단계에서 시스템이 정상 동작하는가? (중간 상태 안전성)
- [ ] 레거시 코드와 새 코드가 일시적으로 공존하는 전략이 있는가?
- [ ] 기능 플래그 또는 추상화로 전환 리스크를 관리하는가?

## 3. 리팩토링과 기능 변경 분리

### 혼재 금지 원칙

```
❌ 하나의 PR에 리팩토링 + 기능 변경
커밋 1: refactor(order): 주문 서비스 메서드 분리
커밋 2: feat(order): 주문 취소 기능 추가
커밋 3: refactor(order): 에러 처리 통일
→ 리뷰어가 "기능 변경으로 인한 차이"와 "리팩토링으로 인한 차이"를 구분할 수 없음
→ 버그 발생 시 원인 추적 어려움

✅ PR을 분리
PR #1: "refactor(order): 주문 서비스 메서드 분리 및 에러 처리 통일"
→ 리뷰: 동작 변경 없이 구조만 개선되었는지 확인
→ 머지

PR #2: "feat(order): 주문 취소 기능 추가"
→ 리뷰: 새 기능 로직만 확인
→ 머지
```

### 분리가 어려운 경우

```
때로는 기능 추가를 위해 리팩토링이 선행되어야 한다.

접근법:
1. 리팩토링 PR을 먼저 머지 (기능 변경 없음)
2. 기능 추가 PR을 이어서 제출

같은 PR에 넣어야 하는 경우 (매우 작은 리팩토링):
- 커밋을 분리: 리팩토링 커밋 → 기능 커밋
- PR 설명에 "리팩토링 범위"를 명시
```

## 4. 리팩토링 리뷰 포인트

### 리뷰어가 확인해야 할 것

```
1. 동작 보존 확인
   - 테스트가 변경 없이 통과하는가?
   - public API(메서드 시그니처, 응답 구조)가 유지되는가?
   - 부수 효과(side effect)가 동일한가?

2. 개선 효과 확인
   - 리팩토링 후 코드가 실제로 더 읽기 쉬워졌는가?
   - 복잡도가 감소했는가? (줄 수만 아니라 인지 복잡도)
   - 향후 변경이 더 쉬워졌는가?

3. 과도한 리팩토링 경계
   - 지금 필요하지 않은 추상화를 미리 만들지 않았는가? (YAGNI)
   - 리팩토링 범위가 PR 목적에 비해 과도하지 않은가?
   - "완벽한 구조"를 추구하다 일정을 초과하지 않았는가?
```

### 리팩토링 시점 판단

```
✅ 리팩토링이 필요한 시점
- 같은 코드를 3번 이상 수정해야 할 때 (Rule of Three)
- 새 기능 추가가 기존 구조 때문에 어려울 때
- 버그가 반복적으로 같은 영역에서 발생할 때
- 코드 리뷰에서 같은 피드백이 반복될 때
- 테스트 작성이 어려울 때 (결합도가 높다는 신호)

❌ 리팩토링을 미뤄야 할 시점
- 릴리즈 직전
- 테스트가 충분하지 않은 코드 (리팩토링 전 테스트부터)
- 곧 폐기될 코드
- 기능 요구사항이 아직 확정되지 않은 코드
```

## 5. 일반적인 리팩토링 패턴

### Dead Code 제거

```typescript
// ❌ 사용되지 않는 코드가 남아있음
class UserService {
  async getUser(id: string): Promise<User> { /* 사용 중 */ }

  // @deprecated — 2024년 1월 제거 예정 (이미 2026년...)
  async getUserLegacy(id: string): Promise<User> { /* 아무도 안 씀 */ }

  // 주석 처리된 코드
  // async getUserByEmail(email: string): Promise<User> {
  //   return this.userRepo.findOne({ where: { email } });
  // }
}

// ✅ 죽은 코드 제거
class UserService {
  async getUser(id: string): Promise<User> { /* 사용 중 */ }
  // 필요하면 git history에서 복원 가능 — 주석 보관 불필요
}
```

### Guard Clause

```typescript
// ❌ 깊은 중첩
async processPayment(order: Order): Promise<PaymentResult> {
  if (order) {
    if (order.status === 'pending') {
      if (order.total > 0) {
        if (order.paymentMethod) {
          return this.chargePayment(order);
        } else {
          throw new BadRequestException('결제 수단 없음');
        }
      } else {
        throw new BadRequestException('금액이 0 이하');
      }
    } else {
      throw new BadRequestException('이미 처리된 주문');
    }
  } else {
    throw new BadRequestException('주문 없음');
  }
}

// ✅ Guard Clause로 조기 반환
async processPayment(order: Order): Promise<PaymentResult> {
  if (!order) throw new BadRequestException('주문 없음');
  if (order.status !== 'pending') throw new BadRequestException('이미 처리된 주문');
  if (order.total <= 0) throw new BadRequestException('금액이 0 이하');
  if (!order.paymentMethod) throw new BadRequestException('결제 수단 없음');

  return this.chargePayment(order);
}
```

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| 동작 변경 | 리팩토링인데 외부 동작이 바뀜 | P0 |
| 혼재 PR | 리팩토링 + 기능 변경 한 PR에 | P1 |
| 테스트 미통과 | 리팩토링 후 기존 테스트 실패 | P0 |
| 과도한 추상화 | YAGNI 위반, 불필요한 복잡도 | P2 |
| Dead Code 잔존 | 사용되지 않는 코드/주석 코드 | P2 |
| 점진적 미적용 | 500줄+ 리팩토링을 한번에 | P1 |
| 깊은 중첩 | Guard Clause로 개선 가능한 중첩 | P2 |
