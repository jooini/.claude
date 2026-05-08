# Test Automation Architecture

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/test-automation-architecture

---

## 1. 자동화 아키텍처 목표

- **유지보수성**: 코드 변경 시 테스트 수정 최소화
- **재사용성**: 공통 로직 재사용
- **가독성**: 비개발자도 테스트 의도를 이해
- **안정성**: Flaky Test 최소화

---

## 2. 레이어드 아키텍처

```
테스트 레이어       — spec 파일, 테스트 시나리오
     ↓
Page/API Object    — UI 상호작용, API 호출 추상화
     ↓
공통 유틸/헬퍼      — 인증, 데이터 생성, 공통 액션
     ↓
설정/환경           — 환경 변수, 베이스 설정
```

---

## 3. 폴더 구조

```
tests/
├── e2e/
│   ├── specs/           # 테스트 파일
│   │   ├── auth.spec.ts
│   │   ├── checkout.spec.ts
│   │   └── dashboard.spec.ts
│   ├── pages/           # Page Object Model
│   │   ├── base.page.ts
│   │   ├── login.page.ts
│   │   └── checkout.page.ts
│   ├── fixtures/        # 테스트 데이터/픽스처
│   │   ├── users.ts
│   │   └── products.ts
│   └── helpers/         # 공통 유틸
│       ├── auth.helper.ts
│       └── db.helper.ts
│
├── api/
│   ├── specs/
│   ├── clients/         # API 클라이언트
│   └── schemas/         # 응답 스키마
│
├── unit/
│   └── specs/
│
└── config/
    ├── playwright.config.ts
    └── jest.config.ts
```

---

## 4. Base Page Object

```ts
// e2e/pages/base.page.ts
import { Page, Locator, expect } from '@playwright/test'

export abstract class BasePage {
  protected readonly page: Page

  constructor(page: Page) {
    this.page = page
  }

  // 공통 메서드
  async goto(path: string) {
    await this.page.goto(path)
    await this.waitForPageLoad()
  }

  async waitForPageLoad() {
    await this.page.waitForLoadState('networkidle')
  }

  async getToast(): Promise<string> {
    const toast = this.page.locator('[role="status"]')
    await expect(toast).toBeVisible()
    return toast.textContent() ?? ''
  }

  async expectUrl(pattern: string | RegExp) {
    await expect(this.page).toHaveURL(pattern)
  }

  async screenshot(name: string) {
    await this.page.screenshot({ path: `screenshots/${name}.png` })
  }
}

// e2e/pages/login.page.ts
export class LoginPage extends BasePage {
  private get emailInput() { return this.page.getByLabel('이메일') }
  private get passwordInput() { return this.page.getByLabel('비밀번호') }
  private get submitButton() { return this.page.getByRole('button', { name: '로그인' }) }
  private get errorAlert() { return this.page.getByRole('alert') }

  async goto() {
    await super.goto('/login')
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email)
    await this.passwordInput.fill(password)
    await this.submitButton.click()
  }

  async expectLoginError(message: string) {
    await expect(this.errorAlert).toContainText(message)
  }
}
```

---

## 5. 테스트 픽스처

```ts
// e2e/fixtures/index.ts
import { test as base, Page } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { DashboardPage } from '../pages/dashboard.page'

type Pages = {
  loginPage: LoginPage
  dashboardPage: DashboardPage
}

type Auth = {
  authenticatedPage: Page
}

// 모든 테스트에서 재사용할 픽스처
export const test = base.extend<Pages & Auth>({
  loginPage: async ({ page }, use) => {
    await use(new LoginPage(page))
  },

  dashboardPage: async ({ page }, use) => {
    await use(new DashboardPage(page))
  },

  authenticatedPage: async ({ page }, use) => {
    // API로 토큰 발급 후 localStorage 설정 (로그인 페이지 생략)
    const response = await page.request.post('/api/auth/login', {
      data: { email: 'user@test.com', password: 'TestPass1!' },
    })
    const { data } = await response.json()

    await page.goto('/')
    await page.evaluate(token => {
      localStorage.setItem('access_token', token)
    }, data.accessToken)

    await use(page)
  },
})

export { expect } from '@playwright/test'

// 사용
import { test, expect } from '../fixtures'

test('대시보드 접근', async ({ authenticatedPage, dashboardPage }) => {
  await dashboardPage.goto()
  await expect(authenticatedPage.getByText('대시보드')).toBeVisible()
})
```

---

## 6. 데이터 관리 전략

```ts
// 테스트 데이터 팩토리
export class UserFactory {
  static create(override: Partial<CreateUserDto> = {}): CreateUserDto {
    return {
      email: `test-${Date.now()}@example.com`,
      name: '테스트유저',
      password: 'TestPass1!',
      ...override,
    }
  }

  static createAdmin(override: Partial<CreateUserDto> = {}): CreateUserDto {
    return this.create({ role: 'admin', ...override })
  }
}

// DB 헬퍼
export class DbHelper {
  static async createUser(override = {}) {
    return prisma.user.create({ data: UserFactory.create(override) })
  }

  static async cleanup(...tables: string[]) {
    for (const table of tables) {
      await prisma.$executeRawUnsafe(`TRUNCATE ${table} CASCADE`)
    }
  }
}
```

---

## 7. 리포팅

```ts
// playwright.config.ts
reporter: [
  ['html', { open: 'never' }],                    // HTML 리포트
  ['junit', { outputFile: 'results/junit.xml' }], // CI 연동
  ['allure-playwright'],                           // Allure 리포트
]

// 테스트 결과 슬랙 알림
// .github/workflows/e2e.yml
- name: Notify Slack on Failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "E2E 테스트 실패 :x:\n${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
      }
```

---

## 8. 안티패턴

- **테스트에 비즈니스 로직**: 테스트는 동작 검증, 로직은 프로덕션 코드에
- **하드코딩된 대기 시간**: `sleep(3000)` → 명시적 대기
- **과도한 Page Object 추상화**: 단순한 케이스까지 추상화
- **테스트 코드 리뷰 안 함**: 프로덕션 코드와 동일하게 리뷰
- **CI 없는 자동화**: 로컬에서만 실행 → 가치 반감
