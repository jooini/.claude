# Embedding Models

> 참조 링크: https://platform.openai.com/docs/guides/embeddings, https://docs.voyageai.com/docs/embeddings, https://huggingface.co/MTEB

---

## 1. 임베딩 모델 선택 기준

| 기준 | 설명 |
|------|------|
| **차원(Dimensions)** | 벡터 크기. 높을수록 정보 보존↑, 저장/검색 비용↑ |
| **성능(MTEB 스코어)** | Massive Text Embedding Benchmark 기준 검색/분류 성능 |
| **다국어 지원** | 한국어 포함 여부, 다국어 성능 |
| **비용** | API 호출 비용 (토큰당 또는 요청당) |
| **속도** | 지연 시간, 처리량 |
| **최대 토큰** | 입력 텍스트 최대 길이 |

## 2. 주요 모델 비교

### 클라우드 API 모델

| 모델 | 차원 | 최대 토큰 | 다국어 | 비용 (1M 토큰) | 특징 |
|------|------|----------|--------|--------------|------|
| `text-embedding-3-large` (OpenAI) | 3072 (조절 가능) | 8191 | ✅ | $0.13 | 차원 축소 가능 |
| `text-embedding-3-small` (OpenAI) | 1536 (조절 가능) | 8191 | ✅ | $0.02 | 비용 효율 |
| `voyage-3` (Voyage AI) | 1024 | 32000 | ✅ | $0.06 | 긴 컨텍스트 |
| `voyage-3-lite` (Voyage AI) | 512 | 32000 | ✅ | $0.02 | 경량 |
| `embed-multilingual-v3.0` (Cohere) | 1024 | 512 | ✅ (100+ 언어) | $0.10 | 다국어 특화 |

### 오픈소스 / 로컬 모델

| 모델 | 차원 | 최대 토큰 | 다국어 | 크기 | 특징 |
|------|------|----------|--------|------|------|
| `BAAI/bge-m3` | 1024 | 8192 | ✅ | 2.2GB | 다국어 최고 성능 |
| `intfloat/multilingual-e5-large` | 1024 | 512 | ✅ | 2.2GB | 다국어 안정적 |
| `Xenova/multilingual-e5-small` | 384 | 512 | ✅ | 470MB | 경량 다국어 |
| `nomic-ai/nomic-embed-text-v1.5` | 768 | 8192 | ⚠️ (영어 중심) | 550MB | 긴 컨텍스트 |
| `sentence-transformers/all-MiniLM-L6-v2` | 384 | 256 | ❌ (영어) | 80MB | 초경량 |

## 3. 차원 축소

OpenAI `text-embedding-3` 시리즈는 `dimensions` 파라미터로 차원을 줄일 수 있다.

```typescript
import OpenAI from 'openai';

const openai = new OpenAI();

const response = await openai.embeddings.create({
  model: 'text-embedding-3-large',
  input: '검색할 텍스트',
  dimensions: 256, // 3072 → 256으로 축소 (저장 공간 12x 절약)
});

const embedding = response.data[0].embedding; // length: 256
```

### 차원별 성능 트레이드오프

| 차원 | 상대 성능 | 저장 공간 | 검색 속도 |
|------|----------|---------|----------|
| 3072 (원본) | 100% | 12KB/벡터 | 기준 |
| 1536 | ~98% | 6KB | ~2x |
| 768 | ~95% | 3KB | ~4x |
| 256 | ~90% | 1KB | ~12x |

## 4. 사용 패턴

### OpenAI 임베딩

```typescript
import OpenAI from 'openai';

const openai = new OpenAI();

// 단일 텍스트
async function embed(text: string): Promise<number[]> {
  const res = await openai.embeddings.create({
    model: 'text-embedding-3-small',
    input: text,
  });
  return res.data[0].embedding;
}

// 배치 처리
async function embedBatch(texts: string[]): Promise<number[][]> {
  const res = await openai.embeddings.create({
    model: 'text-embedding-3-small',
    input: texts, // 최대 2048개
  });
  return res.data.map(d => d.embedding);
}
```

### Voyage AI 임베딩

```typescript
import Anthropic from '@anthropic-ai/sdk'; // Voyage는 Anthropic 파트너

// 또는 직접 HTTP 호출
async function embedVoyage(texts: string[]): Promise<number[][]> {
  const response = await fetch('https://api.voyageai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${process.env.VOYAGE_API_KEY}`,
    },
    body: JSON.stringify({
      model: 'voyage-3',
      input: texts,
      input_type: 'document', // 'query' for search queries
    }),
  });
  const data = await response.json();
  return data.data.map((d: any) => d.embedding);
}
```

### 로컬 모델 (Transformers.js)

```typescript
import { pipeline } from '@xenova/transformers';

const extractor = await pipeline('feature-extraction', 'Xenova/multilingual-e5-small');

async function embed(text: string): Promise<number[]> {
  const output = await extractor(`query: ${text}`, {
    pooling: 'mean',
    normalize: true,
  });
  return Array.from(output.data);
}
```

## 5. 선택 가이드

### 프로덕션 (정확도 우선)

- `text-embedding-3-large` (dims=1536) — 범용, 안정적
- `voyage-3` — 긴 문서, RAG 특화
- `bge-m3` — 비용 제로 (셀프 호스팅)

### 프로토타입 / 비용 절약

- `text-embedding-3-small` (dims=512) — 저비용, 충분한 성능
- `Xenova/multilingual-e5-small` — 로컬, 무료, 한국어 지원

### 한국어 특화

- `bge-m3` — 다국어 MTEB 최상위
- `intfloat/multilingual-e5-large` — 안정적 다국어
- `embed-multilingual-v3.0` (Cohere) — API 기반 다국어

## 6. 주의사항

- **query vs document prefix**: 일부 모델(E5, BGE)은 검색 쿼리와 문서에 다른 prefix를 사용해야 한다
  - E5: `query: {질문}`, `passage: {문서}`
  - BGE: `Represent this sentence: {텍스트}`
- **정규화**: 코사인 유사도 사용 시 벡터를 L2 정규화해야 한다
- **토큰 제한 초과**: 최대 토큰을 넘는 텍스트는 잘린다. 사전 청킹 필수
- **모델 변경 시 재인덱싱**: 임베딩 모델을 바꾸면 기존 벡터와 호환되지 않는다
