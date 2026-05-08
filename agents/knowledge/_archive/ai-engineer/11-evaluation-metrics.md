# Evaluation Metrics

> 참조 링크: https://docs.ragas.io/en/latest/concepts/metrics/, https://docs.llamaindex.ai/en/stable/module_guides/evaluating/

---

## 1. 검색 품질 메트릭

### Precision@k

상위 k개 결과 중 관련 문서 비율.

```python
def precision_at_k(retrieved: list[str], relevant: set[str], k: int) -> float:
    top_k = retrieved[:k]
    relevant_in_k = sum(1 for doc in top_k if doc in relevant)
    return relevant_in_k / k

# 예: 상위 5개 중 3개 관련 → Precision@5 = 0.6
```

### Recall@k

전체 관련 문서 중 상위 k개에 포함된 비율.

```python
def recall_at_k(retrieved: list[str], relevant: set[str], k: int) -> float:
    top_k = set(retrieved[:k])
    found = len(top_k & relevant)
    return found / len(relevant) if relevant else 0

# 관련 문서 10개 중 상위 5개에 7개 포함 → Recall@5 = 0.7
```

### MRR (Mean Reciprocal Rank)

첫 번째 관련 결과의 순위 역수 평균.

```python
def mrr(queries: list[tuple[list[str], set[str]]]) -> float:
    rr_sum = 0
    for retrieved, relevant in queries:
        for i, doc in enumerate(retrieved):
            if doc in relevant:
                rr_sum += 1 / (i + 1)
                break
    return rr_sum / len(queries)

# 첫 관련 결과가 3번째 → RR = 1/3
```

### NDCG (Normalized Discounted Cumulative Gain)

순위별 가중치를 적용한 검색 품질. 상위 순위일수록 가중치가 높다.

```python
import numpy as np

def dcg_at_k(relevances: list[float], k: int) -> float:
    relevances = relevances[:k]
    return sum(rel / np.log2(i + 2) for i, rel in enumerate(relevances))

def ndcg_at_k(relevances: list[float], k: int) -> float:
    dcg = dcg_at_k(relevances, k)
    ideal = dcg_at_k(sorted(relevances, reverse=True), k)
    return dcg / ideal if ideal > 0 else 0

# relevances = [3, 2, 0, 1, 0] → 상위부터 관련도 점수
```

### Hit Rate (Hit@k)

상위 k개에 관련 문서가 1개 이상 있는 쿼리 비율.

```python
def hit_rate(queries: list[tuple[list[str], set[str]]], k: int) -> float:
    hits = sum(1 for retrieved, relevant in queries
               if any(doc in relevant for doc in retrieved[:k]))
    return hits / len(queries)
```

## 2. 생성 품질 메트릭

### Faithfulness (충실도)

생성된 답변이 제공된 컨텍스트에 기반하는지 (hallucination 없는지).

```python
# RAGAS 방식: 답변의 각 문장이 컨텍스트에서 뒷받침되는지 LLM으로 판정
faithfulness_prompt = """
Given the context and the answer, determine if each statement in the answer
is supported by the context.

Context: {context}
Answer: {answer}

For each statement, respond with:
- SUPPORTED: the statement is directly supported by the context
- NOT_SUPPORTED: the statement cannot be verified from the context

Statements:
{statements}
"""

def calculate_faithfulness(supported: int, total: int) -> float:
    return supported / total if total > 0 else 0
```

### Answer Relevancy (답변 관련성)

답변이 질문에 얼마나 관련있는지.

```python
# 답변에서 역으로 질문을 생성하여 원래 질문과 유사도 비교
def answer_relevancy(question: str, answer: str, n_questions: int = 3) -> float:
    generated_questions = generate_questions_from_answer(answer, n=n_questions)
    similarities = [cosine_similarity(
        embed(question), embed(gq)
    ) for gq in generated_questions]
    return sum(similarities) / len(similarities)
```

### Context Precision

검색된 컨텍스트 중 답변 생성에 실제 사용된 비율.

### Context Recall

답변에 필요한 정보가 검색된 컨텍스트에 모두 포함되었는지.

## 3. 자동 평가 (LLM-as-Judge)

```typescript
const evaluationPrompt = `다음 질문에 대한 답변을 1-5 점으로 평가하세요.

질문: {question}
참조 답변: {reference}
생성 답변: {generated}

평가 기준:
- 정확성 (1-5): 사실적으로 정확한가?
- 완전성 (1-5): 질문에 충분히 답했는가?
- 관련성 (1-5): 질문과 관련있는 내용인가?
- 간결성 (1-5): 불필요한 내용 없이 간결한가?

JSON 형식으로 응답:
{"accuracy": N, "completeness": N, "relevance": N, "conciseness": N, "reasoning": "..."}`;
```

## 4. 평가 데이터셋 구성

### Golden Dataset

```typescript
interface EvalItem {
  id: string;
  question: string;
  expectedAnswer: string;                // 정답
  relevantDocIds: string[];              // 관련 문서 ID
  metadata: {
    difficulty: 'easy' | 'medium' | 'hard';
    category: string;
    requiresMultiHop: boolean;           // 여러 문서 조합 필요
  };
}

// 최소 50~100개 이상, 다양한 유형 포함
```

### 평가 실행

```typescript
async function evaluateRAG(evalSet: EvalItem[], ragPipeline: RAGPipeline) {
  const results = [];

  for (const item of evalSet) {
    const { answer, contexts } = await ragPipeline.query(item.question);

    results.push({
      id: item.id,
      question: item.question,
      generatedAnswer: answer,
      retrievedDocs: contexts.map(c => c.id),
      metrics: {
        precisionAt5: precision_at_k(contexts.map(c => c.id), new Set(item.relevantDocIds), 5),
        hitRate: contexts.some(c => item.relevantDocIds.includes(c.id)) ? 1 : 0,
        faithfulness: await evaluateFaithfulness(answer, contexts),
        relevancy: await evaluateRelevancy(item.question, answer),
      },
    });
  }

  return {
    items: results,
    averages: calculateAverages(results),
  };
}
```

## 5. 메트릭 선택 가이드

| 시나리오 | 우선 메트릭 | 이유 |
|---------|-----------|------|
| Q&A 챗봇 | Faithfulness, Hit@5 | hallucination 방지가 최우선 |
| 문서 검색 | NDCG@10, Precision@5 | 검색 순위 품질이 핵심 |
| 요약 생성 | Faithfulness, Completeness | 원문 기반 + 빠짐없이 |
| 코드 생성 | 실행 성공률, 테스트 통과율 | 실제 동작 여부가 핵심 |

## 6. 지표 대시보드

```typescript
// 정기 평가 결과 추적
interface EvalReport {
  timestamp: string;
  version: string;          // 파이프라인 버전
  dataset: string;          // 평가 데이터셋 이름
  metrics: {
    retrieval: { hitRate: number; precision5: number; mrr: number; ndcg10: number };
    generation: { faithfulness: number; relevancy: number; completeness: number };
  };
  comparison?: {            // 이전 버전 대비
    retrieval: Record<string, number>;
    generation: Record<string, number>;
  };
}
```
