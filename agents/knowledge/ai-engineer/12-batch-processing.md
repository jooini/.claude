# Batch Processing

> 참조 링크: https://platform.openai.com/docs/guides/batch, https://docs.pinecone.io/guides/data/upsert-data#upsert-records-in-batches

---

## 1. 배치 임베딩

### OpenAI 배치 API

```typescript
import OpenAI from 'openai';

const openai = new OpenAI();

async function embedBatch(texts: string[], batchSize: number = 100): Promise<number[][]> {
  const allEmbeddings: number[][] = [];

  for (let i = 0; i < texts.length; i += batchSize) {
    const batch = texts.slice(i, i + batchSize);
    const response = await openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: batch,
    });
    allEmbeddings.push(...response.data.map(d => d.embedding));

    // Rate limit 대응
    if (i + batchSize < texts.length) {
      await sleep(100); // 100ms 딜레이
    }
  }

  return allEmbeddings;
}
```

### 병렬 배치 처리

```typescript
async function embedParallel(
  texts: string[],
  batchSize: number = 100,
  concurrency: number = 5,
): Promise<number[][]> {
  const batches: string[][] = [];
  for (let i = 0; i < texts.length; i += batchSize) {
    batches.push(texts.slice(i, i + batchSize));
  }

  const results: number[][][] = [];
  for (let i = 0; i < batches.length; i += concurrency) {
    const concurrent = batches.slice(i, i + concurrency);
    const batchResults = await Promise.all(
      concurrent.map(batch =>
        openai.embeddings.create({ model: 'text-embedding-3-small', input: batch })
          .then(res => res.data.map(d => d.embedding))
      )
    );
    results.push(...batchResults);
  }

  return results.flat();
}
```

## 2. 벡터 DB Upsert 배치

### pgvector 배치 인서트

```typescript
async function batchUpsert(
  db: Pool,
  chunks: { content: string; embedding: number[]; metadata: any }[],
  batchSize: number = 500,
) {
  for (let i = 0; i < chunks.length; i += batchSize) {
    const batch = chunks.slice(i, i + batchSize);
    const values = batch.map((c, idx) =>
      `($${idx * 3 + 1}, $${idx * 3 + 2}::vector, $${idx * 3 + 3}::jsonb)`
    ).join(', ');

    const params = batch.flatMap(c => [
      c.content,
      `[${c.embedding.join(',')}]`,
      JSON.stringify(c.metadata),
    ]);

    await db.query(`
      INSERT INTO documents (content, embedding, metadata)
      VALUES ${values}
      ON CONFLICT (id) DO UPDATE SET
        content = EXCLUDED.content,
        embedding = EXCLUDED.embedding,
        metadata = EXCLUDED.metadata
    `, params);
  }
}
```

### Pinecone 배치 Upsert

```typescript
async function batchUpsertPinecone(
  index: any,
  vectors: { id: string; values: number[]; metadata: any }[],
  batchSize: number = 100,
) {
  for (let i = 0; i < vectors.length; i += batchSize) {
    const batch = vectors.slice(i, i + batchSize);
    await index.upsert(batch);
  }
}
```

## 3. 증분 업데이트

변경된 문서만 재임베딩하는 전략.

```typescript
interface DocumentState {
  id: string;
  contentHash: string;   // 내용의 해시
  embeddedAt: string;    // 마지막 임베딩 시점
}

async function incrementalUpdate(documents: Document[], stateStore: Map<string, DocumentState>) {
  const toEmbed: Document[] = [];
  const toDelete: string[] = [];

  for (const doc of documents) {
    const hash = createHash('sha256').update(doc.content).digest('hex');
    const existing = stateStore.get(doc.id);

    if (!existing || existing.contentHash !== hash) {
      toEmbed.push(doc); // 새 문서 또는 변경된 문서
    }
  }

  // 삭제된 문서 감지
  for (const [id] of stateStore) {
    if (!documents.find(d => d.id === id)) {
      toDelete.push(id);
    }
  }

  // 처리
  if (toEmbed.length > 0) await processAndEmbed(toEmbed);
  if (toDelete.length > 0) await deleteFromVectorDB(toDelete);

  // 상태 업데이트
  for (const doc of toEmbed) {
    stateStore.set(doc.id, {
      id: doc.id,
      contentHash: createHash('sha256').update(doc.content).digest('hex'),
      embeddedAt: new Date().toISOString(),
    });
  }
}
```

## 4. 재인덱싱 전략

### 전체 재인덱싱

임베딩 모델 변경, 청킹 전략 변경 시 필수.

```typescript
async function fullReindex(documents: Document[]) {
  // 1. 새 컬렉션/인덱스 생성 (blue-green)
  const newCollection = `documents_${Date.now()}`;
  await createCollection(newCollection);

  // 2. 전체 임베딩 + 저장
  const chunks = documents.flatMap(doc => chunkDocument(doc));
  const embeddings = await embedBatch(chunks.map(c => c.content));

  for (let i = 0; i < chunks.length; i++) {
    chunks[i].embedding = embeddings[i];
  }

  await batchUpsert(newCollection, chunks);

  // 3. 별칭 전환 (다운타임 없음)
  await switchAlias('documents', newCollection);

  // 4. 이전 컬렉션 삭제
  await deleteCollection(oldCollection);
}
```

## 5. 진행 상황 추적

```typescript
class BatchProgress {
  private total: number;
  private processed: number = 0;
  private failed: number = 0;
  private startTime: number;

  constructor(total: number) {
    this.total = total;
    this.startTime = Date.now();
  }

  update(success: number, fail: number = 0) {
    this.processed += success;
    this.failed += fail;
  }

  getStatus() {
    const elapsed = (Date.now() - this.startTime) / 1000;
    const rate = this.processed / elapsed;
    const remaining = (this.total - this.processed) / rate;

    return {
      total: this.total,
      processed: this.processed,
      failed: this.failed,
      percentage: ((this.processed / this.total) * 100).toFixed(1),
      rate: rate.toFixed(1) + '/s',
      eta: formatSeconds(remaining),
    };
  }
}
```

## 6. 에러 처리 / 재시도

```typescript
async function withRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  baseDelay: number = 1000,
): Promise<T> {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error: any) {
      if (attempt === maxRetries) throw error;

      // Rate limit → exponential backoff
      if (error.status === 429) {
        const delay = baseDelay * Math.pow(2, attempt);
        await sleep(delay);
        continue;
      }

      // 일시적 에러 → 재시도
      if (error.status >= 500) {
        await sleep(baseDelay);
        continue;
      }

      throw error; // 영구 에러는 즉시 throw
    }
  }
  throw new Error('Unreachable');
}
```

## 7. 배치 스케줄링

```typescript
// cron 기반 증분 업데이트
// 매시간: 변경된 문서만 재임베딩
// 매일 새벽: 전체 정합성 검증
// 모델 변경 시: 전체 재인덱싱

interface BatchConfig {
  schedule: string;       // cron expression
  type: 'incremental' | 'full';
  batchSize: number;
  concurrency: number;
  retryPolicy: { maxRetries: number; backoffMs: number };
}
```
