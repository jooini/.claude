# 에러 처리 리뷰

> 참조 링크: https://nodejs.org/api/errors.html, https://docs.nestjs.com/exception-filters

---

## 개요

에러 처리는 시스템 안정성의 핵심이다. catch 누락, 에러 삼킴, 의미 없는 메시지, timeout 미설정 등 실무에서 빈번한 에러 처리 문제를 리뷰 관점에서 다룬다.

## 1. Catch 누락

### 비동기 함수 에러 미처리

```typescript
// ❌ async 함수의 에러가 전파되지 않음
function startBackgroundJob() {
  processQueue(); // Promise 반환하지만 await/catch 없음 — 에러 사라짐
}

// ❌ 이벤트 핸들러에서 async 에러 누수
emitter.on('data', async (data) => {
  await processData(data); // 에러 시 unhandledRejection
});

// ✅ 에러 처리 추가
function startBackgroundJob() {
  processQueue().catch(err => {
    logger.error('Background job failed', { error: err });
    // 필요 시 재시도 또는 알림
  });
}

// ✅ 이벤트 핸들러 에러 래핑
emitter.on('data', async (data) => {
  try {
    await processData(data);
  } catch (err) {
    logger.error('Data processing failed', { error: err, data });
  }
});
```

### Promise.all 에러 처리

```typescript
// ❌ Promise.all에서 하나 실패 시 전체 실패 — 나머지 결과 유실
async function fetchAllData(ids: string[]): Promise<Data[]> {
  return await Promise.all(ids.map(id => fetchById(id)));
  // 하나만 실패해도 전체 reject
}

// ✅ Promise.allSettled로 부분 실패 허용
async function fetchAllData(ids: string[]): Promise<Data[]> {
  const results = await Promise.allSettled(ids.map(id => fetchById(id)));

  const succeeded: Data[] = [];
  const failed: string[] = [];

  results.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      succeeded.push(result.value);
    } else {
      failed.push(ids[index]);
      logger.warn(`Failed to fetch ${ids[index]}`, { reason: result.reason });
    }
  });

  if (failed.length > 0) {
    logger.warn(`Partial failure: ${failed.length}/${ids.length} items failed`);
  }

  return succeeded;
}
```

## 2. 에러 삼킴 (Swallowing Errors)

### 빈 catch 블록

```typescript
// ❌ 에러를 완전히 무시
try {
  await sendNotification(user);
} catch (e) {
  // 아무것도 안 함 — 에러가 삼켜짐
}

// ❌ console.log만 찍고 계속 진행
try {
  await chargePayment(order);
} catch (e) {
  console.log(e); // 결제 실패를 로그만 찍고 넘어감?
}

// ✅ 의도적 무시라면 명시적으로 표시
try {
  await sendNotification(user); // 알림 실패는 비즈니스에 영향 없음
} catch (e) {
  logger.warn('Notification failed (non-critical)', {
    error: e,
    userId: user.id,
  });
  // 의도적으로 에러를 삼킴 — 알림은 best-effort
}

// ✅ 중요한 작업은 반드시 에러 전파
try {
  await chargePayment(order);
} catch (e) {
  logger.error('Payment failed', { error: e, orderId: order.id });
  throw e; // 결제 실패는 상위로 전파
}
```

### 에러 정보 유실

```typescript
// ❌ 원본 에러 정보 유실
try {
  await externalApi.call(data);
} catch (e) {
  throw new Error('External API failed'); // 원본 에러의 메시지, 스택 사라짐
}

// ✅ cause로 원본 에러 체이닝
try {
  await externalApi.call(data);
} catch (e) {
  throw new Error('External API failed', { cause: e }); // ES2022 Error cause
}

// ✅ 커스텀 예외로 래핑
try {
  await externalApi.call(data);
} catch (e) {
  throw new ExternalApiException('Payment gateway timeout', {
    cause: e,
    service: 'stripe',
    operation: 'charge',
  });
}
```

## 3. 의미 없는 에러 메시지

```typescript
// ❌ 의미 없는 에러 메시지
throw new Error('Error occurred');
throw new Error('Something went wrong');
throw new Error('Failed');
throw new HttpException('Bad request', 400);

// ✅ 구체적이고 행동 가능한 에러 메시지
throw new Error('Failed to parse config file: invalid JSON at line 42');
throw new Error(`User ${userId} not found in organization ${orgId}`);
throw new BadRequestException('Email format is invalid: must contain @ symbol');
throw new ConflictException(`Order ${orderId} is already cancelled`);
```

### 에러 메시지 가이드라인

```typescript
// 좋은 에러 메시지의 구성 요소
interface GoodErrorMessage {
  what: string;     // 무엇이 실패했는가
  context: string;  // 어떤 맥락에서 (입력값, ID 등)
  why?: string;     // 왜 실패했는가 (알 수 있다면)
  action?: string;  // 어떻게 해결하는가 (사용자향)
}

// 예시
throw new BadRequestException(
  `Cannot update order ${orderId}: order is in '${order.status}' status, ` +
  `only 'pending' or 'confirmed' orders can be updated`
);
```

## 4. Timeout 미설정

### HTTP 요청 timeout

```typescript
// ❌ timeout 없는 외부 API 호출 — 무한 대기 가능
const response = await fetch('https://external-api.com/data');

// ❌ axios 기본 timeout 없음
const response = await axios.get('https://external-api.com/data');

// ✅ timeout 명시
const controller = new AbortController();
const timeoutId = setTimeout(() => controller.abort(), 5000); // 5초 timeout

try {
  const response = await fetch('https://external-api.com/data', {
    signal: controller.signal,
  });
  return await response.json();
} catch (e) {
  if (e.name === 'AbortError') {
    throw new Error('External API timeout after 5s');
  }
  throw e;
} finally {
  clearTimeout(timeoutId);
}

// ✅ axios timeout
const response = await axios.get('https://external-api.com/data', {
  timeout: 5000,
});
```

### DB 쿼리 timeout

```typescript
// ❌ 무거운 쿼리에 timeout 없음
const report = await dataSource.query(`
  SELECT * FROM transactions
  WHERE created_at BETWEEN $1 AND $2
  GROUP BY user_id
`, [startDate, endDate]);

// ✅ 쿼리 타임아웃 설정
const report = await dataSource.query(`
  SET statement_timeout = 10000; -- 10초
  SELECT * FROM transactions
  WHERE created_at BETWEEN $1 AND $2
  GROUP BY user_id
`, [startDate, endDate]);

// ✅ TypeORM QueryRunner로 timeout 설정
const queryRunner = dataSource.createQueryRunner();
await queryRunner.query('SET statement_timeout = 10000');
try {
  const report = await queryRunner.query(/*...*/);
  return report;
} finally {
  await queryRunner.release();
}
```

### 분산 락 timeout

```typescript
// ❌ 락 획득 대기에 timeout 없음
const lock = await redis.lock('resource-key'); // 영원히 대기할 수 있음

// ✅ 락 timeout + 자동 해제
const lock = await redis.lock('resource-key', {
  ttl: 10000,        // 락 자동 해제: 10초
  retryCount: 3,     // 최대 3번 재시도
  retryDelay: 200,   // 재시도 간격: 200ms
});

try {
  await criticalSection();
} finally {
  await lock.release();
}
```

## 5. finally 블록 누락

```typescript
// ❌ 에러 시 리소스 해제 안 됨
async function processFile(path: string): Promise<void> {
  const conn = await db.getConnection();
  const data = await readFile(path);
  await conn.query('INSERT INTO ...', data); // 여기서 에러나면 conn 미해제
  conn.release();
}

// ✅ finally로 리소스 정리 보장
async function processFile(path: string): Promise<void> {
  const conn = await db.getConnection();
  try {
    const data = await readFile(path);
    await conn.query('INSERT INTO ...', data);
  } finally {
    conn.release(); // 성공/실패 무관하게 항상 실행
  }
}
```

## 6. 전역 에러 핸들러

```typescript
// ✅ NestJS 전역 예외 필터
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  constructor(private readonly logger: Logger) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();
    const request = ctx.getRequest();

    const status = exception instanceof HttpException
      ? exception.getStatus()
      : 500;

    const message = exception instanceof HttpException
      ? exception.message
      : 'Internal server error';

    // 5xx만 에러 로그
    if (status >= 500) {
      this.logger.error('Unhandled exception', {
        exception,
        path: request.url,
        method: request.method,
        requestId: request.id,
      });
    }

    response.status(status).json({
      statusCode: status,
      message,
      timestamp: new Date().toISOString(),
      path: request.url,
    });
  }
}
```

## 7. 에러 처리 리뷰 체크리스트

- [ ] 모든 async 함수의 에러가 처리되는가? (await/catch)
- [ ] 빈 catch 블록이 없는가?
- [ ] 에러를 삼키는 경우 의도적임이 명시되어 있는가?
- [ ] 에러 메시지가 구체적이고 디버깅에 도움이 되는가?
- [ ] 원본 에러 정보가 유실되지 않는가? (Error cause)
- [ ] 외부 API/DB 호출에 timeout이 설정되어 있는가?
- [ ] 리소스(커넥션, 파일 핸들)가 finally에서 해제되는가?
- [ ] Promise.all vs Promise.allSettled 선택이 적절한가?
- [ ] 전역 에러 핸들러가 존재하는가?
- [ ] 에러 응답에 내부 정보(스택 트레이스, 쿼리)가 노출되지 않는가?
