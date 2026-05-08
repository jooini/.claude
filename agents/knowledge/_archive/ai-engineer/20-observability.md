# AI System Observability

> 참조 링크: https://langfuse.com/docs, https://docs.smith.langchain.com/

---

## 1. AI 시스템 관측 포인트

```
사용자 쿼리 → 전처리 → 임베딩 → 검색 → 리랭킹 → LLM 생성 → 후처리 → 응답
     ↓          ↓        ↓       ↓        ↓         ↓          ↓        ↓
   [로그]     [지연]   [비용]  [결과수]  [점수]    [토큰]     [필터]   [피드백]
```

### 수집해야 할 메트릭

| 단계 | 메트릭 | 목적 |
|------|--------|------|
| 쿼리 | 쿼리 텍스트, 사용자 ID | 패턴 분석 |
| 임베딩 | 지연시간, 차원 | 성능 |
| 검색 | 결과 수, 점수 분포, 지연시간 | 검색 품질 |
| LLM | 모델, 토큰 수, 지연시간, 비용 | 비용/성능 |
| 응답 | 응답 길이, 사용자 피드백 | 품질 |

## 2. Langfuse

오픈소스 LLM 관측 플랫폼. 셀프호스팅 가능.

### 설정

```typescript
import { Langfuse } from 'langfuse';

const langfuse = new Langfuse({
  publicKey: process.env.LANGFUSE_PUBLIC_KEY!,
  secretKey: process.env.LANGFUSE_SECRET_KEY!,
  baseUrl: process.env.LANGFUSE_HOST,
});
```

### Trace 기록

```typescript
async function ragQuery(question: string) {
  const trace = langfuse.trace({
    name: 'rag-query',
    input: question,
    metadata: { userId: 'user-123' },
  });

  // 검색 단계
  const retrievalSpan = trace.span({
    name: 'retrieval',
    input: question,
  });

  const queryVector = await embed(question);
  const results = await vectorDB.search(queryVector, { limit: 5 });

  retrievalSpan.end({
    output: results.map(r => ({ id: r.id, score: r.score })),
    metadata: { resultCount: results.length, topScore: results[0]?.score },
  });

  // LLM 생성 단계
  const generation = trace.generation({
    name: 'llm-generation',
    model: 'claude-sonnet-4-20250514',
    input: [
      { role: 'system', content: `Context: ${results.map(r => r.content).join('\n')}` },
      { role: 'user', content: question },
    ],
  });

  const response = await llm.complete(question, results);

  generation.end({
    output: response.text,
    usage: {
      input: response.usage.inputTokens,
      output: response.usage.outputTokens,
    },
  });

  trace.update({ output: response.text });
  await langfuse.flushAsync();

  return response.text;
}
```

### 사용자 피드백

```typescript
// 사용자가 좋아요/싫어요 클릭 시
langfuse.score({
  traceId: traceId,
  name: 'user-feedback',
  value: 1, // 1 = positive, 0 = negative
  comment: 'Helpful answer',
});
```

## 3. 커스텀 로깅

프레임워크 없이 직접 구현하는 경우.

```typescript
interface AILog {
  id: string;
  timestamp: string;
  type: 'query' | 'retrieval' | 'generation' | 'error';
  // 쿼리
  query?: string;
  userId?: string;
  // 검색
  retrievalResults?: { docId: string; score: number }[];
  retrievalLatencyMs?: number;
  // 생성
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
  generationLatencyMs?: number;
  cost?: number;
  // 응답
  response?: string;
  feedback?: 'positive' | 'negative';
  // 에러
  error?: string;
}

class AILogger {
  async log(entry: AILog) {
    // DB 저장 (분석용)
    await db.insert(aiLogs).values(entry);

    // 구조화 로깅 (운영용)
    console.log(JSON.stringify({
      level: entry.error ? 'error' : 'info',
      ...entry,
    }));
  }
}
```

## 4. 대시보드 메트릭

### 운영 메트릭

```typescript
interface OperationalMetrics {
  // 트래픽
  queriesPerMinute: number;
  uniqueUsers: number;

  // 지연시간
  p50LatencyMs: number;
  p95LatencyMs: number;
  p99LatencyMs: number;

  // 비용
  dailyCost: number;
  costPerQuery: number;
  tokenUsage: { input: number; output: number };

  // 에러
  errorRate: number;
  rateLimitHits: number;
}
```

### 품질 메트릭

```typescript
interface QualityMetrics {
  // 사용자 피드백
  positiveRate: number;     // 좋아요 비율
  negativeRate: number;

  // 검색 품질
  avgRetrievalScore: number;
  emptyResultRate: number;  // 검색 결과 0건 비율

  // 생성 품질
  avgResponseLength: number;
  halluccinationRate: number; // 자동 평가 기반
}
```

## 5. 알림 설정

```typescript
const alerts = [
  { metric: 'errorRate', threshold: 0.05, message: '에러율 5% 초과' },
  { metric: 'p95LatencyMs', threshold: 10000, message: 'P95 지연 10초 초과' },
  { metric: 'dailyCost', threshold: 100, message: '일일 비용 $100 초과' },
  { metric: 'emptyResultRate', threshold: 0.2, message: '빈 검색 결과 20% 초과' },
  { metric: 'negativeRate', threshold: 0.3, message: '부정 피드백 30% 초과' },
];
```

## 6. 디버깅용 로그

```typescript
// 개발/스테이징 환경에서 상세 로그
if (process.env.NODE_ENV !== 'production') {
  console.log('=== RAG Debug ===');
  console.log('Query:', question);
  console.log('Retrieved:', results.map(r => ({
    id: r.id,
    score: r.score.toFixed(3),
    preview: r.content.slice(0, 100),
  })));
  console.log('Prompt tokens:', response.usage.inputTokens);
  console.log('Completion tokens:', response.usage.outputTokens);
  console.log('Latency:', `${latency}ms`);
}
```
