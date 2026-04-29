# AI System Debugging

---

## 1. 디버깅 프레임워크

AI 시스템 문제는 **검색**, **생성**, **인프라** 3가지로 나뉜다.

```
문제 발생
  ├── 검색 문제: 관련 문서를 못 찾음
  │   ├── 임베딩 품질
  │   ├── 청킹 전략
  │   ├── 인덱스 설정
  │   └── 쿼리 변환
  ├── 생성 문제: 찾았지만 답이 이상함
  │   ├── Hallucination
  │   ├── 프롬프트 설계
  │   ├── 컨텍스트 윈도우
  │   └── 모델 한계
  └── 인프라 문제: 느리거나 에러
      ├── 지연시간
      ├── Rate Limit
      ├── 메모리
      └── 네트워크
```

## 2. 검색 품질 디버깅

### 증상: 관련 문서가 검색되지 않음

```typescript
// 1. 쿼리 임베딩과 문서 임베딩의 유사도 직접 확인
async function debugRetrieval(query: string, expectedDocId: string) {
  const queryVector = await embed(query);
  const docVector = await getStoredVector(expectedDocId);

  const similarity = cosineSimilarity(queryVector, docVector);
  console.log(`유사도: ${similarity.toFixed(4)}`);

  // 0.3 미만이면 임베딩 모델 또는 청킹 문제
  // 0.3-0.7이면 쿼리 변환 또는 top-k 조정 필요
  // 0.7 이상인데 검색 안 되면 인덱스/필터 문제
}
```

### 원인별 해결

| 원인 | 진단 | 해결 |
|------|------|------|
| 청크가 너무 큼 | 청크 내용 확인 → 여러 주제 혼재 | 청크 크기 줄이기 |
| 청크가 너무 작음 | 청크 내용 확인 → 문맥 부족 | 청크 크기 늘리기 + 오버랩 |
| 쿼리와 문서의 어휘 불일치 | 유사도 낮음 | 하이브리드 검색 (BM25 + 벡터) |
| 인덱스 미구축 | 검색 속도 느림 | HNSW 인덱스 생성 |
| 필터 과도 | 결과 0건 | 필터 조건 완화 |

### 검색 결과 분석

```typescript
async function analyzeRetrieval(query: string, limit: number = 10) {
  const results = await vectorDB.search(await embed(query), { limit });

  console.log(`Query: ${query}`);
  console.log(`Results: ${results.length}`);
  console.log('---');

  for (const r of results) {
    console.log(`Score: ${r.score.toFixed(4)}`);
    console.log(`Content: ${r.content.slice(0, 200)}...`);
    console.log(`Metadata: ${JSON.stringify(r.metadata)}`);
    console.log('---');
  }

  // 점수 분포 분석
  const scores = results.map(r => r.score);
  console.log(`Score range: ${Math.min(...scores).toFixed(4)} ~ ${Math.max(...scores).toFixed(4)}`);
  console.log(`Score gap (1st-2nd): ${(scores[0] - scores[1]).toFixed(4)}`);
}
```

## 3. Hallucination 디버깅

### 증상: 컨텍스트에 없는 내용을 생성

```typescript
async function detectHallucination(context: string, answer: string): Promise<{
  statements: { text: string; supported: boolean }[];
  faithfulnessScore: number;
}> {
  const response = await client.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 2048,
    messages: [{
      role: 'user',
      content: `답변의 각 문장이 컨텍스트에서 뒷받침되는지 판단하세요.

컨텍스트:
${context}

답변:
${answer}

JSON 배열로 응답:
[{"statement": "문장", "supported": true/false, "evidence": "근거 또는 null"}]`,
    }],
  });

  const statements = JSON.parse(response.content[0].text);
  const supported = statements.filter((s: any) => s.supported).length;

  return {
    statements,
    faithfulnessScore: supported / statements.length,
  };
}
```

### Hallucination 원인과 대응

| 원인 | 대응 |
|------|------|
| 컨텍스트 부족 | 검색 결과 수 증가, 하이브리드 검색 |
| 컨텍스트가 길어서 무시됨 | 중요 부분 앞에 배치, reranking |
| 프롬프트가 답변을 강제 | "모르면 모른다고 말해" 지시 추가 |
| 모델의 사전 지식과 충돌 | "오직 제공된 컨텍스트만 사용" 강조 |

## 4. 지연시간 디버깅

```typescript
async function profileRAG(query: string) {
  const timings: Record<string, number> = {};

  let start = Date.now();
  const queryVector = await embed(query);
  timings.embedding = Date.now() - start;

  start = Date.now();
  const results = await vectorDB.search(queryVector, { limit: 5 });
  timings.retrieval = Date.now() - start;

  start = Date.now();
  const reranked = await rerank(query, results);
  timings.reranking = Date.now() - start;

  start = Date.now();
  const answer = await llm.complete(query, reranked);
  timings.generation = Date.now() - start;

  timings.total = Object.values(timings).reduce((a, b) => a + b, 0) - timings.total;

  console.table(timings);
  // ┌────────────┬──────────┐
  // │ embedding  │    50ms  │
  // │ retrieval  │   120ms  │
  // │ reranking  │   200ms  │
  // │ generation │  2500ms  │  ← 병목
  // │ total      │  2870ms  │
  // └────────────┴──────────┘
}
```

## 5. 프롬프트 디버깅

```typescript
// 실제 LLM에 전송되는 프롬프트 전체를 로깅
async function debugPrompt(query: string, contexts: string[]) {
  const systemPrompt = buildSystemPrompt(contexts);
  const userPrompt = buildUserPrompt(query);

  console.log('=== SYSTEM PROMPT ===');
  console.log(systemPrompt);
  console.log(`(${countTokens(systemPrompt)} tokens)`);
  console.log('=== USER PROMPT ===');
  console.log(userPrompt);
  console.log(`(${countTokens(userPrompt)} tokens)`);
  console.log(`=== TOTAL: ${countTokens(systemPrompt + userPrompt)} tokens ===`);

  // 컨텍스트 윈도우 초과 확인
  const maxTokens = 200000; // Claude
  const totalTokens = countTokens(systemPrompt + userPrompt);
  if (totalTokens > maxTokens * 0.8) {
    console.warn(`⚠️ 컨텍스트의 ${((totalTokens / maxTokens) * 100).toFixed(0)}% 사용 중`);
  }
}
```

## 6. 체계적 디버깅 절차

```
1. 문제 재현
   - 정확한 쿼리와 기대 결과 기록
   - 동일 입력으로 일관되게 재현되는지 확인

2. 단계별 격리
   - 검색만 실행 → 결과 확인
   - 검색 결과 + 프롬프트 확인
   - LLM 응답 확인

3. 비교 분석
   - 잘 동작하는 유사 쿼리와 비교
   - 검색 점수, 프롬프트 차이 분석

4. 가설 검증
   - 한 번에 하나씩 변경
   - A/B 비교로 효과 측정

5. 수정 후 회귀 테스트
   - Golden Set으로 전체 성능 확인
   - 수정이 다른 케이스를 망가뜨리지 않는지 확인
```

## 7. 디버깅 도구

```typescript
// RAG 디버그 모드
class RAGDebugger {
  async debug(query: string) {
    return {
      query,
      embedding: await this.debugEmbedding(query),
      retrieval: await this.debugRetrieval(query),
      prompt: await this.debugPrompt(query),
      generation: await this.debugGeneration(query),
      timing: await this.profileRAG(query),
    };
  }
}

// 사용
const debugger = new RAGDebugger(pipeline);
const report = await debugger.debug('환불 절차가 어떻게 되나요?');
console.log(JSON.stringify(report, null, 2));
```
