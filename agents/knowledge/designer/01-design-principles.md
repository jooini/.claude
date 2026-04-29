# Design Principles

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/design-principles

---

## 1. 디터 람스의 좋은 디자인 10원칙

Braun의 수석 디자이너 Dieter Rams가 정립한 10원칙. 반세기가 지난 지금도 디지털 프로덕트 디자인의 근본 철학.

| # | 원칙 | 핵심 |
|---|------|------|
| 1 | **Good design is innovative** | 혁신 자체가 목적이 되어선 안 된다 |
| 2 | **Makes a product useful** | 기능적·심리적·미적 요구 모두 충족 |
| 3 | **Is aesthetic** | 아름다움은 장식이 아닌 구조적 명료함에서 나온다 |
| 4 | **Makes a product understandable** | 최고의 인터페이스는 설명이 필요 없다 |
| 5 | **Is unobtrusive** | UI는 콘텐츠를 위한 무대다. 자기 표현이 아닌 사용자의 표현을 돕는다 |
| 6 | **Is honest** | 실제보다 더 가치 있거나 유용한 것처럼 보이게 하지 않는다. 다크 패턴의 반대 |
| 7 | **Is long-lasting** | 유행 대신 원칙에 기반한 디자인은 시간을 견딘다 |
| 8 | **Is thorough down to the last detail** | 디자인 과정의 주의와 정확함은 사용자에 대한 존중 |
| 9 | **Is environmentally friendly** | 디지털에서는 성능으로 해석 — 불필요한 리소스, 배터리 소모 줄이기 |
| 10 | **Is as little design as possible** | "Less, but better" — 본질에 집중, 비본질적인 것은 제거 |

---

## 2. Gestalt 원칙

인간의 시각 인지 패턴. UI 레이아웃과 그루핑의 이론적 기반.

### Proximity (근접성)
가까이 있는 요소들은 하나의 그룹으로 인식된다.
- 폼 필드와 라벨 간격: 4-8px / 필드 그룹 간 간격: 24-32px

### Similarity (유사성)
시각적으로 유사한 요소(색상, 크기, 형태)는 같은 그룹으로 인식된다.
- 같은 기능의 버튼은 같은 스타일, 다른 기능은 다른 스타일

### Continuity (연속성)
시선은 연속된 선이나 곡선을 따라 움직인다.
- 스텝 인디케이터, 프로그레스 바, 타임라인 UI

### Closure (폐합)
불완전한 형태도 완전한 형태로 인식하려는 경향.
- 최소한의 선으로 의미 전달하는 아이콘 디자인

### Figure-Ground (전경-배경)
요소를 전경(주목 대상)과 배경으로 분리하여 인식한다.
- 모달 다이얼로그 + 딤드 배경, 카드 elevation

### Common Region (공통 영역)
경계 안에 있는 요소들은 그룹으로 인식된다.
- 카드, 섹션 구분, 그룹 박스

### Focal Point (초점)
시각적으로 두드러진 요소가 먼저 주목을 끈다.
- CTA 버튼 강조, 배지/알림 인디케이터

---

## 3. Visual Hierarchy (시각적 위계)

사용자의 시선을 의도한 순서로 유도. 모든 요소가 같은 무게를 가지면 아무것도 강조되지 않는다.

**위계를 만드는 도구:**
- **크기**: 큰 요소가 먼저 보인다. 제목 > 부제목 > 본문 > 캡션
- **색상/대비**: 고대비 요소가 시선을 끈다. Primary CTA = 강한 색상
- **무게**: Bold > Regular > Light
- **위치**: 상단/좌측이 먼저 읽힌다 (LTR). F-패턴, Z-패턴 활용
- **여백**: 여백이 많은 요소는 중요해 보인다
- **밀도**: 핵심 정보는 넓은 공간에

**적용 원칙:**
1. **하나의 주인공**: 각 화면/섹션에 하나의 primary focus만
2. **스캔 가능한 구조**: 사용자는 읽지 않고 스캔한다 → 헤딩, 볼드, 리스트로 구조화
3. **점진적 공개**: 중요한 것부터 순서대로

---

## 4. C.R.A.P. 원칙

Robin Williams의 "The Non-Designer's Design Book" 4대 레이아웃 원칙.

### Contrast (대비)
다른 것은 **확실히** 다르게. 약간의 차이는 혼란, 확실한 대비는 위계를 만든다.
- 16px regular vs 18px medium ❌ (차이가 너무 작음)
- 14px regular vs 24px bold ✅ (명확한 대비)

### Repetition (반복)
시각적 요소를 일관되게 반복하여 통일감을 만든다.
- 모든 섹션 제목에 같은 스타일, 모든 카드에 같은 border-radius
- 디자인 토큰이 바로 이 원칙의 구현체

### Alignment (정렬)
모든 요소는 다른 요소와 시각적 연결을 가져야 한다. 임의로 배치하지 않는다.
- 좌측 정렬이 가독성 최고 (LTR)
- 중앙 정렬은 짧은 텍스트, 제목에만

### Proximity (근접성)
관련 있는 항목은 가깝게, 무관한 항목은 멀리.
- 라벨 ↔ 입력 필드: 4-8px
- 폼 그룹 간: 24-32px
- 섹션 간: 48-64px

---

## 5. 실무 적용 가이드

### 디자인 의사결정 프레임워크

1. 사용자 목표에 부합하는가? (기능적 가치)
2. 이해하기 쉬운가? (인지 부하 최소화)
3. 일관적인가? (디자인 시스템과 정합)
4. 접근 가능한가? (모든 사용자)
5. 구현 가능한가? (기술적 실현 가능성)
6. 유지보수 가능한가? (장기적 관점)

### 안티패턴

- **Decoration over function**: 장식이 기능을 방해
- **Inconsistency**: 같은 패턴을 다르게 표현
- **Information overload**: 한 화면에 너무 많은 정보
- **Mystery meat navigation**: 어디를 클릭해야 할지 모름
- **Dark patterns**: 사용자를 속이는 디자인 (확인 해제된 체크박스, 숨겨진 비용)

---

## 참고

- Dieter Rams, "Less and More"
- Robin Williams, "The Non-Designer's Design Book"
- Don Norman, "The Design of Everyday Things"
- Laws of UX (lawsofux.com)
