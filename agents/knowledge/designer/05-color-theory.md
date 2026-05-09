# Color Theory

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/color-theory

---

## 1. 색상의 기초

### 색상 모델

- **RGB**: 스크린 디스플레이 (가산혼합)
- **HSL**: 디자인 작업에 직관적. Hue(0-360°), Saturation(0-100%), Lightness(0-100%)
- **OKLCH**: 지각적으로 균일한 색상 공간. CSS Color Level 4. 다크모드 팔레트에 특히 유용
- **HEX**: RGB의 16진수. 코드에서 가장 흔히 사용

### 색상 관계 (Color Harmony)

| 관계 | 설명 | 사용 |
|------|------|------|
| Monochromatic | 하나의 색조, 다양한 채도/명도 | 세련되고 통일된 느낌 |
| Complementary | 색상환 반대편 | 강한 대비, CTA 강조 |
| Analogous | 색상환 인접 | 자연스럽고 조화로운 |
| Triadic | 120° 간격 3색 | 생동감, 균형 |
| Split-complementary | 보색의 양옆 2색 | 보색보다 부드러운 대비 |

---

## 2. UI 컬러 팔레트 설계

```
Brand Colors
├── Primary     — 브랜드 정체성, CTA, 주요 액션
├── Secondary   — 보조 액션, 강조
└── Accent      — 특별한 강조 (선택적)

Neutral Colors
├── Gray Scale  — 텍스트, 배경, 보더
└── White/Black — 기본 배경/텍스트

Semantic Colors
├── Success (green), Warning (amber), Error (red), Info (blue)
```

### 스케일 생성 (11-step 예시: primary)

```
primary-50:  #eff6ff  (가장 밝음 — 배경)
primary-100: #dbeafe
primary-200: #bfdbfe
primary-300: #93c5fd
primary-400: #60a5fa
primary-500: #3b82f6  (기본값)
primary-600: #2563eb
primary-700: #1d4ed8
primary-800: #1e40af
primary-900: #1e3a8a
primary-950: #172554  (가장 어두움)
```

**스케일 생성 원칙:**
- 50-100: 배경, 호버 상태
- 200-300: 보더, 비활성 요소
- 500-600: 주요 UI 요소 (버튼, 링크)
- 700-900: 텍스트, 강한 강조
- HSL에서 Lightness만 바꾸지 않기 — Saturation도 함께 조절

---

## 3. WCAG 대비 비율 (Contrast Ratio)

| 레벨 | 일반 텍스트 | 대형 텍스트 (18px+ bold, 24px+) | UI 컴포넌트 |
|------|-----------|-------------------------------|-----------|
| AA | 4.5:1 | 3:1 | 3:1 |
| AAA | 7:1 | 4.5:1 | — |

**실무 가이드라인:**
- 본문 텍스트: 최소 4.5:1. 목표 7:1 이상
- 플레이스홀더: 4.5:1 미달 시 접근성 위반 — 연한 회색 주의
- 포커스 인디케이터: 배경 대비 3:1 이상

**대비 검사 도구:** Figma(Stark, A11y 플러그인), WebAIM Contrast Checker, Chrome DevTools → Accessibility

---

## 4. 다크 모드 (Dark Mode)

**원칙:**
1. 단순 반전이 아니다: 라이트 모드 색상을 반전하면 안 됨
2. Elevation = Lightness: 높은 레이어는 더 밝은 배경 사용
3. 채도 낮추기: 밝은 배경에서 잘 보이던 색상은 채도를 10-20% 낮춤
4. 순수 검정(#000000) 피하기: #121212 ~ #1a1a1a 사용

```
Light Mode                    Dark Mode
──────────                    ─────────
background: #ffffff           background: #0a0a0a
surface:    #f8f9fa           surface:    #171717
border:     #e5e7eb           border:     #262626
text:       #111827           text:       #ededed
text-muted: #6b7280           text-muted: #a1a1aa
primary:    #2563eb           primary:    #60a5fa (더 밝은 shade)
```

**구현 전략:**
```css
:root { --bg: #ffffff; --text: #111827; }
.dark { --bg: #0a0a0a; --text: #ededed; }
```

---

## 5. 시맨틱 컬러 (Semantic Colors)

```
Primitive Token   →   Semantic Token         Usage
──────────────────────────────────────────────────
blue-500          →   color-primary          CTA, 링크
blue-50           →   color-primary-bg       선택된 항목 배경
green-600         →   color-success          성공 메시지
red-600           →   color-error            에러 텍스트
amber-600         →   color-warning          경고
gray-900          →   color-text-primary     주요 텍스트
gray-500          →   color-text-secondary   보조 텍스트
```

**규칙:**
- 색상만으로 의미를 전달하지 않는다: 아이콘 + 텍스트 라벨 병행
- 에러 = 빨강만이 아니다: ⚠️ 아이콘 + 텍스트 설명 + 색상

---

## 6. 색상 사용 비율

**60-30-10 법칙:**
- **60%**: Neutral (배경, 넓은 영역)
- **30%**: Secondary/Surface (카드, 섹션)
- **10%**: Primary/Accent (CTA, 하이라이트)

**실무 팁:**
- 색상 수를 제한. 3-5개 핵심 색상 + 그레이스케일
- 새 색상 추가 전 기존 색상으로 해결 가능한지 먼저 검토

---

## 7. 데이터 시각화 색상

- 구별 가능: 인접 색상이 충분히 구별되어야 함
- 순서 표현: Sequential = 같은 색조의 명도 변화
- 발산 표현: Diverging = 중간점(중립)에서 양극으로
- 카테고리 표현: 최대 8-10개 (그 이상은 구별 어려움)
- 색각 이상 안전: 빨강-초록 조합 피하기. 파랑-주황 조합 권장
