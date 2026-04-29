# Visual Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/visual-testing

---

## 1. 비주얼 테스트란

UI 렌더링 결과를 스크린샷으로 비교해 시각적 회귀(regression)를 탐지.
기능은 정상인데 UI가 깨진 것을 자동으로 감지.

---

## 2. Playwright 스크린샷 비교

```ts
// playwright.config.ts
export default defineConfig({
  expect: {
    toHaveScreenshot: {
      maxDiffPixels: 50,        // 허용 픽셀 차이
      threshold: 0.1,           // 색상 차이 허용치 (0~1)
      animations: 'disabled',   // 애니메이션 비활성화
    },
  },
})

// visual.spec.ts
test('버튼 컴포넌트 — 모든 variant', async ({ page }) => {
  await page.goto('/storybook/button')

  // 전체 페이지 스크린샷
  await expect(page).toHaveScreenshot('button-variants.png')
})

test('대시보드 레이아웃', async ({ page }) => {
  await page.goto('/dashboard')
  await page.waitForLoadState('networkidle')  // 모든 리소스 로딩 완료 후

  // 특정 컴포넌트만 캡처
  const chart = page.locator('[data-testid="revenue-chart"]')
  await expect(chart).toHaveScreenshot('revenue-chart.png')
})

// 다크 모드
test('다크 모드 레이아웃', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' })
  await page.goto('/dashboard')
  await expect(page).toHaveScreenshot('dashboard-dark.png')
})
```

---

## 3. Storybook + Chromatic

```ts
// .storybook/main.ts
const config = {
  stories: ['../src/**/*.stories.tsx'],
  addons: ['@storybook/addon-a11y', '@storybook/addon-viewport'],
}

// Button.stories.tsx
export default {
  title: 'UI/Button',
  component: Button,
  parameters: {
    chromatic: { delay: 300 },  // 애니메이션 대기
  },
}

export const AllVariants = {
  render: () => (
    <div className="flex gap-4 p-8">
      <Button variant="default">Default</Button>
      <Button variant="destructive">Destructive</Button>
      <Button variant="outline">Outline</Button>
      <Button isLoading>Loading</Button>
      <Button disabled>Disabled</Button>
    </div>
  ),
}
```

```yaml
# CI에서 Chromatic 실행
- name: Publish to Chromatic
  uses: chromaui/action@v1
  with:
    projectToken: ${{ secrets.CHROMATIC_PROJECT_TOKEN }}
    exitZeroOnChanges: true  # 변경 있어도 CI 실패 안 함 (리뷰 용도)
```

---

## 4. Percy (BrowserStack)

```ts
import percySnapshot from '@percy/playwright'

test('홈페이지 비주얼', async ({ page }) => {
  await page.goto('/')
  await page.waitForLoadState('networkidle')
  await percySnapshot(page, 'Homepage')
})

test('모바일 뷰', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  await page.goto('/')
  await percySnapshot(page, 'Homepage Mobile')
})
```

---

## 5. 비주얼 테스트 전략

```
컴포넌트 레벨 (Storybook + Chromatic)
  - 모든 UI 컴포넌트 variant
  - 인터랙션 상태 (hover, focus, active)
  - 로딩/에러 상태

페이지 레벨 (Playwright)
  - 주요 페이지 레이아웃
  - 반응형 (데스크탑, 태블릿, 모바일)
  - 다크/라이트 모드

크로스 브라우저 (Chromatic/Percy)
  - Chrome, Firefox, Safari 비교
```

---

## 6. 베이스라인 관리

```bash
# 의도적 변경 시 베이스라인 업데이트
npx playwright test --update-snapshots

# 특정 테스트만 업데이트
npx playwright test visual.spec.ts --update-snapshots
```

**베이스라인 업데이트 원칙:**
- UI 변경 배포 시 PR에서 스크린샷 diff 리뷰
- 의도한 변경이면 approve + 베이스라인 업데이트
- 의도치 않은 변경이면 버그로 등록

---

## 7. 안티패턴

- **전체 페이지 스크린샷만**: 컴포넌트 레벨 세분화 필요
- **동적 콘텐츠 포함**: 날짜, 사용자명 등 마스킹 또는 고정값 사용
- **베이스라인 없이 실행**: 최초 실행 시 베이스라인 생성 필수
- **모든 픽셀 차이를 버그로**: maxDiffPixels 적절히 설정
- **CI에서 폰트 미설치**: 로컬과 다른 렌더링 → Docker 이미지 일관성
