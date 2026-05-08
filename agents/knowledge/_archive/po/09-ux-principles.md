# UX Principles

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-po/ux-principles

---

## Nielsen's 10 Usability Heuristics

Jakob Nielsen이 정의한 사용성 평가의 10가지 원칙.

| # | 원칙 | 핵심 |
|---|------|------|
| 1 | **Visibility of System Status** | 로딩 인디케이터, 저장 완료 피드백, breadcrumb |
| 2 | **Match Between System and Real World** | 기술 용어 대신 일상 언어, 사용자 친숙한 개념 |
| 3 | **User Control and Freedom** | Undo/Redo/Cancel — 모든 파괴적 작업에 비상구 |
| 4 | **Consistency and Standards** | 같은 단어/상황/행동 = 같은 의미, 플랫폼 컨벤션 준수 |
| 5 | **Error Prevention** | 좋은 에러 메시지보다 오류가 발생하지 않는 설계 우선 |
| 6 | **Recognition Rather Than Recall** | 기억 부담 최소화 — 최근 항목, 자동완성, 인라인 힌트 |
| 7 | **Flexibility and Efficiency** | 초보자(기본값)와 전문가(단축키) 모두를 위한 설계 |
| 8 | **Aesthetic and Minimalist Design** | 불필요한 정보는 노이즈 — 한 화면에 하나의 주요 행동 |
| 9 | **Help Users Recognize, Diagnose, and Recover from Errors** | "오류가 발생했습니다"(X) → "이메일 형식이 올바르지 않습니다. @를 포함해주세요"(O) |
| 10 | **Help and Documentation** | 컨텍스트에 맞는 tooltip, 검색 가능한 문서, 단계별 가이드 |

---

## Information Architecture (IA)

### IA의 핵심 요소

1. **Organization**: 콘텐츠 분류 체계
2. **Labeling**: 명칭 체계 (사용자 언어 기반)
3. **Navigation**: 이동 방법 (메뉴, 검색, 링크)
4. **Search**: 검색 기능과 결과 구조

### Card Sorting

- **Open sort**: 사용자가 자유롭게 분류하고 이름 붙임 → 탐색적
- **Closed sort**: 미리 정한 카테고리에 분류 → 검증적
- **Hybrid**: 일부 카테고리 고정 + 자유 분류 혼합
- 도구: Optimal Workshop, Maze, UserZoom

### IA 검증: Tree Testing

네비게이션 구조만 보여주고 (UI 없이) 특정 항목을 찾게 하는 테스트.
- 성공률 80% 이상 → OK
- 60-80% → 개선 필요
- 60% 미만 → 구조 재설계

---

## 사용성 테스트

### 테스트 유형

| 유형 | 참가자 수 | 시간 | 적합한 상황 |
|------|---------|------|-----------|
| Moderated (대면) | 5-8명 | 45-60분 | 복잡한 플로우, 깊은 인사이트 |
| Unmoderated (원격) | 10-20명 | 15-30분 | 빠른 검증, 넓은 표본 |
| Guerrilla (게릴라) | 5명 | 10-15분 | 초기 단계, 빠른 피드백 |

### Jakob Nielsen의 5명 원칙

5명의 사용자로 사용성 문제의 ~85%를 발견할 수 있다.
- 5명 테스트 → 수정 → 5명 재테스트가 1회 15명보다 효과적
- 단, 정량적 데이터가 필요하면 더 많은 참가자 필요

### 사용성 테스트 스크립트 구조

```
1. 도입 (2분): 목적 설명, "제품이 아닌 제품을 테스트하는 것"
2. 워밍업 (3분): 배경 질문
3. 태스크 수행 (20-30분):
   - Task 1: "[구체적 시나리오]. 이 화면에서 시작해 주세요."
   - → 관찰 (개입 최소화, Think-aloud 유도)
   - Task 2-4: 동일 패턴
4. 사후 질문 (5분):
   - "가장 어려웠던 부분은?"
   - "예상과 달랐던 것은?"
   - SUS (System Usability Scale) 설문
```

### 측정 지표

- **Task success rate**: 태스크 완료 비율
- **Time on task**: 소요 시간
- **Error rate**: 오류 횟수
- **SUS score**: 표준화된 사용성 점수 (68점 이상 = 양호)

---

## Accessibility 기본

### WCAG 2.1 핵심 원칙 (POUR)

1. **Perceivable**: 모든 사용자가 인식할 수 있는가? (alt text, 충분한 대비)
2. **Operable**: 키보드만으로 조작 가능한가? (포커스, 네비게이션)
3. **Understandable**: 이해할 수 있는가? (명확한 언어, 일관된 UI)
4. **Robust**: 다양한 기기/브라우저에서 작동하는가?

### PO가 알아야 할 Accessibility 체크

- 색상 대비율 4.5:1 이상 (본문), 3:1 이상 (큰 텍스트)
- 모든 이미지에 대체 텍스트
- 키보드 네비게이션 가능
- 스크린 리더 호환
- 폼 레이블 명시

---

## Design Thinking Process

```
Empathize → Define → Ideate → Prototype → Test
   (공감)    (정의)   (발상)   (시제품)    (테스트)
     ↑                                      │
     └──────────────────────────────────────┘
                    (반복)
```

### 각 단계에서 PO의 역할

| 단계 | PO가 하는 일 | 산출물 |
|------|-----------|--------|
| Empathize | 인터뷰 참여, 고객 데이터 공유 | Journey map, Persona |
| Define | 문제 프레이밍, 기회 우선순위 | Problem statement, OST |
| Ideate | 제약 조건 공유, 브레인스토밍 참여 | 솔루션 후보 리스트 |
| Prototype | 범위 설정, 비즈니스 로직 검증 | 프로토타입 피드백 |
| Test | 성공 기준 정의, 결과 해석 | 검증 결과, 다음 스텝 |
