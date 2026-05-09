# 에이전트 선택 매트릭스

> 복잡도 × 도메인 기준으로 어떤 에이전트를 호출할지 결정한다.

---

## 1. 선택 매트릭스의 목적

에이전트 선택은 감이 아니라 작업의 구조로 결정한다.

dev-lead는 먼저 복잡도와 도메인을 정한 뒤 최소 충분 팀을 구성한다.

**선택 기준:**
- 주 도메인을 담당할 구현 에이전트
- 품질을 검증할 리뷰/테스트 에이전트
- 리스크를 낮출 전문 자문 에이전트
- 병렬 대안을 만들 보조 구현 에이전트

---

## 2. 기본 에이전트 목록

| 역할 | 에이전트 | 주 사용 상황 |
|------|----------|--------------|
| 백엔드 구현 | backend-developer | API, DB, 인증, 서비스 로직 |
| 프론트 구현 | frontend-developer | UI, 상태, 브라우저 동작 |
| AI 구현 | ai-engineer | LLM, RAG, 모델 라우팅 |
| 데이터 분석 | data-analyst | 쿼리, 지표, ETL, 분석 |
| 운영 | ops-lead | Docker, 배포, 인프라, 모니터링 |
| 리뷰 | code-reviewer | 코드 품질, 보안, 설계 |
| 테스트 | code-tester | 테스트 실행, 실패 분석 |
| QA | qa | 테스트 전략, 시나리오, 회귀 |
| 디자인 | designer | UX, UI 밀도, 접근성 |
| 제품 | po | 요구사항, 수용 기준 |
| 프롬프트 | prompt-engineer | 프롬프트, 평가, 지침 |
| 디버그 | debug-master | 재현, 원인 분석, 복구 |

---

## 3. S 작업 매트릭스

S 작업은 과도한 위임을 피한다.

| 도메인 | 구현 | 검증 |
|--------|------|------|
| Backend | backend-developer | targeted test |
| Frontend | frontend-developer | visual/manual check |
| Fullstack | backend 또는 frontend 주도 | contract smoke test |
| Data | data-analyst | sample query |
| AI | ai-engineer | prompt regression |
| DevOps | ops-lead | dry-run 또는 config check |

### S 작업 호출 예시

```typescript
Agent("frontend-developer", {
  task: "ProfileCard의 empty state 문구 수정",
  scope: "one component",
});
```

---

## 4. M 작업 매트릭스

M 작업은 구현 + 리뷰 + 테스트를 기본으로 한다.

| 도메인 | 주 구현 | 보조 | 필수 검증 |
|--------|---------|------|-----------|
| Backend | backend-developer | code-reviewer | unit/integration |
| Frontend | frontend-developer | designer | component/e2e smoke |
| Fullstack | backend + frontend | qa | contract + integration |
| Data | data-analyst | backend-developer | query result check |
| AI | ai-engineer | prompt-engineer | eval sample |
| DevOps | ops-lead | code-reviewer | dry-run + rollback |

### M 작업 패턴

```python
backend = Agent("backend-developer", task="쿠폰 조회 API 구현")
review = Agent("code-reviewer", task="권한과 캐시 무효화 리뷰")
test = Agent("code-tester", task="관련 테스트 실행")
```

---

## 5. L 작업 매트릭스

L 작업은 Phase 전체와 병렬 검증이 필요하다.

| 도메인 | Phase 0 | Phase 1 | Phase 2 | Phase 3 |
|--------|---------|---------|---------|---------|
| Backend | explorer/Gemini | backend + reviewer | backend | reviewer + tester |
| Frontend | explorer | designer + frontend | frontend | qa + visual check |
| Fullstack | Gemini scan | backend + frontend 계약 | 병렬 구현 | contract + e2e |
| Data | data scan | data-analyst | backend/data | result validation |
| AI | eval scan | ai + prompt | ai-engineer | qa + eval |
| DevOps | ops impact | ops design | ops-lead | dry-run + monitor |

### L 작업 병렬 예시

```typescript
const contract = Skill("api-contract").draft("주문 취소 플로우");

Agent("backend-developer", {
  task: "주문 취소 API 구현",
  contract,
  ownership: ["server/order/**"],
});

Agent("frontend-developer", {
  task: "주문 취소 버튼과 상태 반영",
  contract,
  ownership: ["web/order/**"],
});

Agent("qa", {
  task: "취소 가능/불가/중복 클릭 시나리오 작성",
  contract,
});
```

---

## 6. XL 작업 매트릭스

XL은 에이전트 선택보다 작업 분해가 먼저다.

| 단계 | 담당 | 산출물 |
|------|------|--------|
| 문제 정의 | po + dev-lead | 목표, 비목표, 수용 기준 |
| 영향 분석 | explorer/Gemini + ops | 시스템 영향도 |
| 설계 | domain agents + reviewer | 아키텍처와 마이그레이션 |
| 분할 | dev-lead | 단계별 PR 계획 |
| 구현 | worker/domain agents | 독립 작업 단위 |
| 검증 | qa + tester + reviewer | 단계별 품질 게이트 |

### XL 금지사항

- 한 에이전트에게 전체 구현을 맡기지 않는다.
- 계약 없이 병렬 구현하지 않는다.
- 리뷰와 테스트를 마지막에 몰아서 하지 않는다.
- 롤백 전략 없이 운영 영향 변경을 진행하지 않는다.

---

## 7. 리스크 기반 추가 배치

| 리스크 | 추가 에이전트 | 이유 |
|--------|---------------|------|
| 보안 | code-reviewer | 인증/인가 우회 점검 |
| UX 품질 | designer | 사용성, 접근성 확인 |
| 장애 가능성 | ops-lead | 배포와 모니터링 점검 |
| 불명확한 요구사항 | po | 목표와 수용 기준 정리 |
| 테스트 공백 | qa | 테스트 전략 설계 |
| 성능 병목 | data-analyst 또는 ops-lead | 측정과 병목 분석 |

---

## 8. 선택 알고리즘

```typescript
type Domain = "Backend" | "Frontend" | "Fullstack" | "Data" | "AI" | "DevOps";
type Size = "S" | "M" | "L" | "XL";

function selectAgents(size: Size, domain: Domain): string[] {
  const base = {
    Backend: ["backend-developer"],
    Frontend: ["frontend-developer"],
    Fullstack: ["backend-developer", "frontend-developer"],
    Data: ["data-analyst"],
    AI: ["ai-engineer", "prompt-engineer"],
    DevOps: ["ops-lead"],
  }[domain];

  if (size === "S") return base;
  if (size === "M") return [...base, "code-reviewer", "code-tester"];
  if (size === "L") return ["explorer", ...base, "qa", "code-reviewer", "code-tester"];
  return ["po", "explorer", ...base, "qa", "code-reviewer", "ops-lead"];
}
```

---

## 9. 프롬프트에 반드시 넣을 정보

- 작업 목표
- 변경 범위
- 소유 파일 또는 디렉토리
- 금지할 파일
- 입력으로 제공되는 사전 분석 요약
- 기대 산출물
- 검증 방법
- 충돌 시 우선순위

---

## 10. 선택 체크리스트

- [ ] 복잡도 분류가 끝났는가?
- [ ] 주 도메인과 보조 도메인을 나눴는가?
- [ ] 구현자와 검증자가 분리되었는가?
- [ ] 동일 파일을 여러 에이전트가 수정하지 않는가?
- [ ] 리스크에 맞는 전문 리뷰어가 있는가?
- [ ] 하위 에이전트에게 충분하지만 과하지 않은 컨텍스트를 줬는가?
- [ ] 최종 수렴 책임자가 dev-lead로 남아 있는가?

---

## 11. 최종 기준

좋은 에이전트 선택은 "가장 많은 사람을 부르는 것"이 아니라 "실패할 가능성이 큰 지점을 전문성으로 막는 것"이다.
