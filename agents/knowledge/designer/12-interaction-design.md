# Interaction Design

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/interaction-design

---

## 1. 마이크로인터랙션 (Micro-interactions)

Dan Saffer가 정의한 4요소로 구성되는 작은 인터랙티브 순간.

**4요소:**
- **Trigger**: 인터랙션을 시작하는 것 (사용자: 클릭/탭/호버 / 시스템: 시간 기반, 데이터 변경)
- **Rules**: 트리거 후 무엇이 일어나는지. "좋아요 클릭 → 하트 채워지고 카운트 +1"
- **Feedback**: 사용자에게 무슨 일이 일어났는지 알려줌 (Visual, Motion, Haptic)
- **Loops & Modes**: 시간에 따른 행동 변화 (첫 번째 좋아요 vs 연속 좋아요)

**주요 예시:**

| 인터랙션 | 트리거 | 피드백 |
|---------|--------|--------|
| Toggle switch | 탭/클릭 | 슬라이드 애니메이션 + 색상 변화 |
| Pull to refresh | 풀다운 | 스피너 회전 + 콘텐츠 업데이트 |
| Like/Heart | 탭 | 하트 팝 애니메이션 + 파티클 |
| Password show/hide | 아이콘 클릭 | 눈 아이콘 전환 + 텍스트 표시 |
| Swipe to delete | 스와이프 | 빨간 배경 노출 + 삭제 아이콘 |

---

## 2. 애니메이션 원칙

### Easing (가속/감속)

- **ease-out**: UI 요소 등장. 빠르게 시작, 부드럽게 정지. **가장 많이 사용**
- **ease-in**: UI 요소 퇴장. 천천히 시작, 빠르게 사라짐
- **ease-in-out**: 화면 전환, 위치 이동
- **linear**: 거의 사용 안 함 (로딩 스피너 정도)

```css
--ease-out:   cubic-bezier(0.16, 1, 0.3, 1);
--ease-in:    cubic-bezier(0.55, 0.055, 0.675, 0.19);
--ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);  /* 스프링 효과 */
```

### Duration (지속 시간)

| 유형 | Duration | 예시 |
|------|----------|------|
| 즉각적 | 100ms | 호버 색상 변화, 체크박스 |
| 빠름 | 150-200ms | 버튼 상태 전환, 드롭다운 열기 |
| 보통 | 200-300ms | 모달 등장, 카드 확장 |
| 느림 | 300-500ms | 페이지 전환, 복잡한 레이아웃 변화 |

**규칙:** 작은 요소 = 짧은 duration. 큰 요소/긴 거리 = 긴 duration.

### Anticipation & Follow-through

- **Anticipation**: 액션 전 약간의 준비 동작. 버튼 클릭 시 scale(0.95) 후 원래 크기로
- **Follow-through**: 메인 동작 후 여운. 토스트가 올라온 후 살짝 바운스

---

## 3. 트랜지션 (Transitions)

**페이지/뷰 전환:**
- **Push**: 새 화면이 옆에서 밀고 들어옴 (네비게이션 진행)
- **Fade**: 부드러운 크로스페이드 (상위 레벨 전환)
- **Scale + Fade**: 약간 확대되며 페이드 (상세 화면 진입)
- **Shared Element**: 같은 요소가 두 화면 간 연결 이동 (View Transitions API)

**모달/오버레이 전환:**
```css
.modal-enter { opacity: 0; transform: scale(0.95) translateY(10px); }
.modal-enter-active {
  opacity: 1; transform: scale(1) translateY(0);
  transition: all 200ms var(--ease-out);
}
.overlay-enter { opacity: 0; }
.overlay-enter-active { opacity: 1; transition: opacity 200ms ease; }
```

**리스트 아이템:**
- 추가: Fade in + slide down
- 제거: Fade out + slide up + 나머지 아이템 자연스럽게 이동
- 재정렬: FLIP 기법 (First, Last, Invert, Play)

---

## 4. 피드백 (Feedback)

### 피드백의 유형

**즉각적 피드백:** 버튼 클릭 시 색상 변화 + ripple, 실시간 유효성 검증

**진행 피드백:**
- Determinate (결정적): 프로그레스 바 (완료율 알 때)
- Indeterminate (비결정적): 스피너, skeleton (완료율 모를 때)
- **Skeleton Screen > Spinner** (지각된 성능 향상)

**확인 피드백:** 토스트 메시지 (2-4초 후 자동 닫기), 인라인 체크마크, 성공 애니메이션

### 피드백 시간 원칙

1. **100ms 이내**: 사용자가 "시스템이 반응했다"고 느끼는 한계
2. **1초 이내 완료**: 사용자 집중 유지. 초과 시 로딩 인디케이터 필요
3. **10초 이내**: 사용자 인내 한계. 초과 시 프로그레스 바 + 취소 옵션
4. **Optimistic UI**: 서버 응답 전 UI 먼저 업데이트. 실패 시 롤백

---

## 5. Affordance (행위유발성)

Don Norman이 정립. 오브젝트가 어떻게 사용될 수 있는지 시각적으로 암시.

| 요소 | 어포던스 | 시각적 단서 |
|------|---------|-----------|
| 버튼 | "클릭할 수 있다" | 배경색, 보더, 호버 변화 |
| 텍스트 링크 | "클릭할 수 있다" | 파란색, 밑줄 |
| 인풋 | "타이핑할 수 있다" | 보더, placeholder |
| 슬라이더 | "드래그할 수 있다" | 트랙 + 핸들 |
| 카드 | "클릭하면 상세로" | 호버 시 elevation 변화 |

**False Affordance 경고:** 클릭 불가한데 파란색 밑줄 텍스트, 버튼처럼 보이지만 반응 없는 요소

**Signifiers:** 어포던스를 더 명확히 하는 추가 단서. 화살표 아이콘, 그랩 핸들 (⋮⋮), 더보기 (...)

---

## 6. 모션 디자인 시스템

```js
const motion = {
  duration: {
    instant: '100ms', fast: '150ms', normal: '250ms', slow: '350ms',
  },
  easing: {
    default: 'cubic-bezier(0.16, 1, 0.3, 1)',
    spring: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
  },
  preset: {
    fadeIn: { opacity: [0, 1], duration: '250ms' },
    slideUp: { transform: ['translateY(8px)', 'translateY(0)'], opacity: [0, 1] },
    scaleIn: { transform: ['scale(0.95)', 'scale(1)'], opacity: [0, 1] },
  }
};
```

**`prefers-reduced-motion` 대응 (접근성 필수):**
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## 7. 안티패턴

- **과도한 애니메이션**: 모든 것이 움직이면 아무것도 강조되지 않음
- **느린 애니메이션**: 500ms 이상의 UI 전환은 사용자를 기다리게 함
- **불일치 모션**: 같은 유형의 전환인데 다른 duration/easing
- **차단적 애니메이션**: 애니메이션 완료까지 다음 액션 불가
- **Linear easing**: 기계적이고 부자연스러운 느낌
