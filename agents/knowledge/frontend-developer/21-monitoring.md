# Monitoring

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/monitoring

---

## 1. 모니터링 영역

| 영역 | 도구 | 목적 |
|------|------|------|
| **에러 트래킹** | Sentry | JS 에러, 스택 트레이스 |
| **성능 모니터링** | Vercel Analytics, Datadog RUM | Core Web Vitals |
| **로그** | Axiom, Datadog | 서버 로그 |
| **업타임** | Better Uptime, Checkly | 가용성 알림 |

---

## 2. Sentry 설정

```bash
npm install @sentry/nextjs
npx @sentry/wizard@latest -i nextjs
```

```ts
// sentry.client.config.ts
import * as Sentry from '@sentry/nextjs'

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,

  // 샘플링 — 운영은 낮게, 개발은 높게
  tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.1 : 1.0,
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,  // 에러 발생 시 100% 캡처

  integrations: [
    Sentry.replayIntegration(),
  ],

  // 민감 정보 필터링
  beforeSend(event) {
    // 패스워드 등 민감 데이터 제거
    if (event.request?.data) {
      delete event.request.data.password
    }
    return event
  },
})
```

```ts
// sentry.server.config.ts
import * as Sentry from '@sentry/nextjs'

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: 0.1,
})
```

---

## 3. 에러 컨텍스트 추가

```ts
import * as Sentry from '@sentry/nextjs'

// 사용자 정보 설정 (로그인 시)
Sentry.setUser({
  id: user.id,
  email: user.email,  // 정책에 따라 포함 여부 결정
})

// 에러에 컨텍스트 추가
try {
  await processPayment(orderId)
} catch (error) {
  Sentry.withScope(scope => {
    scope.setTag('payment.method', paymentMethod)
    scope.setContext('order', { orderId, amount })
    Sentry.captureException(error)
  })
  throw error
}

// 커스텀 이벤트 로깅
Sentry.addBreadcrumb({
  category: 'user-action',
  message: '결제 시작',
  data: { orderId },
  level: 'info',
})
```

---

## 4. 성능 모니터링

```tsx
// app/layout.tsx — Vercel Analytics
import { Analytics } from '@vercel/analytics/react'
import { SpeedInsights } from '@vercel/speed-insights/next'

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html>
      <body>
        {children}
        <Analytics />       {/* 방문자 분석 */}
        <SpeedInsights />   {/* Core Web Vitals */}
      </body>
    </html>
  )
}
```

```ts
// 커스텀 성능 측정
export function measurePerformance(name: string, fn: () => void) {
  performance.mark(`${name}-start`)
  fn()
  performance.mark(`${name}-end`)
  performance.measure(name, `${name}-start`, `${name}-end`)

  const measure = performance.getEntriesByName(name)[0]
  if (measure.duration > 100) {
    console.warn(`[Performance] ${name}: ${measure.duration.toFixed(2)}ms`)
  }
}
```

---

## 5. 로깅

```ts
// lib/logger.ts
type LogLevel = 'debug' | 'info' | 'warn' | 'error'

interface LogEntry {
  level: LogLevel
  message: string
  context?: Record<string, unknown>
  timestamp: string
}

export const logger = {
  debug: (message: string, context?: Record<string, unknown>) =>
    log('debug', message, context),
  info: (message: string, context?: Record<string, unknown>) =>
    log('info', message, context),
  warn: (message: string, context?: Record<string, unknown>) =>
    log('warn', message, context),
  error: (message: string | Error, context?: Record<string, unknown>) => {
    const message_ = message instanceof Error ? message.message : message
    log('error', message_, context)
    if (message instanceof Error) {
      Sentry.captureException(message, { extra: context })
    }
  },
}

function log(level: LogLevel, message: string, context?: Record<string, unknown>) {
  const entry: LogEntry = {
    level,
    message,
    context,
    timestamp: new Date().toISOString(),
  }

  if (process.env.NODE_ENV === 'production') {
    // Axiom, Datadog 등으로 전송
    axiom.ingest('logs', entry)
  } else {
    console[level](message, context)
  }
}
```

---

## 6. 알림 설정

```yaml
# Sentry 알림 규칙 (예시)
- 새 이슈 발생 → Slack #alerts 알림
- 에러율 5% 이상 → PagerDuty 호출
- Core Web Vitals LCP > 3s → 이메일 알림
```

**알림 피로 방지:**
- 중요도별 알림 채널 분리
- 유사 에러 그루핑
- 비업무 시간 낮은 우선순위 알림 묶기

---

## 7. 안티패턴

- **console.log로 운영 로깅**: 구조화된 로거 사용
- **에러 삼키기**: `catch (e) {}` → 반드시 로깅
- **샘플링 없는 트레이싱**: 100% 트레이싱 → 성능 저하 + 비용
- **PII 포함 로그**: 로그에 패스워드, 카드 번호 등 포함 금지
- **알림 설정 없음**: 장애를 사용자 제보로 알게 됨
