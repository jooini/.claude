# Vector Databases

> 참조 링크: https://www.pinecone.io/docs/, https://qdrant.tech/documentation/, https://github.com/pgvector/pgvector

---

## 1. 벡터 DB 선택 기준

| 기준 | 설명 |
|------|------|
| 호스팅 | 관리형 vs 셀프호스팅 |
| 규모 | 벡터 수 (1K ~ 수십억) |
| 지연시간 | 검색 응답 시간 |
| 필터링 | 메타데이터 기반 필터 |
| 비용 | 저장/검색 비용 |
| 기존 인프라 | PostgreSQL 이미 사용 중이면 pgvector |

## 2. 주요 벡터 DB 비교

| | Pinecone | Qdrant | pgvector | Weaviate | ChromaDB |
|---|----------|--------|----------|----------|----------|
| 유형 | 관리형 SaaS | 셀프/클라우드 | PostgreSQL 확장 | 셀프/클라우드 | 임베디드 |
| 규모 | 수십억 | 수십억 | 수백만 | 수십억 | 수십만 |
| 필터링 | ✅ 강력 | ✅ 강력 | ✅ SQL | ✅ GraphQL | ✅ 기본 |
| 하이브리드 검색 | ✅ | ✅ | ✅ (별도 설정) | ✅ | ❌ |
| 적합한 경우 | 프로덕션 SaaS | 유연한 셀프호스팅 | PostgreSQL 이미 사용 | 멀티모달 | 프로토타입/로컬 |

## 3. pgvector (PostgreSQL)

기존 PostgreSQL에 벡터 검색 기능을 추가한다. 별도 인프라 없이 사용 가능.

### 설정

```sql
-- 확장 설치
CREATE EXTENSION vector;

-- 테이블 생성
CREATE TABLE documents (
  id SERIAL PRIMARY KEY,
  content TEXT NOT NULL,
  embedding vector(1536),  -- 차원 수 지정
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스 (HNSW — 권장)
CREATE INDEX ON documents
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- 또는 IVFFlat (대규모 데이터)
CREATE INDEX ON documents
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
```

### 검색

```sql
-- 코사인 유사도 검색 (가장 유사한 5개)
SELECT id, content, metadata,
       1 - (embedding <=> $1::vector) AS similarity
FROM documents
WHERE metadata->>'category' = 'tech'  -- 메타데이터 필터
ORDER BY embedding <=> $1::vector
LIMIT 5;

-- L2 거리 기반
SELECT * FROM documents
ORDER BY embedding <-> $1::vector
LIMIT 5;

-- 내적 기반
SELECT * FROM documents
ORDER BY embedding <#> $1::vector
LIMIT 5;
```

### TypeScript (Drizzle ORM)

```typescript
import { pgTable, serial, text, vector, jsonb, timestamp } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

export const documents = pgTable('documents', {
  id: serial('id').primaryKey(),
  content: text('content').notNull(),
  embedding: vector('embedding', { dimensions: 1536 }),
  metadata: jsonb('metadata'),
  createdAt: timestamp('created_at').defaultNow(),
});

// 검색
const results = await db.execute(sql`
  SELECT id, content, metadata,
         1 - (embedding <=> ${sql.raw(`'[${queryVector.join(',')}]'`)}::vector) as similarity
  FROM documents
  ORDER BY embedding <=> ${sql.raw(`'[${queryVector.join(',')}]'`)}::vector
  LIMIT 5
`);
```

## 4. Pinecone

```typescript
import { Pinecone } from '@pinecone-database/pinecone';

const pc = new Pinecone({ apiKey: process.env.PINECONE_API_KEY! });
const index = pc.index('my-index');

// Upsert
await index.upsert([
  {
    id: 'doc-1',
    values: embedding,
    metadata: { source: 'manual', category: 'tech' },
  },
]);

// 검색
const results = await index.query({
  vector: queryEmbedding,
  topK: 5,
  filter: { category: { $eq: 'tech' } },
  includeMetadata: true,
});

// 결과
results.matches.forEach(match => {
  console.log(match.id, match.score, match.metadata);
});
```

## 5. Qdrant

```typescript
import { QdrantClient } from '@qdrant/js-client-rest';

const client = new QdrantClient({ url: 'http://localhost:6333' });

// 컬렉션 생성
await client.createCollection('documents', {
  vectors: { size: 1536, distance: 'Cosine' },
});

// Upsert
await client.upsert('documents', {
  wait: true,
  points: [
    {
      id: 1,
      vector: embedding,
      payload: { content: '문서 내용', category: 'tech' },
    },
  ],
});

// 검색
const results = await client.search('documents', {
  vector: queryEmbedding,
  limit: 5,
  filter: {
    must: [{ key: 'category', match: { value: 'tech' } }],
  },
  with_payload: true,
});
```

## 6. ChromaDB (프로토타입/로컬)

```typescript
import { ChromaClient } from 'chromadb';

const client = new ChromaClient();

const collection = await client.getOrCreateCollection({
  name: 'documents',
  metadata: { 'hnsw:space': 'cosine' },
});

// 추가
await collection.add({
  ids: ['doc-1', 'doc-2'],
  embeddings: [embedding1, embedding2],
  documents: ['문서 1', '문서 2'],
  metadatas: [{ category: 'tech' }, { category: 'science' }],
});

// 검색
const results = await collection.query({
  queryEmbeddings: [queryEmbedding],
  nResults: 5,
  where: { category: 'tech' },
});
```

## 7. 인덱스 최적화

### HNSW 파라미터

| 파라미터 | 설명 | 기본값 | 트레이드오프 |
|---------|------|--------|-----------|
| `m` | 노드당 연결 수 | 16 | 높을수록 정확↑ 메모리↑ |
| `ef_construction` | 인덱스 빌드 시 탐색 범위 | 64 | 높을수록 빌드 느림, 정확↑ |
| `ef_search` | 검색 시 탐색 범위 | 40 | 높을수록 검색 느림, 정확↑ |

### 규모별 권장

| 벡터 수 | 권장 DB | 인덱스 |
|---------|--------|--------|
| < 10K | pgvector 또는 ChromaDB | 인덱스 없이도 충분 |
| 10K - 1M | pgvector (HNSW) | HNSW (m=16, ef=64) |
| 1M - 100M | Qdrant 또는 Pinecone | HNSW 튜닝 |
| > 100M | Pinecone 또는 Qdrant 클러스터 | 샤딩 + HNSW |

## 8. 하이브리드 검색

벡터 검색 + 키워드 검색(BM25)을 결합한다.

```sql
-- pgvector + pg_trgm (PostgreSQL)
SELECT id, content,
       (0.7 * (1 - (embedding <=> $1::vector))) +
       (0.3 * ts_rank(to_tsvector('korean', content), plainto_tsquery('korean', $2))) AS score
FROM documents
WHERE to_tsvector('korean', content) @@ plainto_tsquery('korean', $2)
ORDER BY score DESC
LIMIT 5;
```
