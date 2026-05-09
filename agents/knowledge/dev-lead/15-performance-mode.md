# 성능 최적화 모드

> 측정 없이 최적화하지 않고, 병목별 전문 에이전트를 배치한다.

---

## 1. 성능 모드의 목적

성능 최적화는 감으로 하는 리팩터링이 아니다.

dev-lead는 먼저 측정 지표를 정하고, 병목을 확인한 뒤, 최소 변경으로 개선한다.

**핵심 원칙:**
- 측정 전 최적화 금지
- 병목 위치를 먼저 분리
- 전후 수치를 비교
- 정확성 회귀를 함께 확인
- 복잡도 증가를 경계

---

## 2. 성능 모드 진입 조건

- 응답 시간이 목표를 초과함
- 쿼리가 느림
- 프론트 렌더링이 버벅임
- 배치/ETL 시간이 증가함
- LLM 비용 또는 latency가 높음
- 메모리 사용량 증가

---

## 3. 성능 지표 정의

| 영역 | 지표 |
|------|------|
| API | p50, p95, p99 latency, error rate |
| DB | query time, rows scanned, lock wait |
| Frontend | LCP, INP, CLS, bundle size |
| Batch | throughput, duration, retry count |
| AI | latency, token count, cost, eval score |
| Infra | CPU, memory, connection pool, queue depth |

### 지표 템플릿

```markdown
## 목표 지표
- 현재: p95 1.8s
- 목표: p95 700ms 이하
- 측정 환경: staging
- 트래픽 조건: 최근 7일 평균 요청 패턴
```

---

## 4. 데이터/쿼리 병목

쿼리 성능은 data-analyst를 먼저 배치한다.

```python
Agent("data-analyst", task="""
주문 목록 조회 쿼리의 병목을 분석하라.
EXPLAIN, 인덱스 후보, rows scanned, 정합성 리스크를 포함하라.
코드 수정 없이 분석 결과와 개선안을 보고하라.
""")
```

### 쿼리 최적화 체크리스트

- [ ] 실제 느린 쿼리를 확인했는가?
- [ ] EXPLAIN을 봤는가?
- [ ] where/order by 인덱스가 맞는가?
- [ ] N+1이 아닌가?
- [ ] 페이지네이션이 있는가?
- [ ] 결과 정합성이 유지되는가?

---

## 5. Backend 성능

Backend 병목은 호출 흐름과 리소스 사용량을 본다.

| 병목 | 대응 |
|------|------|
| N+1 query | fetch join, batch load |
| 불필요한 외부 호출 | cache, request coalescing |
| lock 경합 | transaction 범위 축소 |
| CPU 연산 | algorithm 개선, memoization |
| serialization | 응답 크기 축소 |

```typescript
Agent("backend-developer", {
  task: "주문 목록 API p95 개선",
  evidence: "N+1 query detected in OrderItem loading",
  constraints: ["응답 schema 변경 금지", "정렬 결과 유지"],
  verification: ["query count test", "integration test"],
});
```

---

## 6. Frontend 성능

Frontend 성능은 사용자 체감 지표를 우선한다.

**주요 원인:**
- 과도한 re-render
- 큰 bundle
- 이미지 최적화 부족
- list virtualization 없음
- blocking script
- 비효율적 상태 관리

```typescript
Agent("frontend-developer", {
  task: "검색 결과 화면 렌더링 지연 개선",
  metrics: ["INP", "render count", "bundle size"],
  constraints: [
    "디자인 변경 금지",
    "키보드 접근성 유지",
  ],
});
```

### FE 검증

- Lighthouse 또는 Web Vitals
- React Profiler
- Playwright interaction timing
- bundle analyzer
- 모바일 viewport 확인

---

## 7. AI/LLM 성능

AI 성능은 latency, token, 품질을 함께 본다.

| 최적화 | 리스크 |
|--------|--------|
| 짧은 프롬프트 | 품질 하락 |
| 작은 모델 | 정확도 하락 |
| caching | stale answer |
| RAG top-k 축소 | recall 하락 |
| streaming | 구현 복잡도 증가 |

```python
Agent("ai-engineer", task="""
문의 요약 LLM 호출의 latency와 token 비용을 줄인다.
품질 eval 20개를 유지하고, 전후 비용과 latency를 표로 보고하라.
""")
```

---

## 8. Codex 병렬 대안 구현

성능 최적화는 대안 비교가 유용하다.

```typescript
Agent("codex", {
  task: "주문 목록 API 성능 개선 대안 2개 제시",
  mode: "parallel-impl",
  constraints: [
    "응답 schema 유지",
    "DB migration 없는 안 1개 포함",
    "측정 방법 포함",
  ],
});
```

### 대안 비교표

| 대안 | 예상 개선 | 리스크 | 구현 비용 |
|------|-----------|--------|-----------|
| 인덱스 추가 | 높음 | migration 필요 | 중 |
| 쿼리 분리 | 중 | 코드 복잡도 | 중 |
| 캐시 추가 | 높음 | stale data | 높음 |

---

## 9. 성능 검증

최적화는 전후 비교가 없으면 완료가 아니다.

```markdown
## 성능 결과
- Before: p95 1.8s, query 42회
- After: p95 620ms, query 4회
- 정확성 테스트: 통과
- 회귀 리스크: 캐시 미사용, schema 변경 없음
```

---

## 10. 성능 안티패턴

- 측정 없이 캐시부터 넣는다.
- 테스트를 깨고 빠르게 만든다.
- p50만 보고 p95를 무시한다.
- 데이터 크기가 작은 로컬 결과만 믿는다.
- 프론트 최적화를 하면서 접근성을 깨뜨린다.
- LLM 비용을 줄이며 eval score를 보지 않는다.

---

## 11. 성능 모드 체크리스트

- [ ] 목표 지표가 정의되었는가?
- [ ] 실제 병목을 측정했는가?
- [ ] 병목에 맞는 에이전트를 배치했는가?
- [ ] 대안과 리스크를 비교했는가?
- [ ] 전후 수치를 기록했는가?
- [ ] 정확성 회귀 테스트를 실행했는가?
- [ ] 복잡도 증가가 합리적인가?

---

## 12. 최종 기준

성능 최적화 완료는 "빨라진 느낌"이 아니라, 같은 동작을 유지하면서 핵심 지표가 개선되었다는 증거다.
