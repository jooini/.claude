# 테스트 코드 리뷰

> 참조 링크: https://jestjs.io/docs/getting-started, https://testing-library.com/docs/guiding-principles

---

## 개요

테스트 코드의 품질은 프로덕션 코드의 신뢰성을 결정한다. 커버리지, 엣지 케이스, 독립성, Happy Path 편향, mock 적절성 등 테스트 코드 리뷰의 핵심 관점을 다룬다.

## 1. 테스트 커버리지

### 의미 있는 커버리지

```typescript
// ❌ 라인 커버리지만 높이는 무의미한 테스트
it('should create user', async () => {
  const result = await service.createUser(validDto);
  expect(result).toBeDefined(); // 존재 여부만 확인 — 내용 검증 없음
});

// ❌ 구현 세부사항만 테스트
it('should call repository', async () => {
  await service.createUser(validDto);
  expect(mockRepo.save).toHaveBeenCalled(); // 동작이 아닌 구현을 테스트
});

// ✅ 행동과 결과를 검증
it('should create user with hashed password', async () => {
  const dto = { email: 'test@test.com', password: 'plain123', name: 'Test' };
  const result = await service.createUser(dto);

  expect(result.id).toBeDefined();
  expect(result.email).toBe(dto.email);
  expect(result.name).toBe(dto.name);
  expect(result.password).not.toBe(dto.password); // 비밀번호 해싱 확인
});
```

### 커버리지가 빠지기 쉬운 곳

```typescript
// 리뷰 시 확인해야 할 커버리지 사각지대
// 1. catch 블록 내부 로직
// 2. if-else의 else 분기
// 3. switch-case의 default
// 4. early return 조건
// 5. 콜백 함수 내부
// 6. 삼항 연산자의 falsy 분기

// ❌ happy path만 테스트
describe('OrderService', () => {
  it('should create order', async () => { /* ... */ });
  it('should get order by id', async () => { /* ... */ });
  // 실패 경로 테스트 없음
});

// ✅ 실패 경로도 포함
describe('OrderService', () => {
  it('should create order successfully', async () => { /* ... */ });
  it('should throw when product is out of stock', async () => { /* ... */ });
  it('should throw when user has no payment method', async () => { /* ... */ });
  it('should get order by id', async () => { /* ... */ });
  it('should throw NotFoundException for non-existent order', async () => { /* ... */ });
  it('should throw ForbiddenException when accessing others order', async () => { /* ... */ });
});
```

## 2. 엣지 케이스

### 경계값 테스트

```typescript
// ✅ 경계값 테스트 패턴
describe('calculateDiscount', () => {
  // 정상 범위
  it('should apply 10% discount', () => {
    expect(calculateDiscount(1000, 10)).toBe(100);
  });

  // 경계값
  it('should handle 0% discount', () => {
    expect(calculateDiscount(1000, 0)).toBe(0);
  });

  it('should handle 100% discount', () => {
    expect(calculateDiscount(1000, 100)).toBe(1000);
  });

  // 엣지 케이스
  it('should handle 0 price', () => {
    expect(calculateDiscount(0, 50)).toBe(0);
  });

  it('should reject negative price', () => {
    expect(() => calculateDiscount(-100, 10)).toThrow();
  });

  it('should clamp discount over 100', () => {
    expect(calculateDiscount(1000, 150)).toBe(1000); // 최대 100%
  });

  it('should handle very large numbers', () => {
    expect(calculateDiscount(Number.MAX_SAFE_INTEGER, 1)).toBeDefined();
  });
});
```

### 빈 입력 테스트

```typescript
// ✅ 빈 입력, null, undefined 케이스
describe('searchUsers', () => {
  it('should return empty array for empty search term', async () => {
    const result = await searchUsers('');
    expect(result).toEqual([]);
  });

  it('should return empty array when no users match', async () => {
    const result = await searchUsers('zzzznonexistent');
    expect(result).toEqual([]);
  });

  it('should handle special characters in search', async () => {
    const result = await searchUsers("'; DROP TABLE users; --");
    expect(result).toEqual([]); // SQL injection 방어 확인
  });

  it('should trim whitespace from search term', async () => {
    const result = await searchUsers('  Alice  ');
    expect(result).toHaveLength(1);
  });
});
```

## 3. 테스트 독립성

### 공유 상태 문제

```typescript
// ❌ 테스트 간 상태 공유
let testUser: User;

describe('UserService', () => {
  it('should create user', async () => {
    testUser = await service.createUser(dto); // 다음 테스트에서 사용
    expect(testUser).toBeDefined();
  });

  it('should update user', async () => {
    // testUser에 의존 — 위 테스트가 실패하면 이것도 실패
    const result = await service.updateUser(testUser.id, { name: 'Updated' });
    expect(result.name).toBe('Updated');
  });
});

// ✅ 각 테스트가 독립적
describe('UserService', () => {
  let testUser: User;

  beforeEach(async () => {
    testUser = await factory.createUser(); // 매 테스트마다 새 데이터
  });

  afterEach(async () => {
    await cleanupDatabase(); // 테스트 후 정리
  });

  it('should update user name', async () => {
    const result = await service.updateUser(testUser.id, { name: 'Updated' });
    expect(result.name).toBe('Updated');
  });

  it('should update user email', async () => {
    const result = await service.updateUser(testUser.id, { email: 'new@test.com' });
    expect(result.email).toBe('new@test.com');
  });
});
```

### 테스트 실행 순서 의존

```typescript
// ❌ 테스트 실행 순서에 의존
describe('Counter', () => {
  const counter = new Counter();

  it('should start at 0', () => {
    expect(counter.value).toBe(0);
  });

  it('should increment to 1', () => {
    counter.increment();
    expect(counter.value).toBe(1); // 위 테스트가 먼저 실행되어야 함
  });

  it('should increment to 2', () => {
    counter.increment();
    expect(counter.value).toBe(2); // 순서 의존
  });
});

// ✅ 각 테스트가 자체 인스턴스 사용
describe('Counter', () => {
  it('should start at 0', () => {
    const counter = new Counter();
    expect(counter.value).toBe(0);
  });

  it('should increment by 1', () => {
    const counter = new Counter();
    counter.increment();
    expect(counter.value).toBe(1);
  });

  it('should increment multiple times', () => {
    const counter = new Counter();
    counter.increment();
    counter.increment();
    expect(counter.value).toBe(2);
  });
});
```

## 4. Happy Path 편향

```typescript
// ❌ 성공 케이스만 테스트
describe('TransferService', () => {
  it('should transfer money between accounts', async () => {
    const result = await service.transfer('acc1', 'acc2', 100);
    expect(result.success).toBe(true);
  });
});

// ✅ 실패/엣지 케이스 충분히 테스트
describe('TransferService', () => {
  // 성공 케이스
  it('should transfer money and update both balances', async () => {
    const result = await service.transfer('acc1', 'acc2', 100);
    expect(result.success).toBe(true);
    expect(result.fromBalance).toBe(900); // 1000 - 100
    expect(result.toBalance).toBe(1100);  // 1000 + 100
  });

  // 실패 케이스
  it('should reject transfer with insufficient balance', async () => {
    await expect(service.transfer('acc1', 'acc2', 99999))
      .rejects.toThrow(InsufficientBalanceError);
  });

  it('should reject transfer to same account', async () => {
    await expect(service.transfer('acc1', 'acc1', 100))
      .rejects.toThrow('Cannot transfer to the same account');
  });

  it('should reject zero amount', async () => {
    await expect(service.transfer('acc1', 'acc2', 0))
      .rejects.toThrow('Amount must be positive');
  });

  it('should reject negative amount', async () => {
    await expect(service.transfer('acc1', 'acc2', -100))
      .rejects.toThrow('Amount must be positive');
  });

  it('should throw when source account not found', async () => {
    await expect(service.transfer('nonexistent', 'acc2', 100))
      .rejects.toThrow(NotFoundException);
  });

  // 동시성 케이스
  it('should handle concurrent transfers correctly', async () => {
    // 잔액 1000인 계좌에서 동시에 600씩 이체
    const [result1, result2] = await Promise.allSettled([
      service.transfer('acc1', 'acc2', 600),
      service.transfer('acc1', 'acc3', 600),
    ]);

    // 하나만 성공해야 함
    const successes = [result1, result2].filter(r => r.status === 'fulfilled');
    expect(successes).toHaveLength(1);
  });
});
```

## 5. Mock 적절성

### 과도한 Mocking

```typescript
// ❌ 테스트 대상까지 mock — 실제로 아무것도 테스트 안 함
it('should process order', async () => {
  jest.spyOn(service, 'processOrder').mockResolvedValue(mockOrder);
  const result = await service.processOrder(dto);
  expect(result).toEqual(mockOrder); // 자기 자신을 mock한 것 — 무의미
});

// ❌ 너무 많은 mock — 테스트 신뢰도 저하
it('should create order', async () => {
  mockProductService.findById.mockResolvedValue(mockProduct);
  mockInventoryService.check.mockResolvedValue(true);
  mockPricingService.calculate.mockResolvedValue(1000);
  mockPaymentService.charge.mockResolvedValue({ success: true });
  mockNotificationService.send.mockResolvedValue(undefined);
  mockAuditService.log.mockResolvedValue(undefined);
  // 6개 mock — 실제 통합이 제대로 되는지 알 수 없음

  const result = await service.createOrder(dto);
  expect(result).toBeDefined();
});

// ✅ 외부 의존성만 mock
it('should create order with correct total', async () => {
  // 외부 서비스만 mock
  mockPaymentGateway.charge.mockResolvedValue({ transactionId: 'tx-123' });

  // 내부 서비스는 실제 로직 사용
  const result = await service.createOrder({
    userId: testUser.id,
    items: [{ productId: testProduct.id, quantity: 2 }],
  });

  expect(result.total).toBe(testProduct.price * 2);
  expect(result.paymentTransactionId).toBe('tx-123');
});
```

### Mock 반환값 현실성

```typescript
// ❌ 비현실적인 mock 반환값
mockRepo.findOne.mockResolvedValue({
  id: '1',
  name: 'test',
}); // 실제 엔티티와 구조가 다름 — createdAt, updatedAt 등 누락

// ✅ 현실적인 mock 데이터
const mockUser: User = {
  id: 'uuid-123',
  name: 'Test User',
  email: 'test@example.com',
  role: 'user',
  isActive: true,
  createdAt: new Date('2024-01-01'),
  updatedAt: new Date('2024-01-01'),
};
mockRepo.findOne.mockResolvedValue(mockUser);
```

## 6. 테스트 이름과 구조

```typescript
// ❌ 모호한 테스트 이름
it('should work', async () => { /* ... */ });
it('test1', async () => { /* ... */ });
it('handles edge case', async () => { /* ... */ }); // 어떤 엣지 케이스?

// ✅ 행동을 설명하는 이름
it('should return 404 when user does not exist', async () => { /* ... */ });
it('should hash password before saving to database', async () => { /* ... */ });
it('should reject email without @ symbol', async () => { /* ... */ });

// ✅ Arrange-Act-Assert 패턴
it('should calculate total with tax', () => {
  // Arrange
  const items = [
    { price: 1000, quantity: 2 },
    { price: 500, quantity: 1 },
  ];
  const taxRate = 0.1;

  // Act
  const total = calculateTotal(items, taxRate);

  // Assert
  expect(total).toBe(2750); // (1000*2 + 500*1) * 1.1
});
```

## 7. 테스트 코드 리뷰 체크리스트

- [ ] 변경된 로직에 대한 테스트가 추가/수정되었는가?
- [ ] Happy path와 실패 경로 모두 테스트하는가?
- [ ] 경계값과 엣지 케이스를 테스트하는가?
- [ ] 각 테스트가 독립적으로 실행 가능한가?
- [ ] 테스트 이름이 검증하는 행동을 명확히 설명하는가?
- [ ] Mock이 외부 의존성에만 사용되는가?
- [ ] Mock 반환값이 현실적인가?
- [ ] Arrange-Act-Assert 패턴을 따르는가?
- [ ] 구현 세부사항이 아닌 행동을 테스트하는가?
- [ ] 비동기 에러를 올바르게 검증하는가? (rejects.toThrow)
