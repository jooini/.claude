# Cost Management

> 참조 링크: https://openai.com/pricing, https://www.anthropic.com/pricing, https://docs.voyageai.com/docs/pricing

---

## 1. LLM API 비용 구조

### 주요 모델 비용 (2025 기준)

| 모델 | Input (1M 토큰) | Output (1M 토큰) | 컨텍스트 |
|------|----------------|-----------------|---------|
| GPT-4o | $2.50 | $10.00 | 128K |
| GPT-4o-mini | $0.15 | $0.60 | 128K |
| Claude Sonnet 4 | $3.00 | $15.00 | 200K |
| Claude Haiku 3.5 | $0.80 | $4.00 | 200K |
| Claude Opus 4 | $15.00 | $75.00 | 200K |

### 임베딩 비용

| 모델 | 비용 (1M 토큰) | 차원 |
|------|--------------|------|
| text-embedding-3-small | $0.02 | 1536 |
| text-embedding-3-large | $0.13 | 3072 |
| voyage-3 | $0.06 | 1024 |
| 로컬 (bge-m3) | $0 (GPU 비용만) | 1024 |

## 2. 토큰 사용량 추적

```typescript
interface TokenUsage {
  model: string;
  inputTokens: number;
  outputTokens: number;
  cachedTokens?: number;
  cost: number;
  timestamp: string;
  endpoint: string;      // 어떤 기능에서 사용했는지
  userId?: string;
}

class CostTracker {
  private usages: TokenUsage[] = [];

  record(usage: TokenUsage) {
    this.usages.push(usage);
  }

  getDailyCost(date: string): number {
    return this.usages
      .filter(u => u.timestamp.startsWith(date))
      .reduce((sum, u) => sum + u.cost, 0);
  }

  getByEndpoint(): Record<string, number> {
    const result: Record<string, number> = {};
    for (const u of this.usages) {
      result[u.endpoint] = (result[u.endpoint] || 0) + u.cost;
    }
    return result;
  }
}
```

### OpenAI 응답에서 비용 계산

```typescript
function calculateCost(response: any, model: string): number {
  const pricing: Record<string, { input: number; output: number }> = {
    'gpt-4o': { input: 2.5 / 1_000_000, output: 10 / 1_000_000 },
    'gpt-4o-mini': { input: 0.15 / 1_000_000, output: 0.6 / 1_000_000 },
  };

  const price = pricing[model];
  if (!price) return 0;

  const inputCost = response.usage.prompt_tokens * price.input;
  const outputCost = response.usage.completion_tokens * price.output;
  return inputCost + outputCost;
}
```

## 3. 비용 최적화 전략

### 모델 라우팅

쿼리 복잡도에 따라 다른 모델로 라우팅한다.

```typescript
async function routeToModel(query: string): Promise<string> {
  // 간단한 분류기로 복잡도 판단
  const complexity = await classifyComplexity(query); // 'simple' | 'moderate' | 'complex'

  switch (complexity) {
    case 'simple': return 'gpt-4o-mini';       // 저비용
    case 'moderate': return 'claude-sonnet-4-20250514';   // 중간
    case 'complex': return 'claude-opus-4-20250514';      // 고비용 (필요 시만)
  }
}
```

### 프롬프트 최적화

```typescript
// ❌ 비효율적: 매번 긴 시스템 프롬프트 전송
const systemPrompt = `당신은 ... (3000 토큰 분량의 상세 지시)`;

// ✅ 캐싱 활용
// Anthropic: cache_control 사용
// OpenAI: 동일 prefix 자동 캐싱

// ✅ 불필요한 컨텍스트 제거
// 검색된 5개 문서 중 관련도 높은 3개만 사용
const relevantContexts = contexts.filter(c => c.score > 0.7).slice(0, 3);
```

### 임베딩 비용 절감

```typescript
// 1. 차원 축소: 3072 → 512 (6x 저장 비용 절감)
dimensions: 512

// 2. 배치 임베딩: API 호출 수 최소화
// 개별 호출 대신 한 번에 2048개까지

// 3. 임베딩 캐시: 동일 텍스트 재계산 방지

// 4. 로컬 모델: API 비용 제로
// bge-m3, multilingual-e5-small 등
```

## 4. Rate Limit 대응

```typescript
class RateLimiter {
  private tokens: number;
  private maxTokens: number;
  private refillRate: number; // tokens per second
  private lastRefill: number;

  constructor(maxTokens: number, refillRate: number) {
    this.maxTokens = maxTokens;
    this.tokens = maxTokens;
    this.refillRate = refillRate;
    this.lastRefill = Date.now();
  }

  async acquire(cost: number = 1): Promise<void> {
    this.refill();
    while (this.tokens < cost) {
      const waitTime = (cost - this.tokens) / this.refillRate * 1000;
      await sleep(waitTime);
      this.refill();
    }
    this.tokens -= cost;
  }

  private refill() {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(this.maxTokens, this.tokens + elapsed * this.refillRate);
    this.lastRefill = now;
  }
}

// 사용
const limiter = new RateLimiter(10000, 1000); // 10K tokens, 1K/sec refill
await limiter.acquire(estimatedTokens);
const response = await openai.chat.completions.create({ ... });
```

## 5. 비용 알림

```typescript
class CostAlert {
  private dailyBudget: number;
  private monthlyBudget: number;

  async checkAndAlert(tracker: CostTracker) {
    const today = new Date().toISOString().split('T')[0];
    const dailyCost = tracker.getDailyCost(today);

    if (dailyCost > this.dailyBudget * 0.8) {
      await notify(`⚠️ 일일 비용 80% 도달: $${dailyCost.toFixed(2)} / $${this.dailyBudget}`);
    }
    if (dailyCost > this.dailyBudget) {
      await notify(`🔴 일일 예산 초과: $${dailyCost.toFixed(2)}`);
      // 선택: 저비용 모델로 자동 전환
    }
  }
}
```

## 6. 비용 리포트

```typescript
// 주간/월간 비용 리포트
interface CostReport {
  period: string;
  totalCost: number;
  breakdown: {
    byModel: Record<string, number>;
    byEndpoint: Record<string, number>;
    byDay: Record<string, number>;
  };
  optimization: {
    cacheHitRate: number;       // 캐시 히트율
    savedByCaching: number;     // 캐시로 절약한 비용
    avgTokensPerRequest: number;
  };
}
```
