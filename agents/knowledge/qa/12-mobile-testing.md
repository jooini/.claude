# Mobile Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/mobile-testing

---

## 1. 모바일 테스트 범위

```
기능 테스트     — 앱 기능 정상 동작
UI/UX 테스트   — 레이아웃, 터치 인터랙션
성능 테스트     — 시작 시간, 메모리, 배터리
네트워크 테스트 — 오프라인, 느린 연결
기기 호환성     — OS 버전, 화면 크기
접근성 테스트   — 스크린 리더, 큰 텍스트
```

---

## 2. Playwright 모바일 에뮬레이션

```ts
// playwright.config.ts
projects: [
  { name: 'desktop',       use: { ...devices['Desktop Chrome'] } },
  { name: 'mobile-chrome', use: { ...devices['Pixel 5'] } },
  { name: 'mobile-safari', use: { ...devices['iPhone 13'] } },
  { name: 'tablet',        use: { ...devices['iPad Pro'] } },
]

// 모바일 전용 테스트
test('모바일 네비게이션 — 햄버거 메뉴', async ({ page }) => {
  await page.goto('/')

  // 모바일에서 햄버거 메뉴 표시 확인
  const hamburger = page.getByRole('button', { name: '메뉴 열기' })
  await expect(hamburger).toBeVisible()

  // 데스크탑 네비게이션은 숨겨져야 함
  await expect(page.getByRole('navigation').first()).not.toBeVisible()

  // 햄버거 클릭 → 메뉴 열림
  await hamburger.click()
  await expect(page.getByRole('navigation').first()).toBeVisible()
})

test('터치 스와이프 — 이미지 캐러셀', async ({ page }) => {
  await page.goto('/products/1')
  const carousel = page.locator('[data-testid="image-carousel"]')

  // 스와이프 시뮬레이션
  const box = await carousel.boundingBox()!
  await page.touchscreen.tap(box!.x + box!.width * 0.8, box!.y + box!.height / 2)

  // 다음 이미지로 전환 확인
  await expect(page.locator('[data-testid="image-dot-1"]')).toHaveClass(/active/)
})
```

---

## 3. Appium (네이티브 앱)

```ts
// Flutter 앱 테스트 (Appium + Flutter Driver)
import { remote } from 'webdriverio'

describe('Flutter 앱 — 로그인', () => {
  let driver: WebdriverIO.Browser

  before(async () => {
    driver = await remote({
      capabilities: {
        platformName: 'Android',
        'appium:deviceName': 'Pixel_6_API_33',
        'appium:app': './app/release/app-release.apk',
        'appium:automationName': 'Flutter',
      },
    })
  })

  after(() => driver.deleteSession())

  it('로그인 성공', async () => {
    const emailField = await driver.$('~email_input')  // accessibilityId
    await emailField.setValue('user@test.com')

    const passwordField = await driver.$('~password_input')
    await passwordField.setValue('Password1!')

    const loginButton = await driver.$('~login_button')
    await loginButton.click()

    const welcomeText = await driver.$('~welcome_message')
    await expect(welcomeText).toBeDisplayed()
  })
})
```

---

## 4. 네트워크 조건 테스트

```ts
// Playwright — 네트워크 쓰로틀링
test('느린 네트워크에서 로딩 상태 표시', async ({ page, context }) => {
  // 3G 네트워크 시뮬레이션
  await context.route('**/*', async route => {
    await new Promise(resolve => setTimeout(resolve, 1000))  // 1초 지연
    await route.continue()
  })

  await page.goto('/products')

  // 로딩 스피너 표시 확인
  await expect(page.getByTestId('loading-spinner')).toBeVisible()

  // 로딩 완료 후 사라짐
  await expect(page.getByTestId('loading-spinner')).not.toBeVisible({ timeout: 10000 })
})

test('오프라인 상태 처리', async ({ page, context }) => {
  await page.goto('/dashboard')  // 먼저 온라인 상태에서 접근

  // 오프라인 전환
  await context.setOffline(true)

  await page.reload()
  await expect(page.getByText('인터넷 연결을 확인해주세요')).toBeVisible()

  // 온라인 복구
  await context.setOffline(false)
  await page.getByRole('button', { name: '재시도' }).click()
  await expect(page.getByTestId('dashboard-content')).toBeVisible()
})
```

---

## 5. 반응형 디자인 테스트

```ts
const breakpoints = [
  { name: 'mobile',  width: 375,  height: 812  },
  { name: 'tablet',  width: 768,  height: 1024 },
  { name: 'desktop', width: 1440, height: 900  },
]

for (const bp of breakpoints) {
  test(`레이아웃 — ${bp.name} (${bp.width}px)`, async ({ page }) => {
    await page.setViewportSize({ width: bp.width, height: bp.height })
    await page.goto('/')

    // 가로 스크롤 없음 확인
    const hasHorizontalScroll = await page.evaluate(() =>
      document.documentElement.scrollWidth > document.documentElement.clientWidth
    )
    expect(hasHorizontalScroll).toBe(false)

    await expect(page).toHaveScreenshot(`home-${bp.name}.png`)
  })
}
```

---

## 6. 디바이스 팜 (BrowserStack / Sauce Labs)

```yaml
# .github/workflows/mobile-e2e.yml
- name: Run on BrowserStack
  env:
    BROWSERSTACK_USERNAME: ${{ secrets.BS_USERNAME }}
    BROWSERSTACK_ACCESS_KEY: ${{ secrets.BS_ACCESS_KEY }}
  run: |
    npx playwright test \
      --config=playwright.browserstack.config.ts \
      --project="iPhone 14" \
      --project="Samsung Galaxy S23"
```

---

## 7. 안티패턴

- **데스크탑만 테스트**: 모바일 트래픽이 50%+ 인 경우 많음
- **에뮬레이터만 테스트**: 실 기기와 다를 수 있음 (특히 Safari)
- **터치 인터랙션 무시**: 클릭 이벤트와 터치 이벤트 다름
- **온라인 환경만 테스트**: 지하철, 엘리베이터 등 단절 상황
- **가로 모드 미테스트**: 영상, 게임 앱에서 중요
