# Accessibility

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/accessibility

---

## 1. WCAG 2.1 개요

Web Content Accessibility Guidelines. W3C 국제 표준.

**준수 레벨:**
- **A**: 최소 (필수)
- **AA**: 권장 (대부분의 법적 요구사항) ← **기본 목표**
- **AAA**: 최고 (특수한 상황)

---

## 2. POUR 원칙

### Perceivable (인지 가능)

**텍스트 대안 (1.1):**
- 모든 비텍스트 콘텐츠에 텍스트 대안
- 이미지: `alt` 속성. 장식: `alt=""`
- 아이콘 버튼: `aria-label`
- 복잡한 이미지(차트): 데이터 테이블 대안

**시간 기반 미디어 (1.2):**
- 비디오: 자막, 오디오 설명
- 오디오: 텍스트 전사

**색상 대비 (1.4.3 AA):**
- 일반 텍스트: 4.5:1 이상
- 대형 텍스트 (18pt+ 또는 14pt bold+): 3:1 이상
- UI 컴포넌트, 그래픽: 3:1 이상

**색상만으로 의미 전달 금지 (1.4.1):**
- ❌ 빨간색으로만 에러 표시 → ✅ 색상 + 아이콘 + 텍스트 함께

### Operable (조작 가능)

**키보드 접근 (2.1):**
- 모든 기능을 키보드만으로 사용 가능
- Tab, Enter, Escape, Arrow keys
- Keyboard trap 없어야 함 (모달 제외, 모달은 트랩 필요)

**포커스 가시성 (2.4.7):**
- 현재 포커스된 요소가 시각적으로 명확해야 함
- ❌ `outline: none` 제거 금지 (대안 없이)
- Focus ring이 명확해야 함

**건너뛰기 링크 (2.4.1):**
- 키보드 사용자가 반복 네비게이션을 건너뛸 수 있어야 함
```html
<a href="#main-content" class="skip-link">메인 콘텐츠로 건너뛰기</a>
```

**충분한 시간 (2.2):**
- 세션 타임아웃 시 경고 + 연장 옵션
- 자동 이동/갱신 제어 가능

**발작 유발 콘텐츠 (2.3):**
- 초당 3회 이상 깜빡이는 콘텐츠 금지

### Understandable (이해 가능)

**언어 명시 (3.1.1):**
```html
<html lang="ko">
```

**명확한 레이블 (3.3.2):**
- 모든 폼 입력에 `<label>` 또는 `aria-label`
- Placeholder만으로 레이블 대체 불가

**에러 식별 (3.3.1):**
- 에러 발생 시 어떤 필드에 문제가 있는지 텍스트로 설명
- 에러 복구 방법 제안

**일관성 (3.2):**
- 같은 컴포넌트는 일관된 위치, 같은 동작

### Robust (견고)

**유효한 HTML:**
- 시맨틱 HTML 사용 (`<nav>`, `<main>`, `<header>`, `<aside>`, `<section>`)
- ARIA 속성 올바른 사용

---

## 3. ARIA (Accessible Rich Internet Applications)

**핵심 원칙:**
1. 시맨틱 HTML을 먼저 사용하고, ARIA는 보완 수단
2. `aria-label`, `aria-labelledby`, `aria-describedby` 로 이름 제공
3. 동적 콘텐츠: `aria-live`, `aria-atomic`으로 변경 알림

**주요 ARIA 속성:**

```html
<!-- 버튼 역할 -->
<div role="button" tabindex="0" aria-label="닫기">×</div>

<!-- 모달 -->
<div role="dialog" aria-modal="true" aria-labelledby="modal-title">
  <h2 id="modal-title">제목</h2>
</div>

<!-- 폼 에러 -->
<input aria-required="true" aria-describedby="email-error">
<span id="email-error" role="alert">올바른 이메일을 입력해 주세요</span>

<!-- 로딩 상태 -->
<div aria-live="polite" aria-atomic="true">
  콘텐츠가 업데이트되었습니다
</div>

<!-- 토글 상태 -->
<button aria-expanded="false" aria-controls="menu">메뉴</button>
```

---

## 4. 키보드 네비게이션

**포커스 관리:**
- 모달 열릴 때: 첫 번째 인터랙티브 요소로 포커스 이동
- 모달 닫힐 때: 모달을 연 요소로 포커스 복귀
- 새 콘텐츠 로드 시: 적절한 위치로 포커스 이동

**Tab 순서:**
- DOM 순서 = 시각적 순서 (일치시키기)
- `tabindex="0"`: 탭 순서에 포함
- `tabindex="-1"`: 탭 제외, JS로 포커스 가능
- `tabindex="1+"`: 사용 피하기 (순서 망가짐)

**Focus Trap (모달용):**
```js
// 모달 내에서만 Tab 순환
const focusableElements = modal.querySelectorAll(
  'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
);
```

---

## 5. 접근성 테스트

**자동 도구:**
- Axe DevTools (Chrome 확장)
- Lighthouse (Chrome DevTools → Accessibility)
- WAVE (webaim.org/resources/wave)

**수동 테스트:**
- 키보드만으로 전체 플로우 완수 가능한지
- 스크린 리더: macOS VoiceOver (Cmd+F5), Windows NVDA

**Figma:**
- Stark 플러그인: 색상 대비 체크
- Focus Order 플러그인: 탭 순서 시각화

---

## 6. 실무 체크리스트

- [ ] 모든 이미지에 `alt` 속성
- [ ] 색상 대비 4.5:1 이상 (본문)
- [ ] 색상만으로 정보 전달하지 않음
- [ ] 모든 인터랙티브 요소 키보드 접근 가능
- [ ] Focus ring 제거하지 않음
- [ ] 모든 폼 필드에 레이블
- [ ] 에러 메시지가 텍스트로 제공됨
- [ ] `<html lang="ko">` 명시
- [ ] 시맨틱 HTML 사용
- [ ] 영상에 자막 제공

---

## 7. 안티패턴

- `outline: none` 제거 후 대안 없음 (키보드 사용자 포커스 불가)
- Placeholder만으로 레이블 대체 (필드 클릭 시 힌트 사라짐)
- 색상만으로 에러/상태 표시
- 클릭 가능한 `<div>`에 역할/키보드 지원 없음
- 이미지에 alt 없음 또는 "image.jpg" 같은 무의미한 alt
