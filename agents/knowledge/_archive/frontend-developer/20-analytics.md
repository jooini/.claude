# Analytics

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/analytics

---

## 1. 분석 도구 스택

| 도구 | 용도 |
|------|------|
| **Vercel Analytics** | Core Web Vitals, 트래픽 |
| **Mixpanel / Amplitude** | 이벤트 기반 제품 분석 |
| **Google Analytics 4** | 범용 웹 분석 |
| **Sentry** | 에러 트래킹 |
| **FullStory / LogRocket** | 세션 리플레이 |

---

## 2. 이벤트 트래킹 설계

### 이벤트 네이밍 컨벤션

```
{객체}_{행위}

user_signed_up
user_logged_in
payment_completed
payment_failed
product_viewed
product_added_to_cart
button_clicked
form_submitted
```

### 이벤트 스키마

```ts
// analytics/events.ts
interface BaseEvent {
  userId?: string
  sessionId: string
  timestamp: number
  page: string
}

interface ButtonClickedEvent extends BaseEvent {
  event: 'button_clicked'
  properties: {
    buttonName: string
    buttonLocation: string
  }
}

interface PaymentCompletedEvent extends BaseEvent {
  event: 'payment_completed'
  properties: {
    orderId: string
    amount: number
    currency: string
    paymentMethod: string
  }
}

type AnalyticsEvent = ButtonClickedEvent | PaymentCompletedEvent | ...
```

---

## 3. Analytics 추상화 레이어

특정 서비스에 종속되지 않도록 추상화.

```ts
// analytics/client.ts
type EventName = string
type EventProperties = Record<string, unknown>

interface AnalyticsProvider {
  track(event: EventName, properties?: EventProperties): void
  identify(userId: string, traits?: Record<string, unknown>): void
  page(name: string, properties?: EventProperties): void
}

class Analytics implements AnalyticsProvider {
  private providers: AnalyticsProvider[] = []

  addProvider(provider: AnalyticsProvider) {
    this.providers.push(provider)
  }

  track(event: EventName, properties?: EventProperties) {
    this.providers.forEach(p => p.track(event, properties))
  }

  identify(userId: string, traits?: Record<string, unknown>) {
    this.providers.forEach(p => p.identify(userId, traits))
  }

  page(name: string, properties?: EventProperties) {
    this.providers.forEach(p => p.page(name, properties))
  }
}

// Mixpanel 어댑터
class MixpanelProvider implements AnalyticsProvider {
  track(event: string, properties?: EventProperties) {
    mixpanel.track(event, properties)
  }
  identify(userId: string, traits?: Record<string, unknown>) {
    mixpanel.identify(userId)
    if (traits) mixpanel.people.set(traits)
  }
  page(name: string, properties?: EventProperties) {
    mixpanel.track('page_viewed', { page: name, ...properties })
  }
}

export const analytics = new Analytics()
analytics.addProvider(new MixpanelProvider())
```

---

## 4. 페이지뷰 자동 트래킹

```tsx
// app/providers/analytics-provider.tsx
'use client'
import { usePathname, useSearchParams } from 'next/navigation'
import { useEffect } from 'react'
import { analytics } from '@/analytics/client'

export function AnalyticsProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const searchParams = useSearchParams()

  useEffect(() => {
    analytics.page(pathname, {
      search: searchParams.toString(),
    })
  }, [pathname, searchParams])

  return <>{children}</>
}
```

---

## 5. 이벤트 트래킹 훅

```ts
// analytics/useTrack.ts
import { useCallback } from 'react'
import { analytics } from './client'

export function useTrack() {
  return useCallback(
    (event: string, properties?: Record<string, unknown>) => {
      analytics.track(event, properties)
    },
    []
  )
}

// 사용
function CheckoutButton({ orderId, amount }: Props) {
  const track = useTrack()

  function handleClick() {
    track('checkout_started', { orderId, amount })
    router.push('/checkout')
  }

  return <button onClick={handleClick}>결제하기</button>
}
```

---

## 6. 사용자 식별

```ts
// 로그인 시 identify
async function handleLogin(user: User) {
  await loginApi(user)

  analytics.identify(user.id, {
    email: user.email,
    name: user.name,
    plan: user.plan,
    createdAt: user.createdAt,
  })
}

// 로그아웃 시 reset
function handleLogout() {
  analytics.reset?.()  // 사용자 세션 초기화
}
```

---

## 7. 개인정보 고려사항

```ts
// GDPR/PIPA 준수
// 동의 없이는 트래킹 금지

function AnalyticsProvider({ children }: { children: ReactNode }) {
  const { hasConsent } = useCookieConsent()

  useEffect(() => {
    if (hasConsent) {
      analytics.enable()
    } else {
      analytics.disable()
    }
  }, [hasConsent])

  return <>{children}</>
}

// PII(개인식별정보) 트래킹 금지
// ❌ email, 전화번호, 주민번호 등을 이벤트 properties에 포함
track('user_signup', { email: user.email })  // ❌

// ✅ 익명화된 ID만 사용
track('user_signup', { userId: user.id, plan: user.plan })  // ✅
```

---

## 8. 안티패턴

- **모든 클릭을 트래킹**: 의미 있는 이벤트만
- **이벤트명 불일치**: `ButtonClick`, `button_click`, `btn_clicked` 혼용 → 컨벤션 통일
- **PII 포함**: 이메일, 전화번호 등 개인정보 이벤트에 포함 금지
- **동의 없는 트래킹**: GDPR 위반
- **클라이언트에서만 트래킹**: 서버 이벤트(결제 완료 등)는 서버에서 트래킹
