# Unit Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/unit-testing

---

## 1. 단위 테스트 원칙

**FIRST 원칙:**
- **F**ast: 빠르게 실행 (ms 단위)
- **I**solated: 외부 의존성 없이 독립적
- **R**epeatable: 항상 같은 결과
- **S**elf-validating: 사람이 개입 없이 Pass/Fail 판단
- **T**imely: 코드 작성과 함께 (TDD) 또는 직후

---

## 2. 좋은 단위 테스트 구조 (AAA)

```ts
describe('OrderService.calculateTotal', () => {
  it('수량 × 가격으로 합계 계산', () => {
    // Arrange — 준비
    const items = [
      { price: 10000, quantity: 2 },
      { price: 5000,  quantity: 3 },
    ]

    // Act — 실행
    const total = calculateTotal(items)

    // Assert — 검증
    expect(total).toBe(35000)
  })
})
```

---

## 3. Mocking 전략

```ts
// Jest Mock 기본
// 모듈 전체 Mock
jest.mock('@/services/email.service')
jest.mock('@/repositories/user.repository')

// 함수 단위 Mock
const mockFindUser = jest.fn()
const mockSendEmail = jest.fn()

// 반환값 설정
mockFindUser.mockResolvedValue({ id: '1', email: 'test@test.com', name: '홍길동' })
mockSendEmail.mockResolvedValue({ messageId: 'msg-123' })

// 에러 Mock
mockFindUser.mockRejectedValue(new Error('DB connection failed'))

// 호출 검증
expect(mockSendEmail).toHaveBeenCalledWith('test@test.com', '환영합니다')
expect(mockSendEmail).toHaveBeenCalledTimes(1)
expect(mockFindUser).not.toHaveBeenCalled()
```

---

## 4. 비즈니스 로직 단위 테스트

```ts
// 할인 계산 로직
describe('DiscountCalculator', () => {
  let calculator: DiscountCalculator

  beforeEach(() => {
    calculator = new DiscountCalculator()
  })

  describe('calculateDiscount', () => {
    // 정상 케이스
    it('VIP 등급은 20% 할인', () => {
      expect(calculator.calculateDiscount(100000, 'VIP')).toBe(80000)
    })

    it('일반 등급은 할인 없음', () => {
      expect(calculator.calculateDiscount(100000, 'NORMAL')).toBe(100000)
    })

    // 경계값
    it('최소 주문금액(1000원) 할인 적용', () => {
      expect(calculator.calculateDiscount(1000, 'VIP')).toBe(800)
    })

    // 엣지 케이스
    it('금액 0원은 0원 반환', () => {
      expect(calculator.calculateDiscount(0, 'VIP')).toBe(0)
    })

    // 에러 케이스
    it('음수 금액은 에러 발생', () => {
      expect(() => calculator.calculateDiscount(-1000, 'VIP')).toThrow('금액은 0 이상이어야 합니다')
    })

    it('유효하지 않은 등급은 에러 발생', () => {
      expect(() => calculator.calculateDiscount(10000, 'PLATINUM' as any)).toThrow('유효하지 않은 등급')
    })
  })
})
```

---

## 5. 비동기 코드 테스트

```ts
describe('UserService', () => {
  it('사용자 생성 성공', async () => {
    // Mock 설정
    mockRepo.findByEmail.mockResolvedValue(null)
    mockRepo.create.mockResolvedValue({
      id: 'uuid-123',
      email: 'new@test.com',
      name: '홍길동',
    })

    const result = await userService.create({
      email: 'new@test.com',
      name: '홍길동',
      password: 'Password1!',
    })

    expect(result.id).toBe('uuid-123')
    expect(result.email).toBe('new@test.com')
    // 패스워드는 응답에 포함되지 않아야 함
    expect(result).not.toHaveProperty('password')
  })

  it('이메일 중복 시 ConflictException', async () => {
    mockRepo.findByEmail.mockResolvedValue({ id: '1', email: 'dup@test.com' })

    await expect(
      userService.create({ email: 'dup@test.com', name: '홍길동', password: 'pw' })
    ).rejects.toThrow(ConflictException)
  })

  it('DB 에러 발생 시 InternalServerErrorException', async () => {
    mockRepo.findByEmail.mockRejectedValue(new Error('Connection refused'))

    await expect(
      userService.create({ email: 'test@test.com', name: '홍길동', password: 'pw' })
    ).rejects.toThrow(InternalServerErrorException)
  })
})
```

---

## 6. TDD (Test-Driven Development)

```
Red   → 실패하는 테스트 먼저 작성
Green → 테스트를 통과하는 최소한의 코드 작성
Refactor → 코드 품질 개선 (테스트는 계속 통과)
```

```ts
// 1. Red — 실패하는 테스트
it('비밀번호는 최소 8자', () => {
  expect(validatePassword('short')).toBe(false)   // 아직 함수 없음 → 실패
})

// 2. Green — 통과하는 최소 구현
function validatePassword(password: string): boolean {
  return password.length >= 8
}

// 3. Refactor — 개선 (요구사항 추가)
function validatePassword(password: string): boolean {
  if (password.length < 8) return false
  if (!/[A-Z]/.test(password)) return false   // 대문자 포함
  if (!/[0-9]/.test(password)) return false   // 숫자 포함
  return true
}

// 추가 테스트
it('대문자 없으면 false', () => {
  expect(validatePassword('password1')).toBe(false)
})
it('숫자 없으면 false', () => {
  expect(validatePassword('Password')).toBe(false)
})
it('8자+대문자+숫자 포함하면 true', () => {
  expect(validatePassword('Password1')).toBe(true)
})
```

---

## 7. 커버리지 측정

```json
// jest.config.ts
{
  "collectCoverage": true,
  "coverageThreshold": {
    "global": {
      "lines": 80,
      "functions": 80,
      "branches": 70,
      "statements": 80
    },
    // 핵심 비즈니스 로직은 더 높게
    "./src/services/payment/**": {
      "lines": 95,
      "branches": 90
    }
  },
  "coveragePathIgnorePatterns": [
    "/node_modules/",
    "*.dto.ts",
    "*.entity.ts",
    "*.module.ts"
  ]
}
```

---

## 8. 안티패턴

- **구현 세부사항 테스트**: private 메서드, 내부 state 직접 접인 → 공개 API로
- **Mock 과도 사용**: 모든 것을 Mock하면 실제 동작 검증 불가
- **단언 없는 테스트**: `expect` 없는 테스트는 항상 통과
- **테스트끼리 의존**: 순서 바뀌면 실패 → 각 테스트 독립
- **커버리지만을 위한 테스트**: 의미 없는 테스트로 수치만 채우기
