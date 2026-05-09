# Caching Optimization

> 참조 링크: https://platform.openai.com/docs/guides/prompt-caching, https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching

---

## 1. AI 시스템 캐싱 레이어

```
사용자 쿼리
  ↓
1. Exact Match Cache — 동일 쿼리 캐시
  ↓
2. Semantic Cache — 유사 쿼리 캐시
  ↓
3. Embedding Cache — 임베딩 결과 캐시
  ↓
4. LLM Prompt Cache — 프롬프트 prefix 캐시
  ↓
5. 실제 처리
```

## 2. Exact Match Cache

동일한 쿼리에 대해 이전 결과를 반환한다.

```typescript
import Redis from 'ioredis';

const redis = new Redis();

async function cachedQuery(query: string): Promise<string> {
  const cacheKey = `rag:${createHash('sha256').update(query).digest('hex')}`;
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached);

  const result = await ragPipeline(query);
  await redis.set(cacheKey, JSON.stringify(result), 'EX', 3600); // 1시간 TTL
  return result;
}
```

## 3. Semantic Cache

의미적으로 유사한 쿼리를 캐시 히트로 처리한다.

```typescript
async function semanticCachedQuery(query: string, threshold: number = 0.95): Promise<string | null> {
  const queryEmbedding = await embed(query);

  // 캐시에서 유사한 쿼리 검색
  const results = await vectorDB.search({
    collection: 'query_cache',
    vector: queryEmbedding,
    limit: 1,
  });

  if (results.length > 0 && results[0].score >= threshold) {
    return results[0].metadata.response; // 캐시 히트
  }

  // 캐시 미스 → 실제 처리
  const response = await ragPipeline(query);

  // 결과를 캐시에 저장
  await vectorDB.upsert('query_cache', {
    id: `cache_${Date.now()}`,
    vector: queryEmbedding,
    metadata: { query, response, createdAt: new Date().toISOString() },
  });

  return response;
}
```

### 주의사항

- threshold가 너무 낮으면 잘못된 캐시 히트 (다른 의미의 쿼리에 이전 답변 반환)
- 시간에 민감한 쿼리 ("오늘 날씨")는 캐시하면 안 됨
- 개인화된 쿼리는 사용자별 캐시 격리 필요

## 4. Embedding Cache

동일한 텍스트의 임베딩을 재계산하지 않는다.

```typescript
const embeddingCache = new Map<string, number[]>();

async function cachedEmbed(text: string): Promise<number[]> {
  const key = createHash('md5').update(text).digest('hex');

  if (embeddingCache.has(key)) return embeddingCache.get(key)!;

  const embedding = await embed(text);
  embeddingCache.set(key, embedding);
  return embedding;
}

// Redis 기반 (영속)
async function cachedEmbedRedis(text: string): Promise<number[]> {
  const key = `emb:${createHash('md5').update(text).digest('hex')}`;
  const cached = await redis.get(key);
  if (cached) return JSON.parse(cached);

  const embedding = await embed(text);
  await redis.set(key, JSON.stringify(embedding), 'EX', 86400 * 7); // 7일
  return embedding;
}
```

## 5. LLM Prompt Caching

### Anthropic Prompt Caching

```typescript
import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic();

const response = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  system: [
    {
      type: 'text',
      text: longSystemPrompt,   // 긴 시스템 프롬프트
      cache_control: { type: 'ephemeral' }, // 캐시 지시
    },
  ],
  messages: [{ role: 'user', content: userQuery }],
});

// 캐시 히트 시 비용 90% 절감, 지연시간 85% 감소
```

### OpenAI Automatic Caching

OpenAI는 동일한 prefix를 자동으로 캐시한다. 별도 설정 불필요.

```typescript
// 시스템 프롬프트 + 긴 컨텍스트가 동일하면 자동 캐시
// 1024 토큰 이상의 prefix가 동일해야 캐시 히트
const response = await openai.chat.completions.create({
  model: 'gpt-4o',
  messages: [
    { role: 'system', content: longSystemPrompt },    // 캐시됨
    { role: 'user', content: '이전 대화...' },          // 캐시됨 (이전과 동일 시)
    { role: 'user', content: newQuery },               // 새 부분
  ],
});
```

## 6. 캐시 무효화 전략

| 전략 | 적용 | 구현 |
|------|------|------|
| TTL (Time-To-Live) | 시간 기반 만료 | Redis `EX` 옵션 |
| 이벤트 기반 | 데이터 변경 시 무효화 | 문서 업데이트 → 관련 캐시 삭제 |
| 버전 기반 | 모델/파이프라인 변경 시 | 캐시 키에 버전 포함 |
| LRU | 메모리 제한 시 오래된 것부터 | Redis `maxmemory-policy allkeys-lru` |

```typescript
// 버전 기반 캐시 키
const CACHE_VERSION = 'v2'; // 모델 변경 시 증가
const cacheKey = `rag:${CACHE_VERSION}:${queryHash}`;

// 이벤트 기반 무효화
async function onDocumentUpdate(docId: string) {
  const pattern = `rag:*`; // 관련 캐시 패턴
  // 실제로는 문서-쿼리 매핑 테이블로 정밀하게 무효화
  await redis.del(pattern);
}
```

## 7. 캐시 모니터링

```typescript
interface CacheMetrics {
  hitRate: number;          // 캐시 히트율
  missRate: number;
  avgLatency: { hit: number; miss: number }; // ms
  memoryUsage: number;      // bytes
  evictions: number;        // 제거된 항목 수
  costSaved: number;        // 절약된 API 비용
}

// Redis INFO 기반 모니터링
async function getCacheStats(): Promise<CacheMetrics> {
  const info = await redis.info('stats');
  const hits = parseInt(info.match(/keyspace_hits:(\d+)/)?.[1] || '0');
  const misses = parseInt(info.match(/keyspace_misses:(\d+)/)?.[1] || '0');
  return {
    hitRate: hits / (hits + misses),
    missRate: misses / (hits + misses),
    // ...
  };
}
```
