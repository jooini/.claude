# Type Safety

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/type-safety

---

## 1. 타입 안전성이 왜 품질에 중요한가

타입 오류를 런타임이 아닌 컴파일 타임에 발견.
테스트 전에 버그를 제거하는 가장 저렴한 방법.

```
타입 오류 발견 비용:
  개발 중 (타입 체크) : 1배
  코드 리뷰          : 6배
  QA 테스트          : 15배
  운영 발생          : 100배
```

---

## 2. strict 설정 체크리스트

```json
// tsconfig.json — 전체 strict 활성화
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

---

## 3. 런타임 타입 검증 (Zod)

```ts
// 컴파일 타임 + 런타임 모두 검증
import { z } from 'zod'

const CreateOrderSchema = z.object({
  productId: z.string().uuid(),
  quantity:  z.number().int().positive().max(100),
  couponCode: z.string().optional(),
})

type CreateOrderDto = z.infer<typeof CreateOrderSchema>

// API 엔드포인트에서 검증
@Post()
async createOrder(@Body() body: unknown) {
  const dto = CreateOrderSchema.parse(body)  // 실패 시 ZodError throw
  return this.ordersService.create(dto)
}

// 외부 API 응답 검증
const ExternalApiResponseSchema = z.object({
  transactionId: z.string(),
  status: z.enum(['success', 'failed', 'pending']),
  amount: z.number(),
})

const response = await paymentApi.charge(data)
const validated = ExternalApiResponseSchema.safeParse(response)
if (!validated.success) {
  logger.error('Unexpected API response shape', validated.error)
  throw new ExternalApiException()
}
```

---

## 4. 타입 안전 테스트

```ts
// 타입 테스트 — tsd 또는 expect-type
import { expectType, expectError } from 'tsd'
import { calculateDiscount } from './discount'

// 반환 타입 검증
expectType<number>(calculateDiscount(10000, 'VIP'))

// 잘못된 타입 거부 확인
expectError(calculateDiscount('string', 'VIP'))  // 첫 번째 인자가 number여야 함
expectError(calculateDiscount(10000, 'PLATINUM'))  // 유효하지 않은 등급

// 제네릭 타입 추론 검증
const users = await getUsers<User>()
expectType<User[]>(users)
```

---

## 5. 타입 가드 테스트

```ts
describe('타입 가드', () => {
  it('isApiError가 ApiError를 올바르게 판별', () => {
    const apiError = new ApiError(404, 'NOT_FOUND', '찾을 수 없습니다')
    const regularError = new Error('일반 에러')

    expect(isApiError(apiError)).toBe(true)
    expect(isApiError(regularError)).toBe(false)
    expect(isApiError(null)).toBe(false)
    expect(isApiError(undefined)).toBe(false)
    expect(isApiError('string')).toBe(false)
  })
})
```

---

## 6. any 사용 감사

```ts
// ESLint 규칙으로 자동 탐지
"@typescript-eslint/no-explicit-any": "error"

// CI에서 any 사용 수 추적
// scripts/check-any.sh
ANY_COUNT=$(grep -rn ": any" src --include="*.ts" | wc -l)
echo "any 사용 수: $ANY_COUNT"

if [ $ANY_COUNT -gt 10 ]; then
  echo "any 사용 수가 허용치(10)를 초과했습니다"
  exit 1
fi
```

---

## 7. 안티패턴

- **`any` 타입 남용**: `unknown` + 타입 가드로 대체
- **타입 체크 비활성화**: `// @ts-ignore` 대신 타입 정의 개선
- **런타임 검증 없음**: Zod로 외부 입력 검증
- **타입 단언 남용**: `as UserType` 대신 타입 가드
- **strict 끄기**: 점진적으로 활성화하더라도 최종 목표는 strict
