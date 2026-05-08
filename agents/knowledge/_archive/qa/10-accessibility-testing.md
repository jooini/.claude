# Accessibility Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/accessibility-testing

---

## 1. 접근성 테스트 기준

**WCAG 2.1 준수 레벨:**
- Level A: 최소 요구사항
- Level AA: 권장 (법적 요구사항인 경우 많음)
- Level AAA: 최고 수준

**4대 원칙 (POUR):**
- **P**erceivable: 인식 가능 (시각/청각 대안)
- **O**perable: 운용 가능 (키보드 접근)
- **U**nderstandable: 이해 가능 (명확한 언어)
- **R**obust: 견고함 (보조 기술 호환)

---

## 2. 자동화 테스트 — axe-core

```ts
// jest + axe
import { render } from '@testing-library/react'
import { axe, toHaveNoViolations } from 'jest-axe'
expect.extend(toHaveNoViolations)

describe('LoginForm 접근성', () => {
  it('WCAG AA 위반 없음', async () => {
    const { container } = render(<LoginForm onSubmit={jest.fn()} />)
    const results = await axe(container)
    expect(results).toHaveNoViolations()
  })

  it('에러 상태에서도 접근성 유지', async () => {
    const { container } = render(<LoginForm onSubmit={jest.fn()} error="로그인 실패" />)
    const results = await axe(container, {
      rules: {
        // 특정 규칙만 검사
        'color-contrast': { enabled: true },
        'label': { enabled: true },
        'aria-required-attr': { enabled: true },
      },
    })
    expect(results).toHaveNoViolations()
  })
})

// Playwright + axe
import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

test('홈페이지 접근성', async ({ page }) => {
  await page.goto('/')
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa'])
    .analyze()

  expect(results.violations).toEqual([])
})
```

---

## 3. 키보드 네비게이션 테스트

```ts
test('키보드만으로 로그인 완료', async ({ page }) => {
  await page.goto('/login')

  // Tab으로 이메일 필드로 이동
  await page.keyboard.press('Tab')
  await expect(page.getByLabel('이메일')).toBeFocused()
  await page.keyboard.type('user@example.com')

  // Tab으로 비밀번호 필드
  await page.keyboard.press('Tab')
  await expect(page.getByLabel('비밀번호')).toBeFocused()
  await page.keyboard.type('Password1!')

  // Tab으로 버튼, Enter로 제출
  await page.keyboard.press('Tab')
  await expect(page.getByRole('button', { name: '로그인' })).toBeFocused()
  await page.keyboard.press('Enter')

  await expect(page).toHaveURL('/dashboard')
})

test('모달 포커스 트랩', async ({ page }) => {
  await page.goto('/dashboard')
  await page.getByRole('button', { name: '설정 열기' }).click()

  // 모달 내에서만 Tab 이동
  const modal = page.getByRole('dialog')
  await expect(modal).toBeVisible()

  // 여러 번 Tab 해도 모달 밖으로 나가지 않음
  for (let i = 0; i < 10; i++) {
    await page.keyboard.press('Tab')
    const focusedElement = await page.evaluate(() => document.activeElement?.closest('[role="dialog"]'))
    expect(focusedElement).not.toBeNull()
  }

  // ESC로 닫기
  await page.keyboard.press('Escape')
  await expect(modal).not.toBeVisible()
})
```

---

## 4. 스크린 리더 테스트

```ts
// 수동 테스트 체크리스트 (자동화 불가)
// VoiceOver (macOS), NVDA/JAWS (Windows), TalkBack (Android)

const screenReaderChecklist = `
[ ] 페이지 제목이 명확하게 읽힘
[ ] 이미지 alt 텍스트 적절
[ ] 폼 레이블과 입력 필드 연결 확인
[ ] 에러 메시지 즉시 읽힘 (role="alert")
[ ] 로딩 상태 알림 (aria-live)
[ ] 버튼 목적이 텍스트로 전달됨
[ ] 링크 텍스트가 의미 있음 ("여기를 클릭" 금지)
[ ] 데이터 테이블 헤더 연결 확인
`

// ARIA 속성 테스트
test('에러 메시지가 스크린 리더에 전달됨', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: '로그인' }).click()

  const errorAlert = page.getByRole('alert')
  await expect(errorAlert).toBeVisible()
  await expect(errorAlert).toHaveAttribute('aria-live', 'polite')
})
```

---

## 5. 색상 대비 테스트

```ts
// 자동화: axe가 대비율 검사
// 수동 확인: Chrome DevTools > Accessibility > Color contrast

test('색상 대비 WCAG AA 준수', async ({ page }) => {
  await page.goto('/')
  const results = await new AxeBuilder({ page })
    .withRules(['color-contrast'])
    .analyze()

  if (results.violations.length > 0) {
    console.table(results.violations.map(v => ({
      element: v.nodes[0]?.html,
      impact: v.impact,
      description: v.description,
    })))
  }

  expect(results.violations).toHaveLength(0)
})
```

---

## 6. 접근성 테스트 워크플로우

```
1. 개발 중 — jest-axe로 컴포넌트 단위 자동 검사
2. PR — CI에서 자동 axe 스캔
3. QA — Playwright + axe-core로 주요 페이지 검사
4. 릴리스 전 — 수동 키보드/스크린 리더 테스트
5. 정기 감사 — 전체 사이트 접근성 감사 (분기)
```

---

## 7. 안티패턴

- **자동화만 믿기**: axe가 30~40%만 탐지 → 수동 보완 필수
- **개발 완료 후 접근성 추가**: 처음부터 고려해야 비용 낮음
- **색상만 의존한 정보 전달**: 색맹 사용자 고려
- **Focus 스타일 제거**: `outline: none` → 키보드 사용자 불가
- **접근성 위반을 P4(낮음)로 처리**: Legal risk 고려
