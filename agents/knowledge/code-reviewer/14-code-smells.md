# 코드 스멜

> 참조 링크: https://refactoring.guru/refactoring/smells, https://sourcemaking.com/refactoring/smells

---

## 개요

코드 스멜은 직접적인 버그는 아니지만 깊은 문제를 암시하는 코드 패턴이다. 리뷰 시 코드 스멜을 식별하면 기술 부채가 쌓이기 전에 대응할 수 있다.

## 1. God Class

### 징후

- 클래스가 300줄 이상
- 메서드 10개 이상
- 의존성(생성자 파라미터) 7개 이상
- 클래스 이름에 `Manager`, `Handler`, `Processor`, `Helper` 포함

```typescript
// ❌ God Class: 모든 것을 아는 클래스
class OrderManager {
  constructor(
    private readonly orderRepo: OrderRepository,
    private readonly userRepo: UserRepository,
    private readonly productRepo: ProductRepository,
    private readonly paymentGateway: PaymentGateway,
    private readonly emailService: EmailService,
    private readonly smsService: SmsService,
    private readonly inventoryService: InventoryService,
    private readonly analyticsService: AnalyticsService,
    private readonly couponService: CouponService,
    private readonly shippingService: ShippingService,
  ) {}

  async createOrder() { /* ... */ }
  async cancelOrder() { /* ... */ }
  async processPayment() { /* ... */ }
  async sendConfirmationEmail() { /* ... */ }
  async updateInventory() { /* ... */ }
  async calculateShipping() { /* ... */ }
  async applyCoupon() { /* ... */ }
  async generateInvoice() { /* ... */ }
  async trackAnalytics() { /* ... */ }
  async notifyUser() { /* ... */ }
  async handleRefund() { /* ... */ }
}

// ✅ 책임 분리
class OrderService {
  constructor(
    private readonly orderRepo: OrderRepository,
    private readonly paymentService: PaymentService,
    private readonly fulfillmentService: FulfillmentService,
  ) {}

  async createOrder(dto: CreateOrderDto): Promise<Order> {
    const order = Order.create(dto);
    await this.orderRepo.save(order);
    await this.paymentService.processPayment(order);
    await this.fulfillmentService.initiate(order);
    return order;
  }
}

class PaymentService {
  constructor(
    private readonly paymentGateway: PaymentGateway,
    private readonly couponService: CouponService,
  ) {}

  async processPayment(order: Order): Promise<PaymentResult> { /* ... */ }
  async handleRefund(order: Order): Promise<RefundResult> { /* ... */ }
}
```

### God Class 리뷰 체크리스트

- [ ] 생성자 의존성이 5개를 넘는가? → 분리 검토
- [ ] 클래스 내 메서드 그룹이 서로 다른 필드를 사용하는가? → 분리 대상
- [ ] 클래스 이름을 한 단어로 설명할 수 없는가?

## 2. Feature Envy

### 징후

한 클래스의 메서드가 자기 데이터보다 다른 클래스의 데이터를 더 많이 접근한다.

```typescript
// ❌ Feature Envy: OrderService가 User의 내부를 너무 많이 알고 있음
class OrderService {
  calculateDiscount(order: Order, user: User): number {
    let discount = 0;

    if (user.membership === 'gold') discount += 10;          // user 내부 접근
    if (user.orderCount > 50) discount += 5;                 // user 내부 접근
    if (user.registeredAt < oneYearAgo) discount += 3;       // user 내부 접근
    if (user.totalSpent > 1000000) discount += 7;            // user 내부 접근

    return Math.min(discount, 25);
  }
}

// ✅ 로직을 데이터가 있는 곳으로 이동
class User {
  getDiscountRate(): number {
    let discount = 0;

    if (this.membership === 'gold') discount += 10;
    if (this.orderCount > 50) discount += 5;
    if (this.registeredAt < oneYearAgo) discount += 3;
    if (this.totalSpent > 1000000) discount += 7;

    return Math.min(discount, 25);
  }
}

class OrderService {
  calculateDiscount(order: Order, user: User): number {
    return user.getDiscountRate(); // User에게 위임
  }
}
```

### Feature Envy 체크리스트

- [ ] 메서드가 파라미터 객체의 프로퍼티를 3개 이상 직접 접근하는가?
- [ ] 해당 로직을 데이터 소유 클래스로 옮길 수 있는가?
- [ ] getter 체인(`a.b.c.d`)이 2단계를 넘는가? (Law of Demeter 위반)

## 3. Shotgun Surgery

### 징후

하나의 기능 변경을 위해 여러 파일/클래스를 수정해야 한다.

```typescript
// ❌ 새 사용자 역할 추가 시 수정이 필요한 곳이 산재
// 1. user.entity.ts
type Role = 'admin' | 'user' | 'editor'; // 여기에 추가

// 2. auth.guard.ts
if (role === 'admin' || role === 'editor') { /* ... */ } // 여기도 수정

// 3. user.service.ts
getPermissions(role: string) {
  if (role === 'admin') return ALL_PERMISSIONS;
  if (role === 'editor') return EDITOR_PERMISSIONS; // 여기도 추가
}

// 4. user.controller.ts
@Roles('admin', 'editor') // 여기도 변경

// 5. admin.template.ts
const menuItems = role === 'admin' ? adminMenu : role === 'editor' ? editorMenu : userMenu;

// ✅ 역할 관련 로직을 한 곳에 집중
interface RoleDefinition {
  name: string;
  permissions: Permission[];
  menuItems: MenuItem[];
}

class RoleRegistry {
  private readonly roles = new Map<string, RoleDefinition>();

  register(role: RoleDefinition): void {
    this.roles.set(role.name, role);
  }

  getPermissions(roleName: string): Permission[] {
    return this.roles.get(roleName)?.permissions ?? [];
  }

  getMenuItems(roleName: string): MenuItem[] {
    return this.roles.get(roleName)?.menuItems ?? [];
  }

  hasPermission(roleName: string, permission: Permission): boolean {
    return this.getPermissions(roleName).includes(permission);
  }
}
```

### Shotgun Surgery 체크리스트

- [ ] 하나의 기능 변경에 3개 이상 파일 수정이 필요한가?
- [ ] 같은 조건문(if/switch)이 여러 파일에 반복되는가?
- [ ] 관련 로직을 한 곳에 모을 수 있는가?

## 4. Long Method

### 징후

- 메서드가 30줄 이상
- 주석으로 섹션을 나누고 있음
- 들여쓰기가 3단계 이상

```typescript
// ❌ Long Method
async processOrder(dto: CreateOrderDto): Promise<OrderResult> {
  // 사용자 검증
  const user = await this.userRepo.findOne({ where: { id: dto.userId } });
  if (!user) throw new NotFoundException('User not found');
  if (user.status === 'suspended') throw new ForbiddenException('Suspended user');
  if (!user.emailVerified) throw new ForbiddenException('Email not verified');

  // 상품 검증
  const items = [];
  for (const item of dto.items) {
    const product = await this.productRepo.findOne({ where: { id: item.productId } });
    if (!product) throw new NotFoundException(`Product ${item.productId} not found`);
    if (product.stock < item.quantity) throw new BadRequestException('Insufficient stock');
    items.push({ product, quantity: item.quantity });
  }

  // 가격 계산
  let total = 0;
  for (const item of items) {
    let price = item.product.price * item.quantity;
    if (item.product.category === 'electronics' && item.quantity >= 3) {
      price *= 0.9;
    }
    total += price;
  }

  // 쿠폰 적용
  if (dto.couponCode) {
    const coupon = await this.couponRepo.findOne({ where: { code: dto.couponCode } });
    if (coupon && coupon.expiresAt > new Date()) {
      total -= coupon.discountAmount;
    }
  }

  // 주문 생성 + 결제 + 재고 차감 + 알림... (계속)
  // ... 50줄 더
}

// ✅ 의미 단위로 메서드 추출
async processOrder(dto: CreateOrderDto): Promise<OrderResult> {
  const user = await this.validateUser(dto.userId);
  const items = await this.validateAndResolveItems(dto.items);
  const total = this.calculateTotal(items);
  const finalTotal = await this.applyCoupon(total, dto.couponCode);
  const order = await this.createOrder(user, items, finalTotal);
  await this.fulfillOrder(order);
  return OrderResult.from(order);
}

private async validateUser(userId: string): Promise<User> {
  const user = await this.userRepo.findOne({ where: { id: userId } });
  if (!user) throw new NotFoundException('User not found');
  if (user.status === 'suspended') throw new ForbiddenException('Suspended user');
  if (!user.emailVerified) throw new ForbiddenException('Email not verified');
  return user;
}
```

### Long Method 체크리스트

- [ ] 메서드가 30줄을 넘는가?
- [ ] 주석으로 "단계"를 구분하고 있는가? → 메서드 추출 신호
- [ ] 들여쓰기가 3단계 이상인 부분이 있는가?
- [ ] 메서드 이름만으로 동작을 설명할 수 있는가?

## 5. 기타 코드 스멜

### Primitive Obsession

```typescript
// ❌ 원시 타입 남용
function createUser(name: string, email: string, phone: string, age: number): User { /* ... */ }
const price = 10000; // 원? 달러?

// ✅ 값 객체 사용
function createUser(dto: CreateUserDto): User { /* ... */ }

class Money {
  constructor(
    readonly amount: number,
    readonly currency: 'KRW' | 'USD',
  ) {}
}
```

### Data Clumps

```typescript
// ❌ 같은 파라미터 그룹이 반복
function calculateShipping(street: string, city: string, zipCode: string, country: string) { /* ... */ }
function validateAddress(street: string, city: string, zipCode: string, country: string) { /* ... */ }

// ✅ 객체로 묶기
interface Address {
  street: string;
  city: string;
  zipCode: string;
  country: string;
}

function calculateShipping(address: Address) { /* ... */ }
function validateAddress(address: Address) { /* ... */ }
```

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| God Class | 의존성 7+, 메서드 10+, 300줄+ | P2 |
| Feature Envy | 다른 객체 프로퍼티 3+ 직접 접근 | P2 |
| Shotgun Surgery | 기능 하나에 파일 3+ 수정 | P2 |
| Long Method | 메서드 30줄+ | P2 |
| Primitive Obsession | 관련 원시값이 반복 전달 | P3 |
| Data Clumps | 같은 파라미터 그룹 반복 | P3 |
| 깊은 중첩 | 들여쓰기 3단계 이상 | P2 |
