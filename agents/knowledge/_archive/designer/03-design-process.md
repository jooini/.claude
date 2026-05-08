# Design Process

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-designer/design-process

---

## 1. 더블 다이아몬드 (Double Diamond)

British Design Council이 제안한 프로세스 모델. 발산(Diverge)과 수렴(Converge)의 반복.

```
Diamond 1: 올바른 문제 찾기         Diamond 2: 올바른 솔루션 찾기
    Discover → Define                  Develop → Deliver
    (발산)    (수렴)                    (발산)    (수렴)
```

**Discover (발견):** 사용자 인터뷰, 필드 관찰, 경쟁사 분석, 데이터 분석

**Define (정의):** Affinity mapping, Persona/JTBD, HMW 질문, Problem Statement

**Develop (개발):** 아이데이션 워크샵, 와이어프레임/프로토타입, 사용성 테스트, 반복 개선

**Deliver (전달):** High-fidelity 디자인, 개발 핸드오프, QA, 출시 후 모니터링

---

## 2. Design Sprint (Google Ventures, 5일)

Jake Knapp이 개발한 5일 집중 프로세스. 큰 문제를 빠르게 검증.

| 요일 | 활동 | 산출물 |
|------|------|--------|
| **Monday** | 장기 목표 설정, Sprint 질문, 문제 맵핑, 타겟 선정 | Sprint 질문, HMW 메모 |
| **Tuesday** | Lightning Demos, Crazy 8s, Solution Sketch | 솔루션 스케치 |
| **Wednesday** | 스케치 전시, Heat Map 투표, Decider 결정 | 스토리보드 |
| **Thursday** | Figma로 사실적 프로토타입 제작 | 프로토타입 |
| **Friday** | 5명 사용성 테스트 (각 60분) | 패턴 발견, 결과 |

**적합 상황:** 새 제품/기능 방향성 검증, 팀 간 합의 필요, 시간 제한된 상황

---

## 3. 디자인 씽킹 (Design Thinking)

IDEO/Stanford d.school의 5단계 프로세스.

**1. Empathize (공감)** — 관찰 + 인터뷰. Empathy Map (Says/Thinks/Does/Feels)

**2. Define (정의)** — POV 문장: "[사용자]는 [니즈]가 필요하다. 왜냐하면 [인사이트]이기 때문이다." → HMW 질문 도출

**3. Ideate (아이디어)** — 브레인스토밍(판단 유보, 양이 질), Mind Mapping, SCAMPER

**4. Prototype (프로토타입)** — 빠르고 저렴하게. 핵심 가설만 검증할 정도면 OK

**5. Test (테스트)** — 관찰 + 피드백. 인사이트 → 다시 Empathize 또는 Ideate로

비선형: 단계 간 자유롭게 이동 가능.

---

## 4. Lean UX

Eric Ries의 Lean Startup을 UX에 적용. 가설 기반 반복.

```
가설 → 최소 실험 → 측정 → 학습 → (반복)
```

### Lean UX Canvas

1. **Business Problem**: 해결할 비즈니스 문제
2. **Business Outcomes**: 측정 가능한 비즈니스 결과
3. **Users**: 대상 사용자
4. **User Outcomes & Benefits**: 사용자가 얻는 가치
5. **Solutions**: 가능한 솔루션 아이디어
6. **Hypotheses**: "우리는 [이 기능]이 [이 사용자]에게 [이 결과]를 가져올 것이라고 믿는다"
7. **MVP**: 가설 검증을 위한 최소 제품
8. **Experiments**: 가설 검증 방법

| | 전통적 UX | Lean UX |
|--|---------|---------|
| 산출물 | 상세 문서, 와이어프레임 | 가설, 실험 결과 |
| 프로세스 | 순차적 | 반복적, 병렬적 |
| 리서치 | 대규모, 선행 | 지속적, 작은 규모 |

---

## 5. Jobs to Be Done (JTBD)

Clayton Christensen의 프레임워크. 사용자의 "직업(Job)"에 초점.

```
When [상황], I want to [동기], so I can [기대 결과].

예시:
"When I'm commuting on the subway,
I want to catch up on industry news,
so I can stay informed without dedicating extra time."
```

**JTBD vs Persona:** Persona는 "누구"에 초점, JTBD는 "무엇을 하려는지"에 초점. 같은 Job을 가진 다양한 Persona가 존재할 수 있음.

---

## 6. 프로세스 선택 가이드

| 상황 | 권장 프로세스 |
|------|-------------|
| 새 제품 초기 탐색 | 디자인 씽킹 + 더블 다이아몬드 |
| 빠른 방향 검증 (1주) | Design Sprint |
| 지속적 개선 | Lean UX |
| 기능 추가/개선 | 간소화된 더블 다이아몬드 |
| 비즈니스 가설 검증 | Lean UX |

---

## 7. 실무 팁

- **프로세스 ≠ 교조**: 상황에 맞게 단계를 건너뛰거나 축소. 프로세스는 도구이지 목적이 아님
- **시간 관리**: 발산 단계에 시간 제한 두기. 60% 작업 → 피드백 → 나머지 40%
- **문서화**: 프로세스 결과물보다 **결정과 근거**를 기록. "A 대신 B를 선택한 이유"
