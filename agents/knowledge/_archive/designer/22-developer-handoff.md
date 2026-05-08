# Developer Handoff

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/developer-handoff

---

## 1. 핸드오프란?

디자이너가 완성된 디자인을 개발자에게 전달하는 과정. "파일 던지기"가 아닌 **협업의 연장**. 잘 된 핸드오프는 구현 중 질문을 최소화하고, 디자인 의도가 정확히 구현된다.

---

## 2. 핸드오프 준비 체크리스트

### Figma 파일 정리

**구조:**
- 레이어 이름 의미있게 (`Button/Primary/Default` ✅, `Rectangle 123` ❌)
- 컴포넌트는 모두 Figma Components로 정의
- 페이지 구조: `Design` / `Prototype` / `Handoff` / `Archive`
- 사용하지 않는 레이어/페이지 정리

**컴포넌트:**
- 모든 상태 표현 (Default, Hover, Focus, Disabled, Error, Loading)
- Variants로 상태/크기 관리
- Auto Layout 적용 (유동적 크기 지원)
- Constraints 설정 (반응형)

**스펙 명확화:**
- 모든 간격, 크기를 8pt Grid에 맞춰 정수로
- 색상은 디자인 토큰/스타일로 (hex 값 직접 참조보다)
- 텍스트 스타일 모두 Text Style로 등록

---

## 3. Figma Dev Mode 활용

**Dev Mode 켜기:**
- Figma 우측 상단 → Dev Mode 토글
- 개발자가 직접 CSS/iOS/Android 스펙 확인 가능

**개발자가 확인할 수 있는 것:**
- CSS properties (color, font, spacing, border-radius 등)
- 레이어 간 간격 (Cmd/Ctrl + 드래그)
- 자산 Export (SVG, PNG, WebP)
- Component 링크

**주석 추가 (Figma Comments):**
- 인터랙션 설명: "클릭 시 모달 오픈"
- 조건부 로직: "로그인 상태에서만 표시"
- 애니메이션: "ease-out 200ms"
- 엣지 케이스: "최대 3줄, 이상 시 말줄임"

---

## 4. 스펙 문서 작성

### 컴포넌트 스펙

각 컴포넌트에 포함할 정보:

```
컴포넌트명: Button (Primary)
─────────────────────────────
크기:
  sm: h-8  (32px),  px-3 (12px)
  md: h-9  (36px),  px-4 (16px)  ← default
  lg: h-10 (40px),  px-6 (24px)

색상:
  배경:      color-primary     (#3b82f6)
  배경 hover: color-primary-hover (#2563eb)
  텍스트:    white
  비활성:    배경 opacity 50%, cursor: not-allowed

Typography: text-sm (14px), font-weight: 500

Border radius: radius-md (6px)

상태:
  Default → Hover (background: darker) → Active (scale: 0.98)
  Disabled: opacity-50, pointer-events-none
  Loading: spinner + 텍스트 숨김

접근성:
  role="button" (또는 <button> 태그)
  disabled 속성 사용 (aria-disabled 아닌)
  최소 44×44px touch target
```

### 플로우 문서

복잡한 인터랙션은 흐름 문서 작성:

```
1. 사용자가 "결제하기" 클릭
   → 로딩 상태 (버튼 spinner, 0.5초)
   → 성공: 완료 페이지로 이동 (페이드)
   → 실패(카드 거절): 인라인 에러 표시 + 버튼 재활성화
   → 실패(네트워크): 토스트 "다시 시도해 주세요" + 버튼 재활성화
```

---

## 5. 자산 Export

### 아이콘
- SVG 형식 권장 (벡터, 크기 자유)
- 파일명 규칙: `icon-{name}.svg` (kebab-case)
- 뷰박스 설정 확인 (24×24 또는 16×16)
- stroke/fill 색상을 `currentColor`로 (CSS로 색상 제어)

### 이미지
- WebP 우선, PNG 폴백
- Retina용 2x, 3x Export
- 최적화: Figma는 기본적으로 무손실. 추가 압축 권장

### 일러스트/아이콘 세트
- Figma → Export as SVG Sprite (한 파일로 묶기)
- 또는 Icon Font 생성 (icomoon 등)

---

## 6. 커뮤니케이션 실천

### 핸드오프 미팅

개발자와 함께 진행하는 워크스루:
1. **맥락 설명**: 이 기능이 왜 필요한가, 어떤 사용자 문제를 해결하는가
2. **Happy path 설명**: 주요 플로우 시연
3. **엣지 케이스 공유**: "이 경우 어떻게 되나요?"를 미리 답변
4. **질문 수렴**: 개발자의 의문 해소
5. **우선순위**: "꼭 구현해야 할 것" vs "나중에 개선할 수 있는 것"

### 슬랙/이슈 트래커 활용
- 구현 중 질문이 오면 24시간 내 답변 목표
- 스크린샷 + 설명으로 명확한 답변
- 중요 결정 사항은 기록으로 남기기

---

## 7. 디자인 QA (Design Quality Assurance)

### QA 시점
- 개발 중간 (기능 완성 전): 레이아웃, 색상, 타이포 확인
- 개발 완성 후 (배포 전): 인터랙션, 반응형, 엣지 케이스 확인

### QA 방법
- 디자인 파일과 구현 나란히 놓고 비교
- Pixeledge, PixelSnap 등 도구 활용
- 모바일 기기에서 실제 터치 테스트
- 키보드 네비게이션 테스트

### 이슈 리포트 형식

```
제목: [버튼] hover 상태 색상 불일치
화면: 로그인 페이지 > CTA 버튼
기대: #2563eb (디자인 파일 기준)
실제: #3b82f6 (구현 결과)
스크린샷: [첨부]
우선순위: Medium (UI 오류, 기능은 정상)
```

---

## 8. 안티패턴

- **디자인 파일만 던지기**: 컨텍스트 없이 Figma 링크만 공유
- **레이어 이름 미정리**: Rectangle 1, Group 47 등
- **상태 미정의**: Default만 있고 나머지 상태 없음
- **스펙 불일치**: Figma와 실제 구현이 달라도 OK
- **QA 건너뛰기**: "개발자가 알아서 잘 하겠지"
- **사후 수정 요청**: 개발 완료 후 "사실 이렇게 바꿔요"
