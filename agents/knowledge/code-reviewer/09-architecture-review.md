# 아키텍처 리뷰

> 참조 링크: https://en.wikipedia.org/wiki/SOLID, https://refactoring.guru/refactoring/smells/couplers

---

## 개요

아키텍처 리뷰는 코드 변경이 시스템의 구조적 건강성을 해치지 않는지 검증한다. 결합도, 응집도, 의존성 방향, 레이어 위반, 단일 책임 원칙(SRP)을 중심으로 판단한다.

## 1. 결합도 (Coupling)

### 느슨한 결합 vs 강한 결합

```typescript
// ❌ 강한 결합: 구현체에 직접 의존
class OrderService {
  private emailSender = new SmtpEmailSender(); // 구현체 직접 생성
  private paymentGateway = new StripePaymentGateway();

  async createOrder(dto: CreateOrderDto): Promise<Order> {
    const order = await this.saveOrder(dto);
    await this.paymentGateway.charge(order.total); // Stripe에 강하게 묶임
    await this.emailSender.send(order.userEmail, 'Order created');
    return order;
  }
}

// ✅ 느슨한 결합: 인터페이스에 의존, DI 활용
interface PaymentGateway {
  charge(amount: number): Promise<PaymentResult>;
}

interface NotificationSender {
  send(to: string, message: string): Promise<void>;
}

class OrderService {
  constructor(
    private readonly paymentGateway: PaymentGateway, // 인터페이스 의존
    private readonly notificationSender: NotificationSender,
  ) {}

  async createOrder(dto: CreateOrderDto): Promise<Order> {
    const order = await this.saveOrder(dto);
    await this.paymentGateway.charge(order.total);
    await this.notificationSender.send(order.userEmail, 'Order created');
    return order;
  }
}
```

### 결합도 리뷰 체크리스트

- [ ] 서비스가 다른 서비스의 구현체를 직접 생성하고 있지 않은가?
- [ ] 외부 라이브러리/SDK가 비즈니스 로직에 직접 침투하지 않았는가?
- [ ] 한 모듈을 변경할 때 연쇄적으로 수정이 필요한 모듈이 3개 이상인가? (위험 신호)
- [ ] 순환 의존(circular dependency)이 존재하지 않는가?

## 2. 응집도 (Cohesion)

### 높은 응집도 vs 낮은 응집도

```typescript
// ❌ 낮은 응집도: 관련 없는 책임이 한 클래스에 몰림
class UserService {
  async createUser(dto: CreateUserDto): Promise<User> { /* ... */ }
  async sendWelcomeEmail(user: User): Promise<void> { /* ... */ }
  async generateReport(startDate: Date): Promise<Report> { /* ... */ }
  async processPayment(userId: string, amount: number): Promise<void> { /* ... */ }
  async resizeAvatar(file: Buffer): Promise<Buffer> { /* ... */ }
}

// ✅ 높은 응집도: 관련 책임만 모아둠
class UserService {
  async createUser(dto: CreateUserDto): Promise<User> { /* ... */ }
  async updateUser(id: string, dto: UpdateUserDto): Promise<User> { /* ... */ }
  async deactivateUser(id: string): Promise<void> { /* ... */ }
  async findUserById(id: string): Promise<User | null> { /* ... */ }
}

class NotificationService {
  async sendWelcomeEmail(user: User): Promise<void> { /* ... */ }
  async sendPasswordResetEmail(user: User, token: string): Promise<void> { /* ... */ }
}
```

### 응집도 판단 기준

- 클래스 내 메서드들이 같은 필드를 공유하는가?
- 클래스 이름에 `And`, `Or`, `Manager`, `Helper`가 포함되어 있으면 의심
- 한 클래스의 import가 5개 이상의 전혀 다른 도메인을 참조하면 분리 검토

## 3. 의존성 방향

### 의존성 규칙 (Dependency Rule)

```
[Controller] → [Service] → [Repository] → [Entity]
    ↓              ↓
  [DTO]       [Interface]
```

```typescript
// ❌ 하위 레이어가 상위 레이어를 참조
// repository/user.repository.ts
import { UserController } from '../controller/user.controller'; // 레이어 역전!

// ❌ Entity가 Service를 알고 있음
class User {
  async save(): Promise<void> {
    await UserService.getInstance().saveUser(this); // Entity가 Service 참조
  }
}

// ✅ 의존성은 항상 안쪽(도메인)을 향한다
// service/user.service.ts
import { UserRepository } from '../repository/user.repository.interface';
import { User } from '../entity/user.entity';

class UserService {
  constructor(private readonly userRepository: UserRepository) {}

  async findById(id: string): Promise<User | null> {
    return this.userRepository.findById(id);
  }
}
```

### 의존성 방향 체크리스트

- [ ] 모든 의존성이 바깥(인프라) → 안쪽(도메인) 방향인가?
- [ ] Entity/Domain 모듈이 framework-specific 코드를 import하지 않는가?
- [ ] Repository 인터페이스가 도메인 레이어에 정의되어 있는가?
- [ ] 패키지 간 양방향 의존이 없는가?

## 4. 레이어 위반

### 전형적인 레이어 위반 패턴

```typescript
// ❌ Controller에서 직접 DB 쿼리
@Controller('users')
class UserController {
  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>, // Controller가 Repository 직접 접근
  ) {}

  @Get(':id')
  async getUser(@Param('id') id: string) {
    return this.userRepo.findOne({ where: { id } }); // 비즈니스 로직 부재
  }
}

// ✅ Controller → Service → Repository 계층 유지
@Controller('users')
class UserController {
  constructor(private readonly userService: UserService) {}

  @Get(':id')
  async getUser(@Param('id') id: string) {
    return this.userService.findById(id);
  }
}

// ❌ Service에서 HTTP Request/Response 객체 접근
class UserService {
  async createUser(req: Request, res: Response): Promise<void> { // HTTP 레이어 침투
    const user = await this.save(req.body);
    res.status(201).json(user);
  }
}

// ✅ Service는 순수 비즈니스 로직만
class UserService {
  async createUser(dto: CreateUserDto): Promise<User> {
    return this.userRepository.save(this.toEntity(dto));
  }
}
```

### 레이어 위반 리뷰 체크리스트

- [ ] Controller에서 Repository를 직접 주입받고 있지 않은가?
- [ ] Service에서 Request, Response, Session 등 HTTP 객체를 사용하지 않는가?
- [ ] Repository에서 비즈니스 규칙을 검증하고 있지 않은가?
- [ ] Entity에 프레젠테이션 로직(직렬화 포맷 등)이 포함되어 있지 않은가?

## 5. 단일 책임 원칙 (SRP)

### SRP 위반 식별

```typescript
// ❌ SRP 위반: 하나의 클래스가 여러 이유로 변경됨
class InvoiceService {
  async createInvoice(order: Order): Promise<Invoice> { /* 비즈니스 로직 */ }
  async calculateTax(invoice: Invoice): Promise<number> { /* 세금 계산 */ }
  async generatePdf(invoice: Invoice): Promise<Buffer> { /* PDF 생성 */ }
  async sendEmail(invoice: Invoice): Promise<void> { /* 이메일 전송 */ }
  async saveToS3(pdf: Buffer, key: string): Promise<string> { /* S3 업로드 */ }
}

// ✅ 책임별 분리
class InvoiceService {
  constructor(
    private readonly taxCalculator: TaxCalculator,
    private readonly pdfGenerator: PdfGenerator,
    private readonly notifier: InvoiceNotifier,
  ) {}

  async createInvoice(order: Order): Promise<Invoice> {
    const tax = await this.taxCalculator.calculate(order);
    const invoice = Invoice.create(order, tax);
    return this.invoiceRepository.save(invoice);
  }
}

class InvoiceNotifier {
  constructor(
    private readonly pdfGenerator: PdfGenerator,
    private readonly emailSender: EmailSender,
  ) {}

  async notifyCreated(invoice: Invoice): Promise<void> {
    const pdf = await this.pdfGenerator.generate(invoice);
    await this.emailSender.send(invoice.customerEmail, pdf);
  }
}
```

### SRP 판단 신호

- "이 클래스는 ~하고, ~하고, ~도 한다" — `and`가 2개 이상이면 분리 검토
- 메서드 수가 10개 이상이면 역할 분리 가능성 검토
- 생성자 파라미터가 5개 이상이면 의존성 과다 의심

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| 순환 의존 | 모듈 간 양방향 import 없는가 | P0 |
| 레이어 위반 | Controller↔Repository 직접 연결 | P1 |
| 의존성 역전 | 도메인이 인프라에 의존하는가 | P1 |
| God Class | 10개 이상 메서드, 300줄 이상 | P2 |
| SRP 위반 | 변경 이유가 2개 이상인 클래스 | P2 |
| 강한 결합 | 구현체 직접 생성 | P2 |
| 응집도 부족 | 무관한 책임이 한 곳에 | P2 |
