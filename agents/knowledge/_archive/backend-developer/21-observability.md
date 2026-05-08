# Observability

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/observability

---

## 1. Observability 3 기둥

```
Logs    — 무슨 일이 일어났는가 (이벤트)
Metrics — 얼마나 자주/빠르게 (수치)
Traces  — 어떻게 흘렀는가 (요청 경로)
```

---

## 2. 구조화 로깅 (Pino)

```ts
// logger.module.ts
import pino from 'pino'

const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  transport: process.env.NODE_ENV === 'development'
    ? { target: 'pino-pretty' }           // 개발: 가독성
    : undefined,                           // 운영: JSON
  base: {
    service: process.env.SERVICE_NAME,
    version: process.env.APP_VERSION,
    env: process.env.NODE_ENV,
  },
  redact: ['req.headers.authorization', 'body.password'],  // 민감 정보 마스킹
})

// NestJS 로거 교체
const app = await NestFactory.create(AppModule, {
  logger: new PinoLogger(logger),
})
```

```ts
// 로그 레벨 기준
logger.debug('상세 디버그 정보', { query, params })        // 개발만
logger.info('요청 처리 완료', { orderId, duration: 120 })  // 일반 이벤트
logger.warn('재시도 발생', { attempt: 2, error: err.message }) // 주의 필요
logger.error('처리 실패', { orderId, error: err.stack })   // 즉시 조치 필요

// ✅ 구조화 — 검색/집계 가능
logger.info({ orderId, userId, amount, event: 'order.completed' })

// ❌ 비구조화 — 파싱 어려움
logger.info(`Order ${orderId} completed by user ${userId} for ${amount}`)
```

---

## 3. 요청 트레이싱

```ts
// 모든 요청에 Trace ID 주입
@Injectable()
export class TraceMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const traceId = req.headers['x-trace-id'] as string || randomUUID()
    const spanId  = randomUUID().slice(0, 8)

    req['traceId'] = traceId
    req['spanId']  = spanId

    // 응답 헤더에도 포함 (클라이언트 디버깅용)
    res.setHeader('x-trace-id', traceId)

    // 로거에 컨텍스트 주입
    const childLogger = logger.child({ traceId, spanId })
    req['logger'] = childLogger

    next()
  }
}

// 서비스 간 전파
@Injectable()
export class ExternalApiService {
  async call(data: unknown, traceId: string) {
    return this.http.post(url, data, {
      headers: { 'x-trace-id': traceId },  // 하위 서비스로 전파
    })
  }
}
```

---

## 4. 메트릭 (Prometheus + Grafana)

```ts
import { PrometheusModule } from '@willsoto/nestjs-prometheus'
import { Counter, Histogram, Gauge } from 'prom-client'

// 모듈 등록
PrometheusModule.register({ path: '/metrics', defaultMetrics: { enabled: true } })

// 커스텀 메트릭
@Injectable()
export class MetricsService {
  private readonly httpRequestsTotal = new Counter({
    name: 'http_requests_total',
    help: '총 HTTP 요청 수',
    labelNames: ['method', 'path', 'status'],
  })

  private readonly httpDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP 요청 처리 시간',
    labelNames: ['method', 'path'],
    buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5],
  })

  private readonly activeConnections = new Gauge({
    name: 'active_db_connections',
    help: '활성 DB 연결 수',
  })

  recordRequest(method: string, path: string, status: number, duration: number) {
    this.httpRequestsTotal.inc({ method, path, status })
    this.httpDuration.observe({ method, path }, duration)
  }
}

// 요청 측정 인터셉터
@Injectable()
export class MetricsInterceptor implements NestInterceptor {
  intercept(ctx: ExecutionContext, next: CallHandler) {
    const req = ctx.switchToHttp().getRequest()
    const start = Date.now()

    return next.handle().pipe(
      tap(() => {
        const duration = (Date.now() - start) / 1000
        const res = ctx.switchToHttp().getResponse()
        this.metricsService.recordRequest(req.method, req.path, res.statusCode, duration)
      }),
    )
  }
}
```

---

## 5. OpenTelemetry 통합

```ts
// tracing.ts — 앱 시작 전 초기화 필수
import { NodeSDK } from '@opentelemetry/sdk-node'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT,
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-http': { enabled: true },
      '@opentelemetry/instrumentation-pg': { enabled: true },
      '@opentelemetry/instrumentation-redis': { enabled: true },
    }),
  ],
})

sdk.start()

// main.ts에서 최상단에 import
// import './tracing'
```

---

## 6. 알림 & SLO

```yaml
# Prometheus AlertManager 규칙
groups:
  - name: api-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          / sum(rate(http_requests_total[5m])) > 0.01
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "에러율 1% 초과"

      - alert: SlowResponseTime
        expr: |
          histogram_quantile(0.95, http_request_duration_seconds_bucket) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P95 응답 시간 1초 초과"

# SLO 정의
# 가용성: 99.9% (월 43분 다운타임 허용)
# P99 응답 시간: 500ms 이하
```

---

## 7. 안티패턴

- **console.log 로깅**: 구조화 로거 사용
- **로그에 민감 정보**: 패스워드, 카드번호, 토큰 마스킹
- **Trace ID 없는 분산 시스템**: 요청 추적 불가
- **메트릭 없는 운영**: 장애를 사용자 제보로 알게 됨
- **너무 많은 로그**: Debug 레벨 운영 적용 → 스토리지/성능 부담
