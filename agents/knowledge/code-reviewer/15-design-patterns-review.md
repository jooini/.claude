# 디자인 패턴 적용 리뷰

> 참조 링크: https://refactoring.guru/design-patterns, https://en.wikipedia.org/wiki/SOLID

---

## 개요

디자인 패턴은 올바르게 적용하면 코드 품질을 높이지만, 오용하거나 과용하면 오히려 복잡도만 증가시킨다. 리뷰어는 패턴의 적절성을 판단하고, SOLID 원칙 위반을 식별해야 한다.

## 1. 패턴 오용 (Misuse)

### Strategy 패턴 오용

```typescript
// ❌ 단순 if-else면 충분한 곳에 Strategy 패턴 적용
interface GreetingStrategy {
  greet(name: string): string;
}

class MorningGreeting implements GreetingStrategy {
  greet(name: string): string { return `좋은 아침이에요, ${name}!`; }
}

class EveningGreeting implements GreetingStrategy {
  greet(name: string): string { return `좋은 저녁이에요, ${name}!`; }
}

class GreetingContext {
  constructor(private strategy: GreetingStrategy) {}
  executeGreeting(name: string): string { return this.strategy.greet(name); }
}

// ✅ 단순한 경우 그냥 함수로
function greet(name: string, timeOfDay: 'morning' | 'evening'): string {
  return timeOfDay === 'morning'
    ? `좋은 아침이에요, ${name}!`
    : `좋은 저녁이에요, ${name}!`;
}
```

### Strategy 패턴이 적합한 경우

```typescript
// ✅ 결제 방식처럼 런타임에 동적으로 바뀌고, 확장 가능성이 높은 경우
interface PaymentStrategy {
  pay(amount: number): Promise<PaymentResult>;
  validate(data: PaymentData): ValidationResult;
  refund(transactionId: string): Promise<RefundResult>;
}

class CreditCardPayment implements PaymentStrategy {
  async pay(amount: number): Promise<PaymentResult> { /* 카드 결제 로직 */ }
  validate(data: PaymentData): ValidationResult { /* 카드 번호 유효성 */ }
  async refund(transactionId: string): Promise<RefundResult> { /* 카드 취소 */ }
}

class BankTransferPayment implements PaymentStrategy {
  async pay(amount: number): Promise<PaymentResult> { /* 계좌이체 로직 */ }
  validate(data: PaymentData): ValidationResult { /* 계좌 유효성 */ }
  async refund(transactionId: string): Promise<RefundResult> { /* 환불 처리 */ }
}
```

### 패턴 오용 신호

- 패턴 적용 후 코드가 더 길어지고 읽기 어려워졌다
- 클래스/인터페이스 수가 불필요하게 증가했다
- 구현체가 1개뿐인 인터페이스가 있다 (테스트 mock용 제외)
- 패턴 이름을 클래스명에 그대로 쓴다 (`UserFactoryFactory`)

## 2. 패턴 과용 (Overuse)

### 불필요한 추상화 계층

```typescript
// ❌ 추상화 과다: 단순 CRUD에 5개 레이어
interface IUserRepository { findById(id: string): Promise<User>; }
class UserRepository implements IUserRepository { /* TypeORM 쿼리 */ }
interface IUserService { getUser(id: string): Promise<UserDto>; }
class UserService implements IUserService { /* repository 호출 */ }
class UserFacade { /* service 호출 */ }
class UserController { /* facade 호출 */ }
class UserPresenter { /* response 변환 */ }

// ✅ 적절한 추상화: 복잡도에 맞는 레이어
class UserController {
  constructor(private readonly userService: UserService) {}

  @Get(':id')
  async getUser(@Param('id') id: string): Promise<UserResponseDto> {
    return this.userService.findById(id);
  }
}

class UserService {
  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
  ) {}

  async findById(id: string): Promise<UserResponseDto> {
    const user = await this.userRepo.findOneOrFail({ where: { id } });
    return UserResponseDto.from(user);
  }
}
```

### 과용 판단 기준

```
"이 추상화를 제거하면 무엇이 더 어려워지는가?"
→ 대답이 "아무것도" 라면 과용이다.

"이 인터페이스의 구현체가 2개 이상 존재하거나 존재할 예정인가?"
→ "아니오" 라면 인터페이스가 불필요할 수 있다.

"이 패턴 없이 같은 요구사항을 충족할 수 있는가?"
→ "예" 라면 패턴이 과하다.
```

### 과용 체크리스트

- [ ] 구현체가 1개뿐인 인터페이스가 있는가? (테스트 mock 제외)
- [ ] 단순히 위임만 하는 래퍼 클래스가 있는가?
- [ ] 추상화 레이어가 3개를 넘는가?
- [ ] 패턴 적용 전보다 코드 줄 수가 2배 이상 늘었는가?

## 3. SOLID 위반 식별

### Single Responsibility Principle (SRP) 위반

```typescript
// ❌ 여러 이유로 변경되는 클래스
class UserService {
  async createUser(dto: CreateUserDto): Promise<User> { /* 비즈니스 로직 */ }
  async exportToCSV(users: User[]): Promise<Buffer> { /* 데이터 포맷 */ }
  async sendNewsletter(users: User[]): Promise<void> { /* 메일 발송 */ }
}

// ✅ 변경 이유별 분리
class UserService { async createUser(dto: CreateUserDto): Promise<User> { /* ... */ } }
class UserExporter { async toCSV(users: User[]): Promise<Buffer> { /* ... */ } }
class NewsletterService { async send(users: User[]): Promise<void> { /* ... */ } }
```

### Open/Closed Principle (OCP) 위반

```typescript
// ❌ 새 할인 타입 추가 시 기존 코드 수정 필요
class DiscountCalculator {
  calculate(type: string, amount: number): number {
    switch (type) {
      case 'percentage': return amount * 0.1;
      case 'fixed': return 100;
      case 'vip': return amount * 0.2; // 새 타입마다 여기 수정
      default: return 0;
    }
  }
}

// ✅ 확장에 열려 있고 수정에 닫힘
interface DiscountPolicy {
  calculate(amount: number): number;
}

class PercentageDiscount implements DiscountPolicy {
  constructor(private readonly rate: number) {}
  calculate(amount: number): number { return amount * this.rate; }
}

class FixedDiscount implements DiscountPolicy {
  constructor(private readonly fixedAmount: number) {}
  calculate(amount: number): number { return this.fixedAmount; }
}

// 새 할인 정책 추가: 기존 코드 수정 없이 클래스만 추가
class BuyOneGetOneDiscount implements DiscountPolicy {
  calculate(amount: number): number { return amount * 0.5; }
}
```

### Liskov Substitution Principle (LSP) 위반

```typescript
// ❌ 자식이 부모의 계약을 깨뜨림
class Bird {
  fly(): void { console.log('Flying'); }
}

class Penguin extends Bird {
  fly(): void { throw new Error('Penguins cannot fly'); } // 부모 계약 위반
}

// ✅ 인터페이스 분리로 해결
interface Walkable { walk(): void; }
interface Flyable { fly(): void; }

class Sparrow implements Walkable, Flyable {
  walk(): void { /* ... */ }
  fly(): void { /* ... */ }
}

class Penguin implements Walkable {
  walk(): void { /* ... */ }
  // fly() 없음 — 정직한 설계
}
```

### Interface Segregation Principle (ISP) 위반

```typescript
// ❌ 뚱뚱한 인터페이스
interface UserRepository {
  findById(id: string): Promise<User>;
  findAll(): Promise<User[]>;
  save(user: User): Promise<User>;
  delete(id: string): Promise<void>;
  generateReport(): Promise<Report>;    // 리포지토리에 리포트?
  sendNotification(): Promise<void>;    // 리포지토리에 알림?
}

// ✅ 역할별 인터페이스 분리
interface UserReader {
  findById(id: string): Promise<User>;
  findAll(): Promise<User[]>;
}

interface UserWriter {
  save(user: User): Promise<User>;
  delete(id: string): Promise<void>;
}
```

### Dependency Inversion Principle (DIP) 위반

```typescript
// ❌ 고수준 모듈이 저수준 모듈에 직접 의존
import { TypeOrmUserRepository } from './typeorm-user.repository';

class UserService {
  private repo = new TypeOrmUserRepository(); // 구현체 직접 의존
}

// ✅ 추상에 의존
class UserService {
  constructor(
    @Inject('USER_REPOSITORY')
    private readonly repo: UserRepository, // 인터페이스 의존
  ) {}
}
```

## 4. 패턴 적용 적절성 판단

### 판단 매트릭스

| 상황 | 패턴 필요 여부 | 이유 |
|------|--------------|------|
| CRUD API (단순) | 불필요 | 패턴 없이도 충분히 명확 |
| 결제 수단 3종+ | Strategy | 런타임 교체, 확장 빈번 |
| 알림 채널 (이메일/SMS/푸시) | Observer/Strategy | 독립적 확장 |
| DB 접근 추상화 | Repository | 테스트, DB 교체 가능성 |
| 복잡한 객체 생성 | Builder/Factory | 생성자 파라미터 과다 |
| 설정값 전역 접근 | Module/DI | Singleton보다 DI 선호 |

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| LSP 위반 | 상속 시 부모 계약 파괴 | P1 |
| DIP 위반 | 비즈니스 로직이 구현체에 직접 의존 | P1 |
| 불필요한 추상화 | 구현체 1개인 인터페이스 남발 | P2 |
| SRP 위반 | 변경 이유 2개 이상인 클래스 | P2 |
| OCP 위반 | 새 기능마다 기존 코드 switch 수정 | P2 |
| ISP 위반 | 사용하지 않는 메서드 포함 인터페이스 | P2 |
| 패턴 과용 | 단순 로직에 과도한 추상화 | P3 |
