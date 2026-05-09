# Wireframing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/wireframing

---

## 1. 와이어프레임이란?

UI의 골격(skeleton). 시각적 디자인을 배제하고 **구조, 콘텐츠 배치, 기능**에 집중하는 설계 도구. 색상, 타이포, 이미지 없이 레이아웃과 정보 우선순위를 결정한다.

---

## 2. Fidelity 레벨

### Low-Fidelity (Lo-fi)

- **형태**: 손 스케치, 박스와 선, 텍스트 자리표시
- **도구**: 종이 + 펜, iPad + Pencil, Excalidraw
- **소요 시간**: 화면당 5-15분

```
┌─────────────────────────┐
│ [Logo]    [Nav] [Nav] [□]│
├─────────────────────────┤
│  xxxxxxxxxxxxxxxx       │
│  xxxx                   │
│  [Button]               │
├──────────┬──────────────┤
│ [■]      │ [■]          │
│ xxxxxxxx │ xxxxxxxx     │
└──────────┴──────────────┘
```

**장점:** 빠른 아이디어 탐색, "예쁜 디자인"에 피드백 집중 방지, 비디자이너 참여 가능, 버리기 쉬움

### Mid-Fidelity (Mid-fi)

- **형태**: 디지털 와이어프레임, 실제 텍스트, 기본 레이아웃
- **도구**: Figma (wireframe kit), Balsamiq, Whimsical
- **소요 시간**: 화면당 30-60분
- 실제 텍스트 사용 (Lorem ipsum 최소화), 기본 그리드/spacing 적용

### High-Fidelity (Hi-fi)

- **형태**: 완성에 가까운 디자인, 실제 콘텐츠, 타이포/컬러
- **도구**: Figma
- **소요 시간**: 화면당 2-8시간
- 디자인 시스템 컴포넌트 사용, 인터랙션 프로토타입 포함

### 언제 어떤 Fidelity?

| 상황 | 권장 Fidelity |
|------|-------------|
| 아이디어 탐색, 브레인스토밍 | Lo-fi |
| 이해관계자에게 방향성 설명 | Lo-fi ~ Mid-fi |
| 사용성 테스트 (초기) | Mid-fi |
| 개발자 협의 | Mid-fi |
| 최종 승인, 핸드오프 | Hi-fi |

---

## 3. 와이어프레임 프로세스

1. **준비**: 유저 플로우 확인, 콘텐츠 인벤토리, 기술적 제약 파악
2. **스케치 (Lo-fi)**: Crazy 8s (8분에 8가지 접근법), 다양한 레이아웃 탐색, 팀 피드백
3. **디지털 와이어프레임 (Mid-fi)**: 선택된 방향 디지털화, 실제 콘텐츠 교체, 상태별 화면 (Empty, Loading, Error)
4. **프로토타입 + 테스트**: 핵심 플로우 인터랙티브 프로토타입, 사용성 테스트, 피드백 반영
5. **비주얼 디자인 (Hi-fi)**: 디자인 시스템 적용, 마이크로인터랙션, 핸드오프 준비

---

## 4. Figma 워크플로우

### 파일 구조

```
📁 Project Name
├── 📄 Research & Insights
├── 📄 Wireframes
│   ├── 🎨 Lo-fi Sketches
│   ├── 🎨 Mid-fi Wireframes
│   └── 🎨 User Flows
├── 📄 Design
│   ├── 🎨 Desktop / Tablet / Mobile
│   └── 🎨 Components (local)
├── 📄 Prototype
└── 📄 Handoff
```

### 네이밍 컨벤션

```
페이지: [Feature] / [Screen Name] / [State]
예: Auth / Login / Default
    Auth / Login / Error
    Dashboard / Overview / Empty
```

### Figma 팁

- **Auto Layout**: 모든 프레임에 적용. 반응형 기본
- **Constraints**: 부모 크기 변경 시 자식 요소 행동 정의
- **Components**: 반복되는 요소는 즉시 컴포넌트화
- **Variants**: 버튼 상태를 variant로 관리

---

## 5. 프로토타이핑

### Figma Prototyping

**기본 인터랙션:**
- Click/Tap → Navigate to (화면 이동)
- Hover → Change to (호버 상태)
- While pressing → Change to (프레스 상태)
- Drag → Move in/out (바텀시트, 캐러셀)

**트랜지션:**
- Dissolve: 부드러운 페이드 (기본)
- Move in/out: 화면 이동
- Smart Animate: 같은 이름의 레이어 간 자동 트윈

**범위:** 모든 화면 연결 불필요. **핵심 플로우만** 프로토타이핑.

### 도구 비교

| 도구 | 강점 | 약점 |
|------|------|------|
| Figma | 디자인 통합, 팀 협업 | 복잡한 인터랙션 한계 |
| Framer | 실제 코드 수준 인터랙션 | 학습 곡선 높음 |
| ProtoPie | 센서, 조건부 인터랙션 | 별도 도구 |

---

## 6. 와이어프레임 리뷰 체크리스트

- 콘텐츠 우선순위가 시각적 위계에 반영되었는가?
- 모든 인터랙티브 요소가 식별 가능한가?
- CTA가 명확한가? (화면당 1개 Primary CTA)
- 모바일/태블릿 변형이 고려되었는가?
- Empty, Error, Loading 상태가 포함되었는가?
- 실제 콘텐츠로 테스트했는가?

---

## 7. 안티패턴

- **Pixel-perfect Lo-fi**: Lo-fi에서 디테일에 시간 쓰기
- **Lorem Ipsum 의존**: 가짜 텍스트로는 레이아웃 검증 불가
- **모바일 후순위**: 데스크톱 먼저, 모바일 나중
- **프로토타입 없이 핸드오프**: 정적 화면만으로는 인터랙션 전달 불가
