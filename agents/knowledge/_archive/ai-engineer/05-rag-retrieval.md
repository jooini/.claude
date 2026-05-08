# RAG 검색 전략

> 참조 링크: https://docs.pinecone.io/guides/data/understanding-hybrid-search, https://arxiv.org/abs/2212.10496

---

## 1. 검색 방식 비교

| 방식 | 원리 | 장점 | 단점 |
|------|------|------|------|
| **Dense (Semantic)** | 임베딩 벡터 유사도 | 의미적 유사성 포착 | 키워드 정확 매칭 약함 |
| **Sparse (Lexical)** | BM25, TF-IDF | 키워드 정확 매칭 | 동의어, 의미 유사성 놓침 |
| **Hybrid** | Dense + Sparse 결합 | 양쪽 장점 결합 | 가중치 튜닝 필요 |

## 2. Hybrid Search

Dense 검색과 Sparse 검색을 결합해 검색 품질을 높인다.

### 가중치 결합 (Convex Combination)

```typescript
interface HybridSearchConfig {
  alpha: number; // 0 = sparse only, 1 = dense only, 보통 0.5~0.7
  topK: number;
}

class HybridSearcher {
  private denseSearcher: DenseSearcher;   // 벡터 검색
  private sparseSearcher: SparseSearcher; // BM25 검색
  private config: HybridSearchConfig;

  async search(query: string): Promise<SearchResult[]> {
    // 동시에 두 검색 실행
    const [denseResults, sparseResults] = await Promise.all([
      this.denseSearcher.search(query, this.config.topK * 2),
      this.sparseSearcher.search(query, this.config.topK * 2),
    ]);

    // 점수 정규화 (min-max)
    const normalizedDense = this.normalizeScores(denseResults);
    const normalizedSparse = this.normalizeScores(sparseResults);

    // 가중치 결합
    const combined = this.mergeResults(normalizedDense, normalizedSparse);
    return combined.slice(0, this.config.topK);
  }

  private mergeResults(dense: SearchResult[], sparse: SearchResult[]): SearchResult[] {
    const scoreMap = new Map<string, number>();

    for (const r of dense) {
      scoreMap.set(r.id, (scoreMap.get(r.id) ?? 0) + this.config.alpha * r.score);
    }
    for (const r of sparse) {
      scoreMap.set(r.id, (scoreMap.get(r.id) ?? 0) + (1 - this.config.alpha) * r.score);
    }

    return [...scoreMap.entries()]
      .sort(([, a], [, b]) => b - a)
      .map(([id, score]) => ({ id, score, content: this.getContent(id) }));
  }

  private normalizeScores(results: SearchResult[]): SearchResult[] {
    if (results.length === 0) return [];
    const min = Math.min(...results.map(r => r.score));
    const max = Math.max(...results.map(r => r.score));
    const range = max - min || 1;
    return results.map(r => ({ ...r, score: (r.score - min) / range }));
  }
}
```

### Reciprocal Rank Fusion (RRF)

점수 정규화 없이 순위 기반으로 결합하는 방법. 더 안정적.

```typescript
function reciprocalRankFusion(
  resultSets: SearchResult[][],
  k: number = 60, // RRF 상수, 보통 60
): SearchResult[] {
  const scoreMap = new Map<string, number>();

  for (const results of resultSets) {
    for (let rank = 0; rank < results.length; rank++) {
      const docId = results[rank].id;
      const rrfScore = 1 / (k + rank + 1); // 순위 기반 점수
      scoreMap.set(docId, (scoreMap.get(docId) ?? 0) + rrfScore);
    }
  }

  return [...scoreMap.entries()]
    .sort(([, a], [, b]) => b - a)
    .map(([id, score]) => ({ id, score }));
}
```

## 3. Reranking

1차 검색 결과를 Cross-Encoder 모델로 재정렬한다. Bi-Encoder(임베딩) 대비 정확도가 높지만 느리다.

### Cohere Rerank API

```typescript
class CohereReranker {
  private apiKey: string;

  async rerank(query: string, documents: string[], topN: number = 5): Promise<RerankResult[]> {
    const response = await fetch('https://api.cohere.ai/v1/rerank', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: 'rerank-v3.5',
        query,
        documents,
        top_n: topN,
        return_documents: true,
      }),
    });

    const result = await response.json();
    return result.results.map((r: any) => ({
      index: r.index,
      relevanceScore: r.relevance_score, // 0~1, 높을수록 관련성 높음
      document: r.document.text,
    }));
  }
}
```

### Reranking 파이프라인

```typescript
class RetrieveAndRerank {
  async search(query: string): Promise<Document[]> {
    // 1단계: 넓게 검색 (top-20~50)
    const candidates = await this.vectorStore.search(query, 30);

    // 2단계: 리랭킹으로 상위 5개 선별
    const reranked = await this.reranker.rerank(
      query,
      candidates.map(c => c.content),
      5,
    );

    // 3단계: 관련성 임계값 필터링
    return reranked
      .filter(r => r.relevanceScore > 0.3) // 임계값 아래 제거
      .map(r => candidates[r.index]);
  }
}
```

## 4. Query Expansion

사용자 질문을 확장하거나 변형해 검색 커버리지를 높인다.

### Multi-Query

```typescript
async function expandToMultiQuery(query: string, openai: OpenAI): Promise<string[]> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `사용자 질문을 다른 관점에서 3개의 검색 쿼리로 변환하세요.
JSON 배열로 반환하세요. 원본 질문의 의도를 유지해야 합니다.`,
      },
      { role: 'user', content: query },
    ],
    temperature: 0.7,
  });

  const queries = JSON.parse(response.choices[0].message.content ?? '[]');
  return [query, ...queries]; // 원본 포함 총 4개
}
```

### Sub-Query Decomposition

복잡한 질문을 하위 질문으로 분해한다.

```typescript
async function decomposeQuery(query: string, openai: OpenAI): Promise<string[]> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `복잡한 질문을 독립적으로 검색 가능한 하위 질문들로 분해하세요.
각 하위 질문은 원본 질문의 일부를 다루어야 합니다.
JSON 배열로 반환하세요.`,
      },
      { role: 'user', content: query },
    ],
  });

  return JSON.parse(response.choices[0].message.content ?? '[]');
}

// 예시: "NestJS에서 TypeORM으로 PostgreSQL 연결하고 마이그레이션 설정하는 방법"
// → ["NestJS에서 TypeORM 설정하는 방법", "TypeORM PostgreSQL 연결 설정", "TypeORM 마이그레이션 설정 방법"]
```

## 5. HyDE (Hypothetical Document Embeddings)

질문 대신 가상의 답변 문서를 생성하고, 그 임베딩으로 검색한다. 질문-문서 간 임베딩 불일치 문제를 해결한다.

```typescript
class HyDERetriever {
  async retrieve(query: string): Promise<Document[]> {
    // 1단계: 가상 답변 문서 생성
    const hypotheticalDoc = await this.generateHypotheticalAnswer(query);

    // 2단계: 가상 문서의 임베딩으로 검색 (질문 임베딩 대신)
    const embedding = await this.embed(hypotheticalDoc);
    return this.vectorStore.search(embedding, this.topK);
  }

  private async generateHypotheticalAnswer(query: string): Promise<string> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `질문에 대한 답변을 작성하세요. 
정확하지 않아도 됩니다. 관련 주제의 문서처럼 작성하세요.
200단어 이내로 작성하세요.`,
        },
        { role: 'user', content: query },
      ],
      temperature: 0.7,
    });

    return response.choices[0].message.content ?? '';
  }
}
```

### HyDE 적용 기준

| 적합한 경우 | 부적합한 경우 |
|------------|-------------|
| 짧은/모호한 질문 | 구체적 키워드 검색 |
| 도메인 특화 문서 검색 | 실시간 데이터 검색 |
| 개념적 질문 | 고유명사/코드 검색 |

## 6. Step-Back Prompting

구체적 질문을 추상화해서 더 넓은 범위의 문서를 검색한다.

```typescript
async function stepBackQuery(query: string, openai: OpenAI): Promise<string> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `구체적인 질문을 더 추상적이고 일반적인 질문으로 변환하세요.
원래 질문에 답하는 데 필요한 배경 지식을 검색할 수 있는 질문이어야 합니다.
변환된 질문만 반환하세요.`,
      },
      { role: 'user', content: query },
    ],
  });

  return response.choices[0].message.content ?? query;
}

// 예시: "Next.js 14 App Router에서 서버 컴포넌트의 캐시 무효화 방법" 
// → "Next.js App Router의 캐싱 메커니즘과 데이터 재검증 전략"
```

## 7. 검색 전략 선택 가이드

| 상황 | 권장 전략 |
|------|----------|
| 키워드 + 의미 검색 모두 필요 | Hybrid Search (alpha 0.5~0.7) |
| 검색 정확도 최우선 | Retrieve → Rerank (top-30 → top-5) |
| 짧은/모호한 질문이 많은 경우 | HyDE + Dense Search |
| 복합 질문 | Sub-Query Decomposition |
| 다양한 표현의 질문 | Multi-Query Expansion |
| 배경 지식이 필요한 질문 | Step-Back Prompting |

## 8. 메타데이터 필터링

벡터 검색에 메타데이터 필터를 결합해 검색 범위를 좁힌다.

```typescript
// Pinecone 예시
const results = await index.query({
  vector: queryEmbedding,
  topK: 10,
  filter: {
    category: { $eq: 'technical' },
    date: { $gte: '2024-01-01' },
    language: { $in: ['ko', 'en'] },
  },
  includeMetadata: true,
});

// pgvector 예시 (SQL)
// SELECT content, embedding <=> $1 AS distance
// FROM documents
// WHERE category = 'technical' AND created_at >= '2024-01-01'
// ORDER BY distance
// LIMIT 10;
```
