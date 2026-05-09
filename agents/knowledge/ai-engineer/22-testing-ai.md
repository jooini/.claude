# AI System Testing

> 참조 링크: https://docs.ragas.io/, https://docs.confident-ai.com/

---

## 1. AI 테스트 유형

| 유형 | 목적 | 빈도 |
|------|------|------|
| Golden Set Test | 기준 성능 확인 | 파이프라인 변경 시 |
| Regression Test | 성능 저하 감지 | 배포 전 |
| A/B Test | 두 버전 비교 | 실험 |
| Auto Evaluation | LLM으로 자동 평가 | 매 배포 |
| Manual Review | 사람이 직접 확인 | 주기적 |

## 2. Golden Set 테스트

정답이 있는 테스트 세트로 기준 성능을 측정한다.

```typescript
interface GoldenItem {
  id: string;
  question: string;
  expectedAnswer: string;
  relevantDocIds: string[];
  category: string;
  difficulty: 'easy' | 'medium' | 'hard';
}

// golden_set.json — 최소 100개 이상
const goldenSet: GoldenItem[] = [
  {
    id: 'gs-001',
    question: '환불 절차가 어떻게 되나요?',
    expectedAnswer: '구매일로부터 14일 이내에 마이페이지 > 주문내역에서 환불 신청이 가능합니다.',
    relevantDocIds: ['doc-refund-policy'],
    category: 'refund',
    difficulty: 'easy',
  },
  // ...
];

async function runGoldenSetTest(pipeline: RAGPipeline, goldenSet: GoldenItem[]) {
  const results = [];

  for (const item of goldenSet) {
    const { answer, sources } = await pipeline.query(item.question);

    results.push({
      id: item.id,
      passed: await evaluateAnswer(item.expectedAnswer, answer),
      retrievalHit: sources.some(s => item.relevantDocIds.includes(s.id)),
      generatedAnswer: answer,
    });
  }

  return {
    passRate: results.filter(r => r.passed).length / results.length,
    retrievalHitRate: results.filter(r => r.retrievalHit).length / results.length,
    failedItems: results.filter(r => !r.passed),
  };
}
```

## 3. Regression 테스트

파이프라인 변경 전후 성능을 비교한다.

```typescript
async function regressionTest(
  oldPipeline: RAGPipeline,
  newPipeline: RAGPipeline,
  testSet: GoldenItem[],
) {
  const oldResults = await runGoldenSetTest(oldPipeline, testSet);
  const newResults = await runGoldenSetTest(newPipeline, testSet);

  const comparison = {
    passRate: { old: oldResults.passRate, new: newResults.passRate },
    retrievalHitRate: { old: oldResults.retrievalHitRate, new: newResults.retrievalHitRate },
    regressions: findRegressions(oldResults, newResults), // 이전에 통과했는데 이제 실패
    improvements: findImprovements(oldResults, newResults),
  };

  // 회귀가 있으면 경고
  if (comparison.regressions.length > 0) {
    console.warn(`⚠️ ${comparison.regressions.length}개 항목 회귀 발생`);
  }

  return comparison;
}
```

## 4. LLM 자동 평가

```typescript
async function autoEvaluate(
  question: string,
  expectedAnswer: string,
  generatedAnswer: string,
): Promise<{ score: number; reasoning: string }> {
  const response = await client.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 512,
    messages: [{
      role: 'user',
      content: `다음 질문에 대한 생성된 답변을 평가하세요.

질문: ${question}
기대 답변: ${expectedAnswer}
생성 답변: ${generatedAnswer}

평가 기준:
1. 정확성: 기대 답변의 핵심 정보를 포함하는가?
2. 완전성: 누락된 중요 정보가 없는가?
3. 간결성: 불필요한 내용이 없는가?

JSON으로 응답:
{"score": 1-5, "reasoning": "이유"}`,
    }],
  });

  return JSON.parse(response.content[0].text);
}
```

## 5. A/B 테스트

```typescript
class ABTest {
  private variants: Map<string, RAGPipeline> = new Map();
  private results: Map<string, { positive: number; negative: number; total: number }> = new Map();

  addVariant(name: string, pipeline: RAGPipeline) {
    this.variants.set(name, pipeline);
    this.results.set(name, { positive: 0, negative: 0, total: 0 });
  }

  // 사용자를 랜덤 배정
  assignVariant(userId: string): string {
    const hash = createHash('md5').update(userId).digest('hex');
    const index = parseInt(hash.slice(0, 8), 16) % this.variants.size;
    return [...this.variants.keys()][index];
  }

  recordFeedback(variant: string, positive: boolean) {
    const r = this.results.get(variant)!;
    r.total++;
    if (positive) r.positive++;
    else r.negative++;
  }

  getResults() {
    const output: Record<string, any> = {};
    for (const [name, r] of this.results) {
      output[name] = {
        ...r,
        positiveRate: r.total > 0 ? r.positive / r.total : 0,
      };
    }
    return output;
  }
}
```

## 6. 검색 품질 테스트

```typescript
async function testRetrieval(vectorDB: VectorDB, testCases: { query: string; expectedDocIds: string[] }[]) {
  const metrics = { hitRate: 0, mrr: 0, precision5: 0 };

  for (const tc of testCases) {
    const results = await vectorDB.search(await embed(tc.query), { limit: 5 });
    const retrievedIds = results.map(r => r.id);

    // Hit Rate
    if (retrievedIds.some(id => tc.expectedDocIds.includes(id))) metrics.hitRate++;

    // MRR
    for (let i = 0; i < retrievedIds.length; i++) {
      if (tc.expectedDocIds.includes(retrievedIds[i])) {
        metrics.mrr += 1 / (i + 1);
        break;
      }
    }

    // Precision@5
    const relevant = retrievedIds.filter(id => tc.expectedDocIds.includes(id)).length;
    metrics.precision5 += relevant / 5;
  }

  const n = testCases.length;
  return {
    hitRate: metrics.hitRate / n,
    mrr: metrics.mrr / n,
    precision5: metrics.precision5 / n,
  };
}
```

## 7. CI 통합

```yaml
# GitHub Actions
- name: AI Pipeline Tests
  run: |
    npx tsx scripts/run-golden-set-test.ts
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}

- name: Check regression
  run: |
    npx tsx scripts/regression-check.ts --threshold=0.95
    # 성능이 95% 미만이면 실패
```

## 8. 테스트 데이터 관리

```
tests/
├── golden-sets/
│   ├── refund-questions.json     # 카테고리별 분리
│   ├── product-questions.json
│   └── general-questions.json
├── retrieval-tests/
│   └── expected-retrievals.json
└── evaluation/
    ├── run-tests.ts
    └── report.ts
```
