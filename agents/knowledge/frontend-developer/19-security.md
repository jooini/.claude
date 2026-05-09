# Security

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/security

---

## 1. XSS (Cross-Site Scripting)

사용자 입력을 HTML로 렌더링할 때 스크립트 삽입.

```tsx
// ✅ React는 기본적으로 XSS 방어 — JSX가 자동 이스케이프
const userInput = '<script>alert("xss")</script>'
<div>{userInput}</div>  // → &lt;script&gt;... 로 이스케이프

// ❌ dangerouslySetInnerHTML — XSS 위험
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// dangerouslySetInnerHTML 불가피할 때 — DOMPurify로 sanitize
import DOMPurify from 'dompurify'
const clean = DOMPurify.sanitize(userInput, {
  ALLOWED_TAGS: ['b', 'i', 'em', 'strong', 'a'],
  ALLOWED_ATTR: ['href'],
})
<div dangerouslySetInnerHTML={{ __html: clean }} />
```

---

## 2. CSRF (Cross-Site Request Forgery)

다른 사이트에서 사용자 권한으로 요청 위조.

```ts
// Next.js Server Actions — 자동으로 CSRF 방어
// (Origin 헤더 검증)

// API Route에서 수동 방어
// next-auth의 CSRF 토큰 활용
import { getCsrfToken } from 'next-auth/react'

async function submitForm() {
  const csrfToken = await getCsrfToken()
  await fetch('/api/update', {
    method: 'POST',
    headers: { 'X-CSRF-Token': csrfToken },
    body: JSON.stringify(data),
  })
}
```

---

## 3. 인증 토큰 저장

```ts
// ❌ localStorage — XSS에 취약 (JS로 접근 가능)
localStorage.setItem('token', accessToken)

// ❌ sessionStorage — 마찬가지로 취약
sessionStorage.setItem('token', accessToken)

// ✅ HttpOnly Cookie — JS 접근 불가 (서버에서 설정)
// 서버에서:
res.setHeader('Set-Cookie', [
  `token=${accessToken}; HttpOnly; Secure; SameSite=Strict; Path=/`,
])

// Next.js cookies() API
import { cookies } from 'next/headers'
cookies().set('token', accessToken, {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'strict',
  maxAge: 60 * 60 * 24 * 7,  // 7일
})
```

---

## 4. 환경 변수

```ts
// .env.local
DATABASE_URL=postgresql://...          # 서버 전용
OPENAI_API_KEY=sk-...                  # 서버 전용
NEXT_PUBLIC_API_URL=https://api...     # 클라이언트 노출 가능

// ❌ NEXT_PUBLIC_ 붙은 변수는 클라이언트 번들에 포함
// API 키, DB URL 등 민감 정보는 절대 NEXT_PUBLIC_ 사용 금지

// Server Component에서만 사용
const apiKey = process.env.OPENAI_API_KEY  // 서버에서만 접근

// 환경변수 검증 (빌드 타임)
import { z } from 'zod'

const envSchema = z.object({
  DATABASE_URL: z.string().url(),
  OPENAI_API_KEY: z.string().startsWith('sk-'),
  NEXT_PUBLIC_API_URL: z.string().url(),
})

export const env = envSchema.parse(process.env)
```

---

## 5. Content Security Policy (CSP)

```ts
// next.config.ts
const cspHeader = `
  default-src 'self';
  script-src 'self' 'unsafe-eval' 'unsafe-inline';
  style-src 'self' 'unsafe-inline';
  img-src 'self' blob: data: https:;
  font-src 'self';
  connect-src 'self' https://api.example.com;
  frame-ancestors 'none';
`

export default {
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'Content-Security-Policy', value: cspHeader.replace(/\n/g, '') },
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
        ],
      },
    ]
  },
}
```

---

## 6. 입력 검증 및 파라미터 처리

```ts
// URL 파라미터 신뢰 금지 — 항상 검증
// app/users/[id]/page.tsx
import { z } from 'zod'

const paramsSchema = z.object({
  id: z.string().uuid(),
})

export default async function UserPage({ params }: Props) {
  const parsed = paramsSchema.safeParse(params)
  if (!parsed.success) notFound()

  const user = await getUser(parsed.data.id)
  // ...
}

// 외부 URL 리다이렉트 방어 (Open Redirect)
function safeRedirect(url: string, fallback = '/') {
  // 절대 URL이면 내부 경로로만 허용
  if (url.startsWith('http') || url.startsWith('//')) return fallback
  return url
}
```

---

## 7. 의존성 보안

```bash
# 취약점 감사
npm audit
npm audit fix

# 자동화 — GitHub Dependabot 또는 Snyk
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 10
```

---

## 8. 안티패턴

- **`eval()` 사용**: 코드 인젝션 위험
- **사용자 입력을 URL에 직접 사용**: encodeURIComponent로 인코딩
- **에러 메시지에 내부 정보 노출**: 스택 트레이스, DB 쿼리 등
- **HTTP에서 민감 데이터 전송**: HTTPS 강제
- **패키지 버전 고정 안 함**: `^`, `~` 대신 lockfile 관리
