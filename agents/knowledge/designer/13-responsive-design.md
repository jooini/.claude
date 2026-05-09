# Responsive Design

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/responsive-design

---

## 1. 모바일 퍼스트 (Mobile First)

Luke Wroblewski가 제안한 접근법. 가장 제약이 많은 환경(모바일)에서 시작해 점진적으로 확장.

**왜 모바일 퍼스트인가?**
1. **집중**: 작은 화면은 핵심 콘텐츠/기능에 집중하게 강제
2. **성능**: 모바일 기준으로 최적화하면 데스크톱에서도 빠름
3. **트래픽**: 글로벌 웹 트래픽의 60%+ 가 모바일
4. **Progressive Enhancement**: 기본 경험 위에 기능 추가

```css
/* ✅ Mobile First: min-width 사용 */
.card { padding: 16px; }
@media (min-width: 768px) { .card { padding: 24px; } }
@media (min-width: 1024px) { .card { padding: 32px; } }

/* ❌ Desktop First: max-width 사용 */
.card { padding: 32px; }
@media (max-width: 1023px) { .card { padding: 24px; } }
@media (max-width: 767px) { .card { padding: 16px; } }
```

---

## 2. Adaptive vs Responsive

**Responsive Design:** 유동적으로 모든 뷰포트에 적응. 비율 기반 레이아웃 + 미디어 쿼리. `width: 100%`, `max-width`, `fr`, `%` 사용. 하나의 코드베이스로 모든 화면 대응.

**Adaptive Design:** 특정 브레이크포인트별로 고정된 레이아웃 제공. 더 정밀한 제어 가능하지만 유지보수 비용 높음.

**실무: 하이브리드** — Responsive(그리드, 이미지, 타이포) + Adaptive(레이아웃 구조, 네비게이션 패턴)

---

## 3. Touch Target

| 플랫폼 | 최소 크기 | 권장 크기 |
|--------|----------|----------|
| Apple HIG | 44×44pt | 44×44pt |
| Material Design | 48×48dp | 48×48dp |
| WCAG 2.2 (AA) | 24×24px | 44×44px |

**터치 타겟 원칙:**
- 인접 타겟 간 최소 8px 간격
- 시각적 크기 < 실제 타겟 크기 가능 (padding으로 확장)
- 아이콘 버튼: 시각적 16-24px + padding으로 44×44 확보

```css
.icon-button {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.icon-button svg { width: 20px; height: 20px; }
```

---

## 4. 모바일 UI 패턴

### 네비게이션 패턴

| 패턴 | 사용 케이스 | 특징 |
|------|-----------|------|
| Bottom Navigation Bar | 앱 주요 탭 (3-5개) | 엄지로 접근 쉬움 |
| Hamburger Menu | 보조 링크, 설정 | 숨김 메뉴 (탐색 어려움) |
| Tab Bar (top) | 동위 콘텐츠 전환 | 수평 스크롤 가능 |
| Floating Action Button | 주요 액션 1개 | 강조, 항상 접근 가능 |
| Drawer | 많은 네비게이션 항목 | 왼쪽에서 슬라이드 |

### 제스처 패턴

| 제스처 | 의미 | 예시 |
|--------|------|------|
| Tap | 선택/활성화 | 버튼 클릭 |
| Long press | 컨텍스트 메뉴 | 항목 옵션 |
| Swipe left/right | 삭제/액션 노출 | 이메일 삭제 |
| Pull down | 새로고침 | 피드 업데이트 |
| Pinch | 확대/축소 | 지도, 이미지 |
| Double tap | 확대 또는 좋아요 | Instagram 좋아요 |

---

## 5. 반응형 이미지

```html
<!-- srcset으로 해상도별 이미지 -->
<img
  src="image-800w.jpg"
  srcset="image-400w.jpg 400w,
          image-800w.jpg 800w,
          image-1600w.jpg 1600w"
  sizes="(max-width: 600px) 100vw,
         (max-width: 1200px) 50vw,
         800px"
  alt="설명"
>

<!-- picture 태그로 포맷 분기 -->
<picture>
  <source type="image/webp" srcset="image.webp">
  <source type="image/jpeg" srcset="image.jpg">
  <img src="image.jpg" alt="설명">
</picture>
```

---

## 6. 반응형 타이포그래피

```css
/* CSS clamp: 뷰포트에 따라 자연스럽게 크기 변화 */
h1 { font-size: clamp(1.75rem, 4vw + 1rem, 3rem); }
p  { font-size: clamp(1rem, 2vw + 0.5rem, 1.25rem); }
```

---

## 7. Figma 반응형 디자인

**Auto Layout + Constraints:**
- 모든 컴포넌트에 Auto Layout 적용
- Hug: 콘텐츠 크기에 맞춤
- Fill: 부모 프레임을 채움
- Fixed: 고정 크기

**변형 작업 순서:**
1. Mobile (375px) 기준 디자인
2. Tablet (768px) 변형 생성
3. Desktop (1440px) 변형 생성
4. 각 브레이크포인트에서 콘텐츠 동작 확인

---

## 8. 안티패턴

- **"나중에 모바일": 데스크톱 완성 후 모바일 축소 시도** → 레이아웃 붕괴
- **터치 타겟 너무 작음**: 16px 아이콘에 패딩 없음
- **호버 의존 UI**: 모바일에는 호버 없음. 중요한 기능을 hover에만 표시 금지
- **반응형 테스트 부족**: 크롬 DevTools만으로 실제 기기 테스트 대체 불가
- **고정 픽셀 크기 남용**: `width: 500px` → 모바일에서 넘침
