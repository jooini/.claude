# 병렬 실행 전략

> 독립 가능한 작업은 동시에 실행하고, 의존성이 있는 작업은 계약으로 분리한다.

---

## 1. 병렬 실행의 목적

병렬 실행은 속도만을 위한 것이 아니다.

서로 다른 전문성이 같은 문제를 동시에 검토하게 만들어 품질을 높인다.

**병렬 실행의 효과:**
- 작업 대기 시간 감소
- 도메인별 전문성 활용
- 대안 설계 확보
- 리뷰 지연 감소
- 전체 작업 흐름의 병목 제거

---

## 2. 병렬화 가능한 작업

| 작업 | 병렬 가능 여부 | 조건 |
|------|----------------|------|
| Backend와 Frontend 구현 | 가능 | API 계약 고정 |
| 구현과 테스트 설계 | 가능 | 요구사항 명확 |
| 구현과 문서 초안 | 가능 | 변경 방향 확정 |
| 코드 리뷰와 QA 시나리오 | 가능 | diff 또는 설계 제공 |
| 성능 분석과 리팩터 | 부분 가능 | 측정 기준 공유 |
| 같은 파일 수정 | 불가 | 충돌 위험 |

---

## 3. 의존성 분석

병렬 실행 전 의존성을 나눈다.

```markdown
## 의존성
- API 계약 작성 → BE/FE 병렬 가능
- DB migration 작성 → repository 구현 가능
- 프롬프트 평가셋 작성 → prompt 개선 가능
- 배포 설정 확정 → smoke test 가능
```

### 의존성 유형

| 유형 | 설명 | 처리 |
|------|------|------|
| hard dependency | 먼저 끝나야 시작 가능 | 순차 |
| contract dependency | 계약만 있으면 시작 가능 | 병렬 |
| soft dependency | 참고하면 좋지만 필수 아님 | 병렬 |
| conflict dependency | 같은 파일 수정 | 분리 또는 단일 담당 |

---

## 4. run_in_background 사고방식

긴 작업은 백그라운드로 돌리고, 메인 흐름은 다른 독립 작업을 진행한다.

**백그라운드에 적합한 작업:**
- 전체 테스트
- 대규모 검색
- 빌드
- 정적 분석
- 긴 benchmark
- 서브에이전트 리뷰

```typescript
const tests = Skill("test-runner").run({
  command: "npm test",
  run_in_background: true,
});

const review = Agent("code-reviewer", {
  task: "현재 diff 리뷰",
  run_in_background: true,
});
```

---

## 5. 병렬 프롬프트 설계

병렬 에이전트에게는 소유권과 출력 형식을 명확히 준다.

```python
Agent("backend-developer", task="""
주문 취소 API를 구현한다.
소유 파일: server/order/**
금지 파일: web/**
계약: POST /orders/:id/cancel
출력: 변경 파일, 테스트 명령, 남은 위험
""")

Agent("frontend-developer", task="""
주문 취소 UI를 구현한다.
소유 파일: web/orders/**
금지 파일: server/**
계약: POST /orders/:id/cancel
출력: 변경 파일, 화면 상태, 테스트 명령
""")
```

---

## 6. 결과 수렴

병렬 결과는 자동으로 맞지 않는다.

dev-lead가 수렴한다.

**수렴 체크:**
- 계약 이름 일치
- enum 값 일치
- 에러 코드 일치
- fixture 일치
- import 경로 일치
- 테스트 실행 순서 일치

### 수렴표 예시

| 항목 | Backend | Frontend | 판단 |
|------|---------|----------|------|
| 상태 값 | `CANCELLED` | `cancelled` | Frontend 수정 |
| 실패 코드 | `ORDER_LOCKED` | 없음 | toast 매핑 추가 |
| null 처리 | `null` | `undefined` | 계약은 null |

---

## 7. 충돌 방지

병렬 실행에서 가장 흔한 실패는 파일 충돌이다.

**방지 규칙:**
- 같은 파일은 한 명만 수정한다.
- 공통 타입은 먼저 계약으로 만든다.
- shared util 수정은 dev-lead가 직접 통합한다.
- 대형 리팩터와 기능 구현을 동시에 하지 않는다.

```typescript
Agent("worker-a", {
  ownership: ["server/order/**"],
  forbidden: ["server/common/**", "web/**"],
});

Agent("worker-b", {
  ownership: ["web/orders/**"],
  forbidden: ["server/**"],
});
```

---

## 8. 병렬 리뷰

리뷰도 병렬화할 수 있다.

| 리뷰어 | 관점 |
|--------|------|
| code-reviewer | 버그, 설계, 보안 |
| qa | 테스트 공백, 시나리오 |
| designer | UX, 접근성, 레이아웃 |
| ops-lead | 배포, 설정, 모니터링 |
| data-analyst | 지표, 쿼리, 데이터 품질 |

### 병렬 리뷰 요청

```markdown
같은 diff를 보되 각자 관점만 리뷰한다.
- code-reviewer: P0/P1 버그
- qa: 누락 테스트
- designer: 사용자 흐름
중복 코멘트는 dev-lead가 병합한다.
```

---

## 9. 병렬 실행 금지 상황

- 요구사항이 아직 불명확하다.
- API 계약이 없다.
- 같은 핵심 파일을 여러 명이 수정해야 한다.
- 보안 정책 결정이 필요하다.
- 데이터 마이그레이션 순서가 확정되지 않았다.
- 이전 단계 결과에 따라 다음 작업이 크게 달라진다.

---

## 10. 병렬 실행 체크리스트

- [ ] 각 작업이 독립적인가?
- [ ] 계약 또는 입력이 고정되었는가?
- [ ] 파일 소유권이 충돌하지 않는가?
- [ ] 결과 출력 형식이 같은가?
- [ ] 수렴 책임자가 정해졌는가?
- [ ] 실패 시 대체 경로가 있는가?
- [ ] 백그라운드 작업 완료를 기다릴 시점이 정해졌는가?

---

## 11. 병렬 실행 결과 보고

```markdown
## 병렬 실행 결과

### Backend
- 완료:
- 이슈:

### Frontend
- 완료:
- 이슈:

### QA
- 완료:
- 이슈:

### 통합 판단
- 수정 필요:
- 최종 테스트:
```

---

## 12. 최종 기준

병렬 실행은 "동시에 시작"이 아니라 "충돌 없이 독립 수행하고, 계약 기준으로 빠르게 수렴"하는 것이다.
