# Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/testing

---

## 1. 테스트 피라미드

```
        E2E (적게)
       /          \
    Integration (중간)
   /                \
  Unit (많이, 빠르게)
```

- **Unit**: 함수, 훅, 유틸리티 단위. 빠르고 많이
- **Integration**: 컴포넌트 + 의존성 조합. 사용자 관점
- **E2E**: 실제 브라우저에서 전체 플로우. 느리고 핵심만

---

## 2. 도구 스택

| 역할 | 도구 |
|------|------|
| 테스트 러너 | Vitest (또는 Jest) |
| 컴포넌트 테스트 | Testing Library |
| E2E | Playwright |
| 모킹 | MSW (API), vi.mock (모듈) |

---

## 3. Unit Test — 유틸/훅

```ts
// utils/format.test.ts
import { describe, it, expect } from 'vitest'
import { formatPrice, formatDate } from './format'

describe('formatPrice', () => {
  it('숫자를 원화 형식으로 변환', () => {
    expect(formatPrice(1000)).toBe('1,000원')
    expect(formatPrice(0)).toBe('0원')
  })

  it('음수 처리', () => {
    expect(formatPrice(-500)).toBe('-500원')
  })
})
```

```ts
// hooks/useCounter.test.ts
import { renderHook, act } from '@testing-library/react'
import { useCounter } from './useCounter'

describe('useCounter', () => {
  it('초기값 설정', () => {
    const { result } = renderHook(() => useCounter(5))
    expect(result.current.count).toBe(5)
  })

  it('increment', () => {
    const { result } = renderHook(() => useCounter(0))
    act(() => result.current.increment())
    expect(result.current.count).toBe(1)
  })
})
```

---

## 4. Integration Test — 컴포넌트

Testing Library의 핵심 원칙: **사용자가 보고 상호작용하는 방식으로 테스트**.

```tsx
// components/LoginForm.test.tsx
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { LoginForm } from './LoginForm'

describe('LoginForm', () => {
  it('유효성 에러 표시', async () => {
    const user = userEvent.setup()
    render(<LoginForm onSubmit={vi.fn()} />)

    // 빈 폼 제출
    await user.click(screen.getByRole('button', { name: '로그인' }))

    expect(screen.getByText('이메일을 입력하세요')).toBeInTheDocument()
  })

  it('정상 제출', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn()
    render(<LoginForm onSubmit={onSubmit} />)

    await user.type(screen.getByLabelText('이메일'), 'test@example.com')
    await user.type(screen.getByLabelText('비밀번호'), 'password123')
    await user.click(screen.getByRole('button', { name: '로그인' }))

    await waitFor(() => {
      expect(onSubmit).toHaveBeenCalledWith({
        email: 'test@example.com',
        password: 'password123',
      })
    })
  })
})
```

### 쿼리 우선순위

```ts
// 1순위 — 접근성 기반 (권장)
screen.getByRole('button', { name: '제출' })
screen.getByLabelText('이메일')
screen.getByPlaceholderText('검색어를 입력하세요')

// 2순위 — 시맨틱
screen.getByText('안녕하세요')
screen.getByAltText('프로필 이미지')

// 3순위 — 테스트 전용 (불가피할 때만)
screen.getByTestId('submit-button')

// ❌ 피해야 할 것
document.querySelector('.submit-btn')  // 구현 세부사항에 결합
```

---

## 5. API 모킹 — MSW

```ts
// mocks/handlers.ts
import { http, HttpResponse } from 'msw'

export const handlers = [
  http.get('/api/users', () => {
    return HttpResponse.json([
      { id: '1', name: 'Alice' },
      { id: '2', name: 'Bob' },
    ])
  }),

  http.post('/api/users', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json({ id: '3', ...body }, { status: 201 })
  }),

  // 에러 시나리오
  http.get('/api/users/:id', ({ params }) => {
    if (params.id === '999') {
      return HttpResponse.json({ message: 'Not Found' }, { status: 404 })
    }
    return HttpResponse.json({ id: params.id, name: 'Test User' })
  }),
]

// mocks/server.ts
import { setupServer } from 'msw/node'
export const server = setupServer(...handlers)

// vitest.setup.ts
import { server } from './mocks/server'
beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
```

---

## 6. E2E — Playwright

```ts
// e2e/auth.spec.ts
import { test, expect } from '@playwright/test'

test.describe('로그인', () => {
  test('정상 로그인 후 대시보드 이동', async ({ page }) => {
    await page.goto('/login')

    await page.getByLabel('이메일').fill('user@example.com')
    await page.getByLabel('비밀번호').fill('password123')
    await page.getByRole('button', { name: '로그인' }).click()

    await expect(page).toHaveURL('/dashboard')
    await expect(page.getByText('환영합니다')).toBeVisible()
  })

  test('잘못된 비밀번호 에러 표시', async ({ page }) => {
    await page.goto('/login')

    await page.getByLabel('이메일').fill('user@example.com')
    await page.getByLabel('비밀번호').fill('wrongpassword')
    await page.getByRole('button', { name: '로그인' }).click()

    await expect(page.getByText('이메일 또는 비밀번호가 틀렸습니다')).toBeVisible()
  })
})
```

---

## 7. 커버리지 설정

```ts
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 70,
      },
      exclude: [
        'node_modules/',
        '**/*.stories.tsx',
        '**/mocks/**',
      ],
    },
  },
})
```

---

## 8. 안티패턴

- **구현 세부사항 테스트**: state, ref 직접 테스트 → 사용자 관점으로
- **스냅샷 테스트 남발**: 변경마다 업데이트 → 의미 없는 테스트
- **테스트 간 의존성**: 각 테스트는 독립적으로 실행 가능해야
- **실제 API 호출**: 테스트에서 네트워크 의존 → MSW로 모킹
- **E2E로 유닛 대체**: 느린 E2E보다 빠른 유닛 테스트 우선
