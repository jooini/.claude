# E2E Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/e2e-testing

---

## 1. E2E 테스트 원칙

실제 사용자 관점에서 전체 시스템 플로우 검증. 느리고 비싸므로 핵심 시나리오만.

**E2E 테스트 대상:**
- 핵심 Happy Path (회원가입, 로그인, 결제)
- 비즈니스 크리티컬 플로우
- 주요 사용자 여정

**E2E 테스트 제외:**
- 단위/통합 테스트로 커버 가능한 것
- 모든 에러 케이스 (통합 테스트로)
- 순수 UI 스타일 검증 (Visual 테스트로)

---

## 2. Playwright 기본 설정

```ts
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html'],
    ['junit', { outputFile: 'test-results/junit.xml' }],
  ],
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile',   use: { ...devices['iPhone 13'] } },
  ],
})
```

---

## 3. Page Object Model (POM)

테스트와 UI 상호작용을 분리해 유지보수성 향상.

```ts
// e2e/pages/login.page.ts
import { Page, Locator, expect } from '@playwright/test'

export class LoginPage {
  readonly emailInput: Locator
  readonly passwordInput: Locator
  readonly submitButton: Locator
  readonly errorMessage: Locator

  constructor(private readonly page: Page) {
    this.emailInput    = page.getByLabel('이메일')
    this.passwordInput = page.getByLabel('비밀번호')
    this.submitButton  = page.getByRole('button', { name: '로그인' })
    this.errorMessage  = page.getByRole('alert')
  }

  async goto() {
    await this.page.goto('/login')
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email)
    await this.passwordInput.fill(password)
    await this.submitButton.click()
  }

  async expectError(message: string) {
    await expect(this.errorMessage).toContainText(message)
  }
}

// e2e/pages/checkout.page.ts
export class CheckoutPage {
  constructor(private readonly page: Page) {}

  async fillCardInfo(cardNumber: string, expiry: string, cvc: string) {
    await this.page.getByLabel('카드 번호').fill(cardNumber)
    await this.page.getByLabel('유효기간').fill(expiry)
    await this.page.getByLabel('CVC').fill(cvc)
  }

  async submit() {
    await this.page.getByRole('button', { name: '결제하기' }).click()
  }

  async expectSuccess() {
    await expect(this.page).toHaveURL('/orders/complete')
    await expect(this.page.getByText('주문이 완료되었습니다')).toBeVisible()
  }
}
```

---

## 4. 핵심 시나리오 테스트

```ts
// e2e/auth.spec.ts
import { test, expect } from '@playwright/test'
import { LoginPage } from './pages/login.page'

test.describe('인증', () => {
  test('정상 로그인 후 대시보드 이동', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('user@example.com', 'Password1!')

    await expect(page).toHaveURL('/dashboard')
    await expect(page.getByText('홍길동님 환영합니다')).toBeVisible()
  })

  test('잘못된 비밀번호 — 에러 메시지', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('user@example.com', 'wrongpassword')

    await loginPage.expectError('이메일 또는 비밀번호가 올바르지 않습니다')
    await expect(page).toHaveURL('/login')  // 페이지 이동 없음
  })
})

// e2e/purchase.spec.ts
test.describe('구매 플로우', () => {
  test.beforeEach(async ({ page }) => {
    // 공통 로그인
    await page.goto('/login')
    await page.getByLabel('이메일').fill('buyer@example.com')
    await page.getByLabel('비밀번호').fill('Password1!')
    await page.getByRole('button', { name: '로그인' }).click()
    await expect(page).toHaveURL('/dashboard')
  })

  test('상품 검색 → 장바구니 → 결제 완료', async ({ page }) => {
    // 검색
    await page.getByPlaceholder('상품 검색').fill('노트북')
    await page.keyboard.press('Enter')
    await expect(page.getByTestId('search-results')).toBeVisible()

    // 상품 선택
    await page.getByTestId('product-card').first().click()
    await expect(page).toHaveURL(/\/products\//)

    // 장바구니 추가
    await page.getByRole('button', { name: '장바구니 담기' }).click()
    await expect(page.getByText('장바구니에 추가되었습니다')).toBeVisible()

    // 결제
    await page.goto('/cart')
    await page.getByRole('button', { name: '주문하기' }).click()

    const checkoutPage = new CheckoutPage(page)
    await checkoutPage.fillCardInfo('4242424242424242', '12/26', '123')
    await checkoutPage.submit()
    await checkoutPage.expectSuccess()
  })
})
```

---

## 5. 테스트 데이터 관리

```ts
// e2e/fixtures/user.fixture.ts
import { test as base } from '@playwright/test'

type Fixtures = {
  loggedInPage: Page
  testUser: { email: string; id: string }
}

export const test = base.extend<Fixtures>({
  testUser: async ({ request }, use) => {
    // API로 테스트 유저 생성
    const res = await request.post('/api/test/users', {
      data: { email: `test-${Date.now()}@example.com`, name: '테스트유저' },
    })
    const user = await res.json()

    await use(user)

    // 테스트 후 삭제
    await request.delete(`/api/test/users/${user.id}`)
  },

  loggedInPage: async ({ page, testUser }, use) => {
    await page.goto('/login')
    await page.getByLabel('이메일').fill(testUser.email)
    await page.getByLabel('비밀번호').fill('TestPass1!')
    await page.getByRole('button', { name: '로그인' }).click()
    await page.waitForURL('/dashboard')
    await use(page)
  },
})
```

---

## 6. CI 통합

```yaml
# .github/workflows/e2e.yml
- name: Install Playwright
  run: npx playwright install --with-deps chromium

- name: Run E2E Tests
  run: npx playwright test
  env:
    BASE_URL: ${{ secrets.STAGING_URL }}

- name: Upload Test Report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: playwright-report
    path: playwright-report/
    retention-days: 7
```

---

## 7. 안티패턴

- **E2E로 모든 것 커버**: 단위/통합 테스트로 처리 가능한 것은 그쪽에
- **하드코딩된 대기**: `await page.waitForTimeout(3000)` → `await expect(locator).toBeVisible()`
- **취약한 선택자**: `page.locator('.btn-3rd > span')` → `getByRole`, `getByLabel`
- **테스트 간 상태 공유**: 각 테스트는 독립적으로 실행 가능해야
- **Flaky Test 무시**: 비결정적 실패는 즉시 격리 후 수정
