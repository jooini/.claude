# AI/ML 모드 오케스트레이션

> ai-engineer, prompt-engineer, data-analyst, qa를 조합해 모델 품질과 시스템 품질을 함께 검증한다.

---

## 1. AI/ML 모드의 목적

AI 기능은 일반 기능과 다르게 정답이 확정되지 않는 경우가 많다.

dev-lead는 모델 호출, 프롬프트, 데이터, 평가, 운영 비용을 함께 관리한다.

**핵심 목표:**
- 품질 기준을 평가셋으로 고정한다.
- 프롬프트 변경을 테스트 가능하게 만든다.
- RAG와 데이터 품질을 분리해서 본다.
- latency와 비용을 함께 관리한다.
- 실패 응답과 fallback을 설계한다.

---

## 2. AI/ML 모드 진입 조건

- LLM 프롬프트를 작성하거나 수정함
- RAG 검색 품질을 개선함
- 모델 라우팅을 변경함
- embedding 또는 vector DB를 다룸
- classification/summarization/extraction 기능
- hallucination, safety, refusal 이슈
- 비용 또는 latency 최적화

---

## 3. 에이전트 조합

| 역할 | 에이전트 | 책임 |
|------|----------|------|
| AI 설계 | ai-engineer | 모델 구조, 도구 호출, RAG |
| 프롬프트 | prompt-engineer | 지침, 예시, 출력 형식 |
| 데이터 | data-analyst | 평가셋, 로그 분석, 분포 |
| QA | qa | 테스트 시나리오, 실패 케이스 |
| Backend | backend-developer | API 통합, 저장, 권한 |
| Ops | ops-lead | 비용, rate limit, observability |

---

## 4. AI 작업 분류

| 유형 | 핵심 질문 | 주 담당 |
|------|-----------|---------|
| Prompt | 지침이 안정적인가? | prompt-engineer |
| RAG | 필요한 문서를 찾는가? | ai-engineer |
| Eval | 품질을 측정하는가? | qa + data |
| Routing | 어떤 모델을 쓸 것인가? | ai-engineer |
| Tool use | 도구 호출이 안전한가? | ai-engineer |
| Product UX | 실패를 어떻게 보여줄 것인가? | frontend + designer |

---

## 5. 프롬프트 변경 패턴

프롬프트는 코드처럼 리뷰하고 테스트한다.

```typescript
Agent("prompt-engineer", {
  task: "고객 문의 분류 프롬프트 개선",
  inputs: [
    "현재 프롬프트",
    "오분류 사례 20개",
    "허용 라벨 목록",
  ],
  output: [
    "개선 프롬프트",
    "변경 이유",
    "실패 가능 케이스",
  ],
});
```

### 프롬프트 체크리스트

- [ ] 출력 형식이 명확한가?
- [ ] 금지 행동이 구체적인가?
- [ ] 모호한 입력 처리 규칙이 있는가?
- [ ] 예시가 과적합을 만들지 않는가?
- [ ] 언어/톤 요구사항이 명시되었는가?
- [ ] 평가셋으로 회귀 확인 가능한가?

---

## 6. 평가셋 설계

AI 기능은 평가셋 없이 개선 여부를 판단하기 어렵다.

| 평가 항목 | 예시 |
|-----------|------|
| 정확도 | 라벨이 정답과 일치 |
| 형식 준수 | JSON schema valid |
| 안전성 | 금지 응답 회피 |
| 근거성 | 출처 기반 답변 |
| 비용 | 평균 token |
| latency | p95 응답 시간 |

```python
Agent("data-analyst", task="""
문의 분류 평가셋을 구성한다.
라벨별 최소 20개, 애매한 케이스 10개, 과거 오분류 사례를 포함하라.
출력은 csv schema와 평가 지표로 작성하라.
""")
```

---

## 7. RAG 작업

RAG 문제는 검색 문제와 생성 문제를 분리한다.

| 증상 | 원인 후보 | 담당 |
|------|-----------|------|
| 관련 문서를 못 찾음 | chunking, embedding, top-k | ai-engineer |
| 문서는 찾지만 답이 틀림 | prompt, grounding | prompt-engineer |
| 오래 걸림 | vector query, rerank | ai-engineer |
| 출처 누락 | response format | prompt-engineer |

### RAG 분석 프롬프트

```typescript
Agent("ai-engineer", {
  task: "RAG 검색 품질 분석",
  checks: [
    "query rewrite",
    "chunk size",
    "top-k recall",
    "reranker need",
    "source citation",
  ],
});
```

---

## 8. Tool Calling 안전성

도구 호출은 권한과 side effect를 확인한다.

**확인 항목:**
- 읽기 도구와 쓰기 도구가 분리되었는가?
- 사용자 확인이 필요한 도구가 있는가?
- 파라미터 검증이 있는가?
- 실패 시 재시도 정책이 있는가?
- 도구 출력이 프롬프트 인젝션을 일으키지 않는가?

```python
Agent("code-reviewer", task="""
LLM tool calling 구현을 리뷰한다.
권한, 파라미터 검증, side effect, prompt injection 관점으로 P0/P1을 찾아라.
""")
```

---

## 9. AI 비용/성능 관리

| 전략 | 적용 조건 | 검증 |
|------|-----------|------|
| 작은 모델 | 단순 분류/요약 | eval 유지 |
| 캐시 | 동일 입력 반복 | stale 정책 |
| 프롬프트 축소 | 긴 시스템 지침 | 품질 비교 |
| streaming | 체감 latency 중요 | UX 확인 |
| batch | 대량 처리 | 실패 재시도 |

### 비용 보고 예시

```markdown
## 비용 비교
- Before: 평균 3,200 tokens, p95 4.2s
- After: 평균 1,450 tokens, p95 2.1s
- Eval score: 0.91 → 0.90
- 판단: 비용 개선 대비 품질 하락 허용 가능
```

---

## 10. AI QA

QA는 deterministic 테스트와 eval을 함께 본다.

**테스트 유형:**
- schema validation
- golden set
- adversarial prompt
- empty input
- long input
- multilingual input
- tool failure

```typescript
Agent("qa", {
  task: "AI 답변 생성 기능의 실패 시나리오 작성",
  cases: ["empty context", "conflicting docs", "tool timeout", "unsafe request"],
});
```

---

## 11. AI/ML 모드 체크리스트

- [ ] AI 기능 유형을 분류했는가?
- [ ] 평가 기준이 있는가?
- [ ] 평가셋이 변경 전후 비교를 가능하게 하는가?
- [ ] 프롬프트와 모델 변경이 분리되어 있는가?
- [ ] RAG라면 검색과 생성 문제를 분리했는가?
- [ ] 비용과 latency를 확인했는가?
- [ ] fallback과 실패 응답을 설계했는가?
- [ ] tool calling의 side effect를 검토했는가?

---

## 12. 최종 기준

AI/ML 모드의 완료는 "답변이 좋아 보임"이 아니라, 평가 기준에서 품질·비용·안전성이 설명 가능한 상태가 되는 것이다.
