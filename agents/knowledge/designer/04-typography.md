# Typography

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/typography

---

## 1. 타이포그래피의 중요성

웹 콘텐츠의 95%는 텍스트다. 타이포그래피는 단순한 글꼴 선택이 아니라 **정보의 구조화, 가독성, 감정 전달**의 핵심 도구다. 잘못된 타이포그래피는 콘텐츠의 가치를 떨어뜨리고, 올바른 타이포그래피는 보이지 않게 작동한다.

---

## 2. Type Scale (타입 스케일)

수학적 비율에 기반한 크기 체계. Major Third (1.25), Perfect Fourth (1.333), Golden Ratio (1.618).

```
Base: 16px (1rem) / Scale ratio: 1.25 (Major Third)

xs:    12.80px  (0.800rem)  — caption, helper text
sm:    14.00px  (0.875rem)  — secondary text, metadata
base:  16.00px  (1.000rem)  — body text
lg:    20.00px  (1.250rem)  — lead paragraph, subtitle
xl:    25.00px  (1.563rem)  — h4
2xl:   31.25px  (1.953rem)  — h3
3xl:   39.06px  (2.441rem)  — h2
4xl:   48.83px  (3.052rem)  — h1
5xl:   61.04px  (3.815rem)  — display
```

**Tailwind CSS 기본 스케일:** text-xs(12) / text-sm(14) / text-base(16) / text-lg(18) / text-xl(20) / text-2xl(24) / text-3xl(30) / text-4xl(36) / text-5xl(48)

---

## 3. Line Height (행간)

| 용도 | Line Height | 비고 |
|------|------------|------|
| 본문 | 1.5–1.75 | 가장 편안한 읽기 경험 |
| 제목 | 1.1–1.3 | 제목은 짧으므로 타이트하게 |
| 캡션/작은 텍스트 | 1.4–1.6 | 작은 텍스트는 약간 넉넉하게 |
| 대형 디스플레이 | 1.0–1.15 | 극대형 텍스트는 매우 타이트하게 |

- 글씨가 작을수록 행간을 넓게, 클수록 좁게
- 한글은 영어보다 약간 넓은 행간 필요 (1.6–1.8 권장)
- `line-height`는 단위 없는 값 사용 (1.5, not 24px)

---

## 4. Letter Spacing (자간)

- **대문자(ALL CAPS)**: +0.05em ~ +0.1em (대문자는 기본 자간이 좁음)
- **제목 (큰 사이즈)**: -0.01em ~ -0.025em (응집력)
- **본문**: 기본값 유지 (0) — 폰트 디자이너가 최적화한 값
- **작은 텍스트**: +0.01em ~ +0.02em (가독성 향상)
- **Bold 제목**: 약간 넓히는 것이 좋다 (Bold는 자간이 좁아 보임)

---

## 5. 가독성 (Readability)

**Line Length (행장):**
- 최적: 45–75자 / 모바일: 35–50자
- CSS: `max-width: 65ch`

**Alignment:**
- 좌측 정렬: 기본. 가장 높은 가독성
- 양쪽 정렬(justify): 웹에서 비권장 (불균등 단어 간격)
- 중앙 정렬: 3줄 이내 짧은 텍스트만
- 우측 정렬: 테이블 내 숫자 데이터

---

## 6. Font Selection (폰트 선택)

**원칙:**
1. 2-3개 폰트로 제한: 제목 + 본문 + (선택적) 모노스페이스
2. 대비 만들기: 제목에 Serif, 본문에 Sans-Serif
3. x-height 확인: 높은 x-height = 작은 크기에서 가독성 좋음
4. 웨이트 가용성: Regular, Medium, SemiBold, Bold 최소 4개

**웹 폰트 성능:**
- Variable Font 활용: 하나의 파일로 다양한 weight
- `font-display: swap`: FOUT 허용, CLS 최소화
- 서브셋: 한글은 필요한 2,350자만 포함 (전체 2만자+ → 경량화)

**한글 폰트 추천:**

| 용도 | 폰트 | 특징 |
|------|------|------|
| 본문 | Pretendard | 한영 조화, 가변폰트 지원 |
| 본문 | Noto Sans KR | Google Fonts, 넓은 웨이트 |
| 제목 | Spoqa Han Sans Neo | 깔끔한 고딕 |
| 코드 | JetBrains Mono | 리거처 지원 |

**시스템 폰트 스택:**
```css
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
  "Helvetica Neue", Arial, "Noto Sans", "Noto Sans KR", sans-serif;
```

---

## 7. Typographic Hierarchy (타이포그래피 위계)

| 역할 | 크기 | 무게 | 용도 |
|------|------|------|------|
| Display | 48-72px | Bold/ExtraBold | 히어로, 랜딩 |
| H1 | 36-48px | Bold | 페이지 제목 |
| H2 | 28-36px | SemiBold | 섹션 제목 |
| H3 | 24-28px | SemiBold | 서브섹션 |
| H4 | 20-24px | Medium | 카드 제목 |
| Body Large | 18px | Regular | 리드 문단 |
| Body | 16px | Regular | 기본 본문 |
| Body Small | 14px | Regular | 보조 정보 |
| Caption | 12px | Regular/Medium | 메타데이터, 힌트 |
| Overline | 12px | SemiBold, CAPS | 카테고리 라벨 |

**위계 만드는 3가지 도구:** Size + Weight + Color. 한 번에 너무 많은 변화를 주지 않는다.

---

## 8. Responsive Typography

**Fluid Typography (CSS clamp):**
```css
/* 최소 16px, 뷰포트의 2.5%, 최대 24px */
font-size: clamp(1rem, 0.5rem + 2.5vw, 1.5rem);
```

**단계별 크기 변화:**
```css
/* 모바일 우선 */
h1 { font-size: 1.75rem; }  /* 28px */

@media (min-width: 768px) {
  h1 { font-size: 2.25rem; }  /* 36px */
}

@media (min-width: 1024px) {
  h1 { font-size: 3rem; }  /* 48px */
}
```

---

## 9. 안티패턴

- 12px 미만 텍스트: 가독성 저해, 접근성 위반 위험
- 3개 이상 폰트 혼용: 시각적 혼란
- 행장 무제한: 전체 화면 너비로 텍스트 늘리기
- 불충분한 대비: 연한 회색 텍스트 on 흰색 배경 (WCAG 위반)
- 과도한 웨이트 사용: Thin(100)은 대형 디스플레이에서만
