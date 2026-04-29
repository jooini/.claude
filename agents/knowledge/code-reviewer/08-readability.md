# 가독성/네이밍

> 참조 링크: https://google.github.io/styleguide/tsguide.html, https://refactoring.guru/refactoring/smells

---

## 개요

가독성은 유지보수성의 기반이다. 네이밍 컨벤션, 죽은 코드, 인지 복잡도, 함수 크기, 매직 넘버 등 코드를 읽기 어렵게 만드는 요인을 리뷰 관점에서 다룬다.

## 1. 네이밍 컨벤션

### 변수/함수 네이밍

```typescript
// ❌ 의미 없는 이름
const d = new Date();
const arr = users.filter(u => u.a);
function proc(x: number): number { return x * 2; }
const temp = calculateTotal(items);

// ✅ 의도를 드러내는 이름
const registrationDate = new Date();
const activeUsers = users.filter(user => user.isActive);
function doublePrice(price: number): number { return price * 2; }
const orderTotal = calculateTotal(items);
```

### Boolean 네이밍

```typescript
// ❌ Boolean이 아닌 것처럼 보이는 이름
const active = true;
const permission = false;
const login = user.token !== null;

// ✅ is/has/can/should 접두어
const isActive = true;
const hasPermission = false;
const isLoggedIn = user.token !== null;
const canEdit = user.role === 'admin' || user.id === resource.ownerId;
const shouldRetry = attempts < maxRetries;
```

### 함수 네이밍

```typescript
// ❌ 동작이 모호한 이름
function handleUser(user: User): void { /* ... */ }
function processData(data: unknown): void { /* ... */ }
function doStuff(): void { /* ... */ }

// ✅ 동작을 명확히 표현
function deactivateUser(user: User): void { /* ... */ }
function validateAndTransformInput(data: unknown): ProcessedData { /* ... */ }
function sendWelcomeEmail(user: User): Promise<void> { /* ... */ }

// 네이밍 패턴
// get* — 동기적으로 값을 반환
// fetch* — 비동기 외부 호출
// find* — 검색 (없으면 null/undefined)
// create* — 새 리소스 생성
// update* — 기존 리소스 수정
// delete/remove* — 리소스 삭제
// validate* — 유효성 검증 (에러 throw)
// is/has/can* — boolean 반환
// to* — 변환 (toJSON, toDTO)
```

### 클래스/인터페이스 네이밍

```typescript
// ❌ 모호한 클래스명
class Manager { /* ... */ }
class Helper { /* ... */ }
class Util { /* ... */ }
class Data { /* ... */ }

// ✅ 역할이 명확한 클래스명
class UserRepository { /* ... */ }
class PaymentGateway { /* ... */ }
class OrderValidator { /* ... */ }
class EmailTemplateRenderer { /* ... */ }

// 인터페이스 — I 접두어 사용 여부는 프로젝트 컨벤션에 따름
interface UserRepository { /* ... */ }     // NestJS 스타일
interface IUserRepository { /* ... */ }    // C# 스타일
```

## 2. 죽은 코드

### 주석 처리된 코드

```typescript
// ❌ 주석 처리된 코드 방치
function calculatePrice(product: Product): number {
  // const discount = getSeasonalDiscount(product);
  // const adjustedPrice = product.price - discount;
  // if (product.category === 'electronics') {
  //   return adjustedPrice * 0.9;
  // }
  return product.price * 0.85;
}

// ✅ 주석 코드 제거 — 히스토리는 Git에 있다
function calculatePrice(product: Product): number {
  return product.price * 0.85;
}
```

### 사용되지 않는 코드

```typescript
// ❌ 사용되지 않는 import
import { Injectable, Logger, Scope, Inject } from '@nestjs/common';
// Logger, Scope, Inject는 사용하지 않음

// ❌ 사용되지 않는 변수
function processOrder(order: Order): OrderResult {
  const user = order.user;     // 아래에서 사용 안 함
  const items = order.items;
  const total = items.reduce((sum, item) => sum + item.price, 0);
  return { orderId: order.id, total };
}

// ❌ 도달 불가능한 코드
function validate(input: string): boolean {
  if (!input) return false;
  return true;
  console.log('validation complete'); // 도달 불가능
}

// ✅ 사용하는 것만 남기기
import { Injectable } from '@nestjs/common';

function processOrder(order: Order): OrderResult {
  const total = order.items.reduce((sum, item) => sum + item.price, 0);
  return { orderId: order.id, total };
}
```

## 3. 인지 복잡도

### 깊은 중첩

```typescript
// ❌ 중첩 3단계 이상 — 읽기 어려움
function processOrder(order: Order): string {
  if (order) {
    if (order.items.length > 0) {
      if (order.paymentMethod) {
        if (order.paymentMethod.isValid) {
          if (order.shippingAddress) {
            return 'ready';
          } else {
            return 'missing_address';
          }
        } else {
          return 'invalid_payment';
        }
      } else {
        return 'no_payment';
      }
    } else {
      return 'empty_cart';
    }
  } else {
    return 'no_order';
  }
}

// ✅ 가드 절(Guard Clause)로 평탄화
function processOrder(order: Order): string {
  if (!order) return 'no_order';
  if (order.items.length === 0) return 'empty_cart';
  if (!order.paymentMethod) return 'no_payment';
  if (!order.paymentMethod.isValid) return 'invalid_payment';
  if (!order.shippingAddress) return 'missing_address';

  return 'ready';
}
```

### 복잡한 조건식

```typescript
// ❌ 복잡한 조건식을 인라인으로
if (user.role === 'admin' || (user.role === 'manager' && user.department === order.department) || (user.role === 'agent' && order.assignedTo === user.id && order.status !== 'closed')) {
  approveOrder(order);
}

// ✅ 의미 있는 변수로 분리
const isAdmin = user.role === 'admin';
const isDepartmentManager = user.role === 'manager' && user.department === order.department;
const isAssignedAgent = user.role === 'agent' && order.assignedTo === user.id && order.status !== 'closed';

if (isAdmin || isDepartmentManager || isAssignedAgent) {
  approveOrder(order);
}

// 또는 함수로 추출
function canApproveOrder(user: User, order: Order): boolean {
  if (user.role === 'admin') return true;
  if (user.role === 'manager' && user.department === order.department) return true;
  if (user.role === 'agent' && order.assignedTo === user.id && order.status !== 'closed') return true;
  return false;
}
```

## 4. 함수 크기

### 함수 분할 기준

```typescript
// ❌ 하나의 함수에서 여러 책임
async function createOrder(dto: CreateOrderDto, user: User): Promise<Order> {
  // 입력 검증 (10줄)
  if (!dto.items || dto.items.length === 0) throw new Error('No items');
  for (const item of dto.items) {
    if (item.quantity <= 0) throw new Error('Invalid quantity');
    const product = await productRepo.findOne({ where: { id: item.productId } });
    if (!product) throw new Error(`Product ${item.productId} not found`);
    if (product.stock < item.quantity) throw new Error('Out of stock');
  }

  // 가격 계산 (10줄)
  let total = 0;
  for (const item of dto.items) {
    const product = await productRepo.findOne({ where: { id: item.productId } });
    total += product.price * item.quantity;
  }
  const tax = total * 0.1;
  const discount = await calculateDiscount(user, total);
  const finalTotal = total + tax - discount;

  // 재고 차감 (5줄) ...
  // 결제 처리 (10줄) ...
  // 주문 저장 (5줄) ...
  // 알림 발송 (5줄) ...
  // 총 50줄 이상
}

// ✅ 각 책임을 별도 함수로 분리
async function createOrder(dto: CreateOrderDto, user: User): Promise<Order> {
  await validateOrderItems(dto.items);
  const pricing = await calculateOrderPricing(dto.items, user);
  await reserveInventory(dto.items);

  const order = await saveOrder({
    userId: user.id,
    items: dto.items,
    ...pricing,
  });

  await processPayment(order);
  await sendOrderConfirmation(order, user); // fire-and-forget 가능

  return order;
}
```

## 5. 매직 넘버

```typescript
// ❌ 의미를 알 수 없는 숫자/문자열
if (retryCount > 3) { /* ... */ }
if (password.length < 8) { /* ... */ }
setTimeout(callback, 86400000);
if (status === 'A') { /* ... */ }

// ✅ 상수로 의미 부여
const MAX_RETRY_COUNT = 3;
const MIN_PASSWORD_LENGTH = 8;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

const OrderStatus = {
  ACTIVE: 'A',
  CANCELLED: 'C',
  COMPLETED: 'D',
} as const;

if (retryCount > MAX_RETRY_COUNT) { /* ... */ }
if (password.length < MIN_PASSWORD_LENGTH) { /* ... */ }
setTimeout(callback, ONE_DAY_MS);
if (status === OrderStatus.ACTIVE) { /* ... */ }
```

### 허용되는 매직 넘버

```typescript
// 다음은 상수화 불필요 — 의미가 자명
const half = total / 2;
const doubled = value * 2;
const percentage = (count / total) * 100;
array.slice(0, 1); // 첫 번째 요소
```

## 6. 일관성

```typescript
// ❌ 같은 프로젝트에서 비일관적인 패턴
// 파일 A: callback 스타일
function getUser(id: string, callback: (err: Error, user: User) => void) { /* ... */ }

// 파일 B: Promise 스타일
function getOrder(id: string): Promise<Order> { /* ... */ }

// 파일 C: async/await
async function getProduct(id: string): Promise<Product> { /* ... */ }

// ✅ 프로젝트 내 일관된 패턴 유지
async function getUser(id: string): Promise<User> { /* ... */ }
async function getOrder(id: string): Promise<Order> { /* ... */ }
async function getProduct(id: string): Promise<Product> { /* ... */ }
```

## 7. 가독성 리뷰 체크리스트

- [ ] 변수/함수 이름이 의도를 명확히 드러내는가?
- [ ] Boolean 변수에 is/has/can/should 접두어가 있는가?
- [ ] 주석 처리된 코드가 없는가?
- [ ] 사용되지 않는 import/변수/함수가 없는가?
- [ ] 중첩이 3단계 이상인 곳이 없는가?
- [ ] 복잡한 조건식이 의미 있는 변수나 함수로 추출되었는가?
- [ ] 함수가 하나의 책임만 가지는가? (20-30줄 이내 권장)
- [ ] 매직 넘버가 상수로 정의되어 있는가?
- [ ] 프로젝트 컨벤션과 일관성을 유지하는가?
- [ ] 불필요한 주석 없이 코드 자체가 의미를 전달하는가?
