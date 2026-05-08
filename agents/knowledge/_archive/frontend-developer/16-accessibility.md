# Accessibility

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/accessibility

---

## 1. 왜 접근성인가

- 법적 요건 (ADA, EAA 등)
- SEO 향상 — 시맨틱 마크업 = 검색 엔진 이해 향상
- 사용성 향상 — 접근성 좋은 UI는 모든 사용자에게 더 좋음
- 기준: WCAG 2.1 AA 준수

---

## 2. 시맨틱 HTML

```tsx
// ❌ div 남용
<div onClick={handleSubmit}>제출</div>
<div class="nav">
  <div onClick={() => navigate('/')}>홈</div>
</div>

// ✅ 시맨틱 태그
<button onClick={handleSubmit}>제출</button>
<nav>
  <a href="/">홈</a>
</nav>

// 올바른 헤딩 계층
<h1>페이지 제목</h1>
  <h2>섹션 제목</h2>
    <h3>서브섹션</h3>
// h1은 페이지당 하나, 계층 건너뛰지 않기
```

---

## 3. ARIA 속성

시맨틱 HTML로 표현 못하는 경우에만 사용 (ARIA > 없음, 시맨틱 HTML >> ARIA).

```tsx
// 레이블 연결
<label htmlFor="email">이메일</label>
<input id="email" type="email" />

// 또는 aria-label (레이블 텍스트 불가 시)
<button aria-label="검색">
  <SearchIcon />
</button>

// 에러 상태
<input
  aria-invalid={!!error}
  aria-describedby={error ? 'email-error' : undefined}
/>
{error && <span id="email-error" role="alert">{error}</span>}

// 확장/축소
<button aria-expanded={isOpen} aria-controls="menu">
  메뉴
</button>
<ul id="menu" hidden={!isOpen}>...</ul>

// 로딩 상태
<button aria-busy={isLoading} disabled={isLoading}>
  {isLoading ? '처리 중...' : '제출'}
</button>

// 시각적으로 숨기되 스크린 리더에는 노출
<span className="sr-only">현재 페이지:</span>
```

---

## 4. 키보드 네비게이션

```tsx
// 포커스 순서 — tabIndex
// tabIndex="0": 자연스러운 탭 순서에 포함
// tabIndex="-1": 탭 순서에서 제외, 프로그래매틱 포커스만 가능
// tabIndex="1+" ❌: 사용 금지 (순서 꼬임)

// 포커스 트랩 — 모달
function Modal({ isOpen, onClose, children }: ModalProps) {
  const firstFocusableRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (isOpen) {
      firstFocusableRef.current?.focus()  // 모달 열릴 때 첫 요소로
    }
  }, [isOpen])

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Escape') onClose()
  }

  return isOpen ? (
    <div role="dialog" aria-modal="true" onKeyDown={handleKeyDown}>
      <button ref={firstFocusableRef} onClick={onClose}>닫기</button>
      {children}
    </div>
  ) : null
}

// 커스텀 드롭다운 키보드 지원
function Dropdown() {
  function handleKeyDown(e: React.KeyboardEvent) {
    switch (e.key) {
      case 'ArrowDown': focusNext(); break
      case 'ArrowUp':   focusPrev(); break
      case 'Enter':
      case ' ':         selectCurrent(); break
      case 'Escape':    close(); break
      case 'Home':      focusFirst(); break
      case 'End':       focusLast(); break
    }
  }
}
```

---

## 5. 포커스 스타일

```css
/* ❌ 절대 제거하지 말 것 */
:focus { outline: none; }

/* ✅ 커스텀 포커스 스타일 */
:focus-visible {
  outline: 2px solid hsl(var(--primary));
  outline-offset: 2px;
  border-radius: 4px;
}

/* Tailwind */
/* focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 */
```

`:focus` 대신 `:focus-visible` 사용 — 마우스 클릭 시엔 outline 숨기고, 키보드 포커스 시에만 표시.

---

## 6. 색상 대비

WCAG AA 기준:
- 일반 텍스트: 대비율 **4.5:1** 이상
- 큰 텍스트 (18px+ 또는 bold 14px+): **3:1** 이상
- UI 컴포넌트, 그래픽: **3:1** 이상

```tsx
// 대비율 확인 도구: axe DevTools, Colour Contrast Checker
// Tailwind 기본 팔레트 기준 안전한 조합:
// text-gray-900 on bg-white  → 21:1 ✅
// text-gray-600 on bg-white  → 7.0:1 ✅
// text-gray-400 on bg-white  → 3.5:1 ❌ (일반 텍스트 기준)
```

---

## 7. 이미지와 미디어

```tsx
// 의미 있는 이미지 — alt 텍스트 필수
<img src="/profile.jpg" alt="홍길동의 프로필 사진" />

// 장식용 이미지 — alt="" (스크린 리더가 건너뜀)
<img src="/divider.png" alt="" role="presentation" />

// SVG 아이콘
<svg aria-hidden="true" focusable="false">...</svg>  // 장식용
<svg aria-label="설정" role="img">...</svg>           // 의미 있는 경우

// 동영상
<video controls>
  <source src="/intro.mp4" type="video/mp4" />
  <track kind="captions" src="/captions.vtt" srclang="ko" label="한국어" />
</video>
```

---

## 8. 자동화 테스트

```ts
// jest-axe로 자동 접근성 검사
import { axe, toHaveNoViolations } from 'jest-axe'
expect.extend(toHaveNoViolations)

it('접근성 위반 없음', async () => {
  const { container } = render(<LoginForm />)
  const results = await axe(container)
  expect(results).toHaveNoViolations()
})
```

---

## 9. 안티패턴

- **`outline: none`**: 키보드 사용자 포커스 불가
- **색상만으로 정보 전달**: "빨간색 = 에러" → 아이콘/텍스트 병행
- **클릭 영역 너무 작음**: 최소 44×44px
- **자동 재생 미디어**: 사용자 제어권 제공
- **에러를 placeholder로만 표시**: focus 잃으면 사라짐 → `aria-describedby`로
