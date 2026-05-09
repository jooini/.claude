# 로깅/모니터링 리뷰

> 참조 링크: https://www.loggly.com/ultimate-guide/node-logging-basics/, https://opentelemetry.io/docs/

---

## 개요

적절한 로깅은 프로덕션 문제 해결의 핵심 도구다. 리뷰어는 로그 레벨 적절성, 민감 정보 노출, 구조화 로깅, 추적 ID 전파를 중심으로 검토한다.

## 1. 로그 레벨

### 레벨별 사용 기준

```typescript
// 로그 레벨 가이드
// ERROR — 즉시 대응 필요. 서비스 기능 불가 상태
// WARN  — 잠재적 문제. 곧 에러가 될 수 있음
// INFO  — 비즈니스 이벤트. 정상 흐름 기록
// DEBUG — 개발/디버깅용 상세 정보. 프로덕션에서 보통 OFF

// ❌ 로그 레벨 오용
class OrderService {
  async createOrder(dto: CreateOrderDto): Promise<Order> {
    this.logger.error(`Creating order for user ${dto.userId}`);   // 에러 아닌데 ERROR
    this.logger.debug('Order created successfully');                // 비즈니스 이벤트인데 DEBUG
    this.logger.info(`SQL: SELECT * FROM orders WHERE ...`);       // 쿼리 로그가 INFO
    console.log('payment processed');                               // console.log 사용
  }
}

// ✅ 올바른 로그 레벨
class OrderService {
  async createOrder(dto: CreateOrderDto): Promise<Order> {
    this.logger.debug('Creating order', { userId: dto.userId, items: dto.items.length });

    try {
      const order = await this.processOrder(dto);
      this.logger.info('Order created', { orderId: order.id, total: order.total }); // 비즈니스 이벤트 → INFO
      return order;
    } catch (error) {
      if (error instanceof InsufficientStockError) {
        this.logger.warn('Order failed: insufficient stock', {   // 예상된 실패 → WARN
          userId: dto.userId,
          items: dto.items,
        });
      } else {
        this.logger.error('Order creation failed', {              // 예상치 못한 실패 → ERROR
          userId: dto.userId,
          error: error.message,
          stack: error.stack,
        });
      }
      throw error;
    }
  }
}
```

### 로그 레벨 체크리스트

- [ ] 정상 흐름에서 ERROR/WARN이 발생하지 않는가?
- [ ] 비즈니스 이벤트(주문 생성, 결제 완료)가 INFO로 기록되는가?
- [ ] 예상된 실패(유효성 검증, 재고 부족)가 WARN인가?
- [ ] 예상치 못한 실패(DB 연결 끊김, 외부 API 장애)가 ERROR인가?
- [ ] `console.log` / `console.error` 대신 로거를 사용하는가?
- [ ] DEBUG 로그가 프로덕션에서 과도한 I/O를 유발하지 않는가?

## 2. 민감 정보

### 로그에 노출되면 안 되는 정보

```typescript
// ❌ 민감 정보가 로그에 노출됨
this.logger.info('User login', {
  email: user.email,
  password: dto.password,              // 비밀번호!
  creditCard: user.creditCardNumber,   // 카드 번호!
  ssn: user.socialSecurityNumber,      // 주민번호!
  token: user.accessToken,             // 인증 토큰!
});

this.logger.error('Payment failed', {
  request: JSON.stringify(paymentRequest), // 결제 정보 전체 덤프!
});

// ✅ 민감 정보 마스킹
this.logger.info('User login', {
  email: maskEmail(user.email),             // p***@example.com
  userId: user.id,                          // ID만 기록
});

this.logger.error('Payment failed', {
  orderId: order.id,
  amount: order.total,
  paymentMethod: 'credit_card',
  lastFourDigits: creditCard.slice(-4),     // 마지막 4자리만
  errorCode: error.code,
});

// 마스킹 유틸리티
function maskEmail(email: string): string {
  const [local, domain] = email.split('@');
  return `${local[0]}***@${domain}`;
}

function maskCardNumber(cardNumber: string): string {
  return `****-****-****-${cardNumber.slice(-4)}`;
}
```

### 민감 정보 체크리스트

- [ ] 비밀번호, 토큰, API 키가 로그에 포함되지 않는가?
- [ ] 개인정보(이메일, 전화번호, 주소)가 마스킹되어 있는가?
- [ ] 결제 정보(카드 번호, CVV)가 로그에 노출되지 않는가?
- [ ] 요청/응답 전체를 덤프하는 로그가 없는가?
- [ ] 에러 스택 트레이스에 환경 변수나 설정값이 포함되지 않는가?

## 3. 구조화 로깅

### 비구조화 vs 구조화

```typescript
// ❌ 비구조화 로그: 파싱 어려움, 검색 불편
this.logger.info(`User ${userId} created order ${orderId} with total ${total}`);
this.logger.error(`Payment failed for order ${orderId}: ${error.message}`);

// 로그 출력: "User abc-123 created order ord-456 with total 50000"
// → 특정 userId 검색하려면 정규표현식 필요

// ✅ 구조화 로그: JSON 형태, 쉬운 검색/집계
this.logger.info('Order created', {
  userId: 'abc-123',
  orderId: 'ord-456',
  total: 50000,
  currency: 'KRW',
  itemCount: 3,
});

// 로그 출력 (JSON):
// {"level":"info","message":"Order created","userId":"abc-123","orderId":"ord-456","total":50000,...}
// → userId로 필터링, total로 집계 가능
```

### 로그 컨텍스트 표준화

```typescript
// 공통 로그 필드 정의
interface LogContext {
  traceId: string;       // 요청 추적 ID
  spanId?: string;       // 스팬 ID (분산 추적)
  userId?: string;       // 인증된 사용자
  requestId?: string;    // HTTP 요청 ID
  service: string;       // 서비스 이름
  environment: string;   // dev, staging, prod
}

// NestJS 인터셉터로 자동 주입
@Injectable()
class LoggingInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest();
    const traceId = request.headers['x-trace-id'] || uuidv4();
    const startTime = Date.now();

    return next.handle().pipe(
      tap(() => {
        this.logger.info('Request completed', {
          traceId,
          method: request.method,
          url: request.url,
          statusCode: context.switchToHttp().getResponse().statusCode,
          duration: Date.now() - startTime,
          userId: request.user?.id,
        });
      }),
      catchError((error) => {
        this.logger.error('Request failed', {
          traceId,
          method: request.method,
          url: request.url,
          error: error.message,
          stack: error.stack,
          duration: Date.now() - startTime,
        });
        throw error;
      }),
    );
  }
}
```

### 구조화 로깅 체크리스트

- [ ] 로그가 JSON 형태(구조화)로 출력되는가?
- [ ] 로그 메시지에 변수를 인라인 삽입하지 않고 별도 필드로 전달하는가?
- [ ] 공통 필드(traceId, userId, service)가 자동으로 포함되는가?
- [ ] 타임스탬프가 ISO 8601 형식인가?

## 4. 추적 ID (Trace ID)

### 분산 추적

```typescript
// ❌ 추적 ID 없이 로그 — 여러 서비스에서 같은 요청 추적 불가
// Service A: "Order created ord-123"
// Service B: "Payment processed for ord-123"
// Service C: "Email sent"
// → 이 3개가 같은 요청인지 알 수 없음

// ✅ 추적 ID로 요청 흐름 연결
// 미들웨어에서 traceId 생성/전파
@Injectable()
class TraceMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction): void {
    const traceId = req.headers['x-trace-id'] as string || uuidv4();
    req['traceId'] = traceId;
    res.setHeader('x-trace-id', traceId); // 클라이언트에도 반환

    // AsyncLocalStorage로 전체 요청 컨텍스트에서 접근 가능
    asyncLocalStorage.run({ traceId }, () => next());
  }
}

// 외부 서비스 호출 시 traceId 전파
class PaymentClient {
  async charge(order: Order): Promise<PaymentResult> {
    const traceId = asyncLocalStorage.getStore()?.traceId;

    return this.httpClient.post('/payments', order, {
      headers: { 'x-trace-id': traceId }, // 다음 서비스로 전파
    });
  }
}

// 모든 로그에 traceId 자동 포함
// Service A: {"traceId":"abc-123","message":"Order created","orderId":"ord-456"}
// Service B: {"traceId":"abc-123","message":"Payment processed","orderId":"ord-456"}
// Service C: {"traceId":"abc-123","message":"Email sent","orderId":"ord-456"}
// → traceId로 필터링하면 전체 흐름 추적 가능
```

### 추적 ID 체크리스트

- [ ] 모든 HTTP 요청에 traceId가 생성/전파되는가?
- [ ] 외부 서비스 호출 시 traceId를 헤더로 전달하는가?
- [ ] 메시지 큐 메시지에 traceId가 포함되는가?
- [ ] 에러 응답에 traceId가 포함되어 디버깅을 도울 수 있는가?
- [ ] 로그 검색 시 traceId 하나로 전체 요청 흐름을 추적할 수 있는가?

## 5. 모니터링 포인트

### 핵심 메트릭

```typescript
// 비즈니스 메트릭 로깅
this.logger.info('order.created', { orderId, total, itemCount }); // 주문 수, 매출
this.logger.info('user.registered', { userId, source });          // 가입자 수, 채널
this.logger.info('payment.completed', { orderId, amount, method }); // 결제 성공률

// 기술 메트릭 로깅
this.logger.info('http.request', { method, url, statusCode, duration }); // 응답 시간
this.logger.warn('circuit.opened', { service, failureCount });          // 서킷 브레이커
this.logger.error('db.connection.failed', { host, retryCount });        // DB 연결 실패
```

### 모니터링 체크리스트

- [ ] 핵심 비즈니스 이벤트(주문, 결제, 가입)가 로깅되는가?
- [ ] 외부 서비스 호출 시 응답 시간과 성공/실패가 기록되는가?
- [ ] 에러 발생 시 알림(alert)으로 연결되는 구조인가?
- [ ] 느린 쿼리가 감지/로깅되는가?

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| 민감 정보 노출 | 비밀번호, 토큰, 카드번호 로그 출력 | P0 |
| 추적 ID 부재 | 분산 환경에서 요청 추적 불가 | P1 |
| 로그 레벨 오용 | 정상 흐름에 ERROR, 장애에 DEBUG | P1 |
| console.log 사용 | 프로덕션 코드에 console 직접 사용 | P2 |
| 비구조화 로그 | 문자열 결합 방식 로그 | P2 |
| 로그 과다/부족 | 핵심 이벤트 누락 또는 과도한 DEBUG | P2 |
