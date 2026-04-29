# Resilience

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/resilience

---

## 1. 복원력(Resilience) 패턴 개요

외부 의존성(DB, 외부 API, 메시지 큐) 장애에도 시스템이 견고하게 동작하도록.

```
Circuit Breaker — 연속 실패 시 빠른 실패로 전환
Retry           — 일시적 실패 재시도
Timeout         — 무한 대기 방지
Bulkhead        — 장애 격리, 다른 기능 보호
Fallback        — 대체 응답 제공
Rate Limiter    — 과부하 방지
```

---

## 2. Circuit Breaker

```ts
// cockatiel 라이브러리
import { CircuitBreakerPolicy, ConsecutiveBreaker } from 'cockatiel'

@Injectable()
export class PaymentGatewayService {
  private readonly circuitBreaker = CircuitBreakerPolicy.handleAll()
    .circuitBreaker(10_000, new ConsecutiveBreaker(5))  // 5회 연속 실패 → 10초 개방
    .withFallback(() => {
      throw new ServiceUnavailableException('결제 서비스가 일시적으로 불가합니다')
    })

  async charge(amount: number, cardToken: string) {
    return this.circuitBreaker.execute(() =>
      this.externalPaymentApi.charge({ amount, cardToken })
    )
  }
}

// 상태: Closed(정상) → Open(차단) → Half-Open(테스트) → Closed
```

---

## 3. Retry

```ts
import { RetryPolicy } from 'cockatiel'

// 지수 백오프 재시도
const retry = RetryPolicy.handleAll()
  .retry()
  .attempts(3)
  .exponential({ initialDelay: 100, maxDelay: 5000 })

await retry.execute(() => externalApi.call())

// 재시도 제외 — 4xx 에러는 재시도 무의미
const retry = RetryPolicy
  .handleWhen(err => !(err instanceof HttpException && err.getStatus() < 500))
  .retry()
  .attempts(3)
  .exponential({ initialDelay: 200 })

// NestJS Axios 재시도
import { HttpService } from '@nestjs/axios'
import axiosRetry from 'axios-retry'

@Injectable()
export class ExternalApiService {
  constructor(private readonly httpService: HttpService) {
    axiosRetry(this.httpService.axiosRef, {
      retries: 3,
      retryDelay: axiosRetry.exponentialDelay,
      retryCondition: (error) =>
        axiosRetry.isNetworkOrIdempotentRequestError(error) ||
        error.response?.status >= 500,
    })
  }
}
```

---

## 4. Timeout

```ts
// 타임아웃 래퍼
async function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  errorMessage = `Timeout after ${ms}ms`,
): Promise<T> {
  const timeout = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error(errorMessage)), ms)
  )
  return Promise.race([promise, timeout])
}

// 사용
const user = await withTimeout(
  this.userService.findById(userId),
  3000,
  'User service timeout',
)

// Axios 타임아웃
const response = await this.httpService.axiosRef.get(url, {
  timeout: 5000,  // 5초
})

// 타임아웃 + 재시도 조합
const result = await retry.execute(() =>
  withTimeout(externalApi.call(), 3000)
)
```

---

## 5. Bulkhead (격벽)

장애가 다른 기능으로 전파되지 않도록 격리.

```ts
// 연결 풀 분리 — 중요한 서비스는 별도 풀
const criticalPool  = new Pool({ max: 20 })  // 결제 등 중요 기능
const standardPool  = new Pool({ max: 10 })  // 일반 조회
const backgroundPool = new Pool({ max: 5 })  // 배치, 집계

// 동시 실행 수 제한 — Semaphore
import { Semaphore } from 'async-mutex'

@Injectable()
export class ImageProcessingService {
  private readonly semaphore = new Semaphore(5)  // 동시 5개만 처리

  async processImage(imageId: string) {
    const [, release] = await this.semaphore.acquire()
    try {
      return await this.doProcess(imageId)
    } finally {
      release()
    }
  }
}
```

---

## 6. Fallback

```ts
@Injectable()
export class RecommendationService {
  async getRecommendations(userId: string): Promise<Product[]> {
    try {
      // ML 기반 개인화 추천
      return await withTimeout(
        this.mlService.recommend(userId),
        2000,
      )
    } catch (error) {
      this.logger.warn(`ML recommendation failed: ${error.message}, using fallback`)
      // Fallback: 인기 상품 반환
      return this.getPopularProducts()
    }
  }

  private async getPopularProducts(): Promise<Product[]> {
    const cached = await this.redis.get('popular:products')
    if (cached) return JSON.parse(cached)
    return this.productRepo.findPopular(10)
  }
}
```

---

## 7. Health Check

```ts
// NestJS Terminus
import { HealthCheckService, TypeOrmHealthIndicator, MemoryHealthIndicator } from '@nestjs/terminus'

@Controller('health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private db: TypeOrmHealthIndicator,
    private memory: MemoryHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      () => this.db.pingCheck('database'),
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024),  // 300MB
      () => this.checkRedis(),
      () => this.checkExternalApi(),
    ])
  }

  private async checkRedis() {
    await this.redis.ping()
    return { redis: { status: 'up' } }
  }
}

// 응답
// {
//   "status": "ok",
//   "info": { "database": { "status": "up" }, "redis": { "status": "up" } },
//   "error": {},
//   "details": { ... }
// }
```

---

## 8. 안티패턴

- **Circuit Breaker 없는 외부 API 호출**: 외부 서비스 장애가 전파
- **재시도 없는 네트워크 호출**: 일시적 오류로 불필요한 실패
- **타임아웃 없는 HTTP 요청**: 외부 서비스 hang으로 연결 풀 고갈
- **모든 에러를 재시도**: 4xx 에러는 재시도 의미 없음
- **Fallback 없는 중요 기능**: 의존 서비스 장애 시 완전 불능
