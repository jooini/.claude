# RAG 아키텍처

> 참조 링크: https://arxiv.org/abs/2312.10997, https://docs.llamaindex.ai/en/stable/

---

## 1. RAG 패러다임 진화

| 세대 | 패턴 | 특징 |
|------|------|------|
| **Naive RAG** | Retrieve → Read | 단순 검색 + 생성. 빠르게 구축 가능 |
| **Advanced RAG** | Pre/Post-Retrieval 최적화 | 쿼리 변환, 리랭킹, 컨텍스트 압축 |
| **Modular RAG** | 교체 가능한 모듈 파이프라인 | 각 단계를 독립 모듈로 분리, 라우팅 |

## 2. Naive RAG

가장 기본적인 RAG 구현. 프로토타입이나 단순 Q&A에 적합하다.

```
[질문] → Embedding → Vector Search → Top-K 문서 → LLM → [답변]
```

### 구현 예시 (TypeScript)

```typescript
import { OpenAI } from 'openai';

interface NaiveRAGConfig {
  embeddingModel: string;   // 임베딩 모델
  llmModel: string;         // 생성 모델
  topK: number;             // 검색 문서 수
}

class NaiveRAG {
  private openai: OpenAI;
  private vectorStore: VectorStore;
  private config: NaiveRAGConfig;

  constructor(config: NaiveRAGConfig) {
    this.openai = new OpenAI();
    this.config = config;
  }

  async query(question: string): Promise<string> {
    // 1. 질문을 임베딩으로 변환
    const queryEmbedding = await this.openai.embeddings.create({
      model: this.config.embeddingModel,
      input: question,
    });

    // 2. 벡터 검색으로 관련 문서 조회
    const results = await this.vectorStore.search(
      queryEmbedding.data[0].embedding,
      this.config.topK,
    );

    // 3. 컨텍스트 조합 후 LLM으로 답변 생성
    const context = results.map(r => r.content).join('\n\n');
    const response = await this.openai.chat.completions.create({
      model: this.config.llmModel,
      messages: [
        { role: 'system', content: `다음 컨텍스트를 기반으로 질문에 답하세요.\n\n${context}` },
        { role: 'user', content: question },
      ],
    });

    return response.choices[0].message.content ?? '';
  }
}
```

### Naive RAG의 한계

| 문제 | 원인 | 영향 |
|------|------|------|
| 검색 품질 낮음 | 쿼리-문서 임베딩 불일치 | 관련 없는 문서 반환 |
| Lost in the middle | 긴 컨텍스트에서 중간 정보 무시 | 중요 정보 누락 |
| Hallucination | 컨텍스트와 무관한 생성 | 부정확한 답변 |
| 중복 검색 | 유사 청크 다수 반환 | 컨텍스트 낭비 |

## 3. Advanced RAG

Naive RAG의 한계를 검색 전/후 최적화로 해결한다.

```
[질문] → Query Transform → Embedding → Vector Search → Reranking → Context Compression → LLM → [답변]
```

### Pre-Retrieval 최적화

```typescript
class AdvancedRAG {
  // 쿼리 변환: 원본 질문을 검색에 최적화된 형태로 변환
  private async transformQuery(question: string): Promise<string[]> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: `사용자 질문을 검색에 최적화된 3개의 쿼리로 변환하세요.
각 쿼리는 다른 관점에서 접근해야 합니다.
JSON 배열로 반환하세요.`,
        },
        { role: 'user', content: question },
      ],
    });

    return JSON.parse(response.choices[0].message.content ?? '[]');
  }

  // Multi-Query 검색: 변환된 쿼리들로 각각 검색 후 결과 합산
  private async multiQueryRetrieve(queries: string[]): Promise<Document[]> {
    const allResults = await Promise.all(
      queries.map(q => this.retrieve(q)),
    );
    return this.deduplicateAndRank(allResults.flat()); // 중복 제거 후 점수 합산
  }
}
```

### Post-Retrieval 최적화

```typescript
class PostRetrievalOptimizer {
  // 리랭킹: 검색 결과를 질문과의 관련성으로 재정렬
  async rerank(question: string, documents: Document[]): Promise<Document[]> {
    const response = await fetch('https://api.cohere.ai/v1/rerank', {
      method: 'POST',
      headers: { Authorization: `Bearer ${process.env.COHERE_API_KEY}` },
      body: JSON.stringify({
        model: 'rerank-v3.5',
        query: question,
        documents: documents.map(d => d.content),
        top_n: 5,
      }),
    });

    const result = await response.json();
    return result.results.map((r: any) => ({
      ...documents[r.index],
      relevanceScore: r.relevance_score,
    }));
  }

  // 컨텍스트 압축: 관련 부분만 추출
  async compress(question: string, documents: Document[]): Promise<string> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `다음 문서들에서 질문과 직접 관련된 부분만 추출하세요.
불필요한 내용은 제거하세요.`,
        },
        {
          role: 'user',
          content: `질문: ${question}\n\n문서:\n${documents.map(d => d.content).join('\n---\n')}`,
        },
      ],
    });

    return response.choices[0].message.content ?? '';
  }
}
```

## 4. Modular RAG

각 단계를 독립 모듈로 분리하고, 파이프라인을 동적으로 구성한다.

### 모듈 구성

```
┌─────────────────────────────────────────────────┐
│                   Router Module                  │  ← 질문 유형에 따라 경로 분기
├──────────┬──────────┬──────────┬────────────────┤
│  Query   │ Retrieve │  Rerank  │   Generate     │
│ Transform│  Module  │  Module  │    Module      │
│  Module  │          │          │                │
├──────────┼──────────┼──────────┼────────────────┤
│ HyDE     │ Dense    │ Cross-   │ Cite-aware     │
│ Step-back│ Sparse   │ Encoder  │ Chain-of-Note  │
│ Decompose│ Hybrid   │ LLM-based│ Self-RAG       │
└──────────┴──────────┴──────────┴────────────────┘
```

### 라우터 구현

```typescript
interface RAGModule {
  name: string;
  execute(input: PipelineContext): Promise<PipelineContext>;
}

interface PipelineContext {
  originalQuery: string;
  transformedQueries?: string[];
  retrievedDocs?: Document[];
  rerankedDocs?: Document[];
  compressedContext?: string;
  answer?: string;
  metadata: Record<string, any>;
}

class RAGRouter {
  private pipelines: Map<string, RAGModule[]> = new Map();

  // 질문 유형별 파이프라인 등록
  registerPipeline(type: string, modules: RAGModule[]): void {
    this.pipelines.set(type, modules);
  }

  // 질문 유형 분류 후 해당 파이프라인 실행
  async route(query: string): Promise<PipelineContext> {
    const queryType = await this.classifyQuery(query); // simple | complex | multi-hop | conversational
    const pipeline = this.pipelines.get(queryType) ?? this.pipelines.get('default')!;

    let context: PipelineContext = { originalQuery: query, metadata: { queryType } };
    for (const module of pipeline) {
      context = await module.execute(context);
    }
    return context;
  }

  private async classifyQuery(query: string): Promise<string> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `질문 유형을 분류하세요: simple, complex, multi-hop, conversational 중 하나만 반환`,
        },
        { role: 'user', content: query },
      ],
    });
    return response.choices[0].message.content?.trim() ?? 'simple';
  }
}

// 파이프라인 구성 예시
const router = new RAGRouter();
router.registerPipeline('simple', [denseRetriever, generator]);                           // 단순 질문: 검색 → 생성
router.registerPipeline('complex', [queryDecomposer, denseRetriever, reranker, generator]); // 복잡 질문: 분해 → 검색 → 리랭킹 → 생성
router.registerPipeline('multi-hop', [stepBackPrompt, hybridRetriever, reranker, chainOfNote]); // 멀티홉: 추상화 → 하이브리드 검색 → 연쇄 추론
```

## 5. Self-RAG

검색 필요 여부를 모델이 스스로 판단하고, 생성 결과의 품질도 자체 검증한다.

```typescript
class SelfRAG {
  async query(question: string): Promise<string> {
    // 1단계: 검색이 필요한지 판단
    const needsRetrieval = await this.judgeRetrievalNeed(question);
    if (!needsRetrieval) {
      return this.generateWithoutContext(question); // 검색 없이 직접 생성
    }

    // 2단계: 검색 + 생성
    const docs = await this.retrieve(question);
    const answer = await this.generateWithContext(question, docs);

    // 3단계: 생성 결과 검증 (관련성, 지지도, 유용성)
    const evaluation = await this.evaluateResponse(question, docs, answer);
    if (evaluation.score < 0.7) {
      return this.regenerateWithFeedback(question, docs, answer, evaluation); // 재생성
    }

    return answer;
  }

  private async evaluateResponse(
    question: string,
    docs: Document[],
    answer: string,
  ): Promise<{ score: number; feedback: string }> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: `답변 품질을 평가하세요:
- relevance (0-1): 질문에 대한 답변 관련성
- groundedness (0-1): 제공된 문서에 기반한 정도
- usefulness (0-1): 실용적 유용성
JSON으로 반환: { score, feedback }`,
        },
        {
          role: 'user',
          content: `질문: ${question}\n문서: ${docs.map(d => d.content).join('\n')}\n답변: ${answer}`,
        },
      ],
    });

    return JSON.parse(response.choices[0].message.content ?? '{}');
  }
}
```

## 6. 아키텍처 선택 가이드

| 상황 | 권장 아키텍처 | 이유 |
|------|-------------|------|
| MVP / 프로토타입 | Naive RAG | 빠른 구축, 단순 |
| 프로덕션 Q&A | Advanced RAG | 검색 품질 + 비용 균형 |
| 복잡한 도메인 | Modular RAG | 유연한 파이프라인 구성 |
| 높은 정확도 필요 | Self-RAG | 자체 검증으로 품질 보장 |
| 다양한 질문 유형 | Router + Modular | 질문별 최적 경로 분기 |

## 7. 프로덕션 체크리스트

```
☐ 임베딩 모델과 벡터 DB 선정 완료
☐ 청킹 전략 결정 (문서 유형별)
☐ 검색 품질 평가 지표 설정 (Precision@K, MRR)
☐ 리랭킹 모델 적용 여부 결정
☐ 컨텍스트 윈도우 내 토큰 수 관리
☐ Hallucination 탐지/방지 로직
☐ 에러 처리 및 폴백 전략
☐ 비용 모니터링 (임베딩 + LLM 호출)
☐ 로깅 및 평가 파이프라인
☐ 증분 인덱싱 전략
```
