# LLM API 연동

> 참조 링크: https://platform.openai.com/docs/api-reference, https://docs.anthropic.com/en/api, https://ai.google.dev/api

---

## 1. 주요 LLM 제공자 비교

| 제공자 | 주요 모델 | 최대 컨텍스트 | 강점 |
|--------|----------|-------------|------|
| **OpenAI** | GPT-4o, GPT-4o-mini, o1 | 128K | 범용, 에코시스템 |
| **Anthropic** | Claude 4 Opus/Sonnet | 200K | 긴 컨텍스트, 안전성 |
| **Google** | Gemini 2.5 Pro/Flash | 1M | 멀티모달, 긴 컨텍스트 |

## 2. OpenAI SDK

### 기본 설정

```typescript
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
  timeout: 30_000,     // 30초 타임아웃
  maxRetries: 3,       // 자동 재시도
});
```

### Chat Completion

```typescript
async function chatCompletion(
  messages: OpenAI.Chat.ChatCompletionMessageParam[],
  options?: { model?: string; temperature?: number; maxTokens?: number },
): Promise<string> {
  const response = await openai.chat.completions.create({
    model: options?.model ?? 'gpt-4o',
    messages,
    temperature: options?.temperature ?? 0.7,
    max_tokens: options?.maxTokens ?? 4096,
  });

  return response.choices[0].message.content ?? '';
}
```

### Structured Output (JSON Mode)

```typescript
import { zodResponseFormat } from 'openai/helpers/zod';
import { z } from 'zod';

const AnalysisSchema = z.object({
  sentiment: z.enum(['positive', 'negative', 'neutral']),
  confidence: z.number().min(0).max(1),
  keywords: z.array(z.string()),
  summary: z.string(),
});

async function analyzeText(text: string) {
  const response = await openai.beta.chat.completions.parse({
    model: 'gpt-4o',
    messages: [
      { role: 'system', content: '텍스트를 분석하세요.' },
      { role: 'user', content: text },
    ],
    response_format: zodResponseFormat(AnalysisSchema, 'analysis'),
  });

  const parsed = response.choices[0].message.parsed; // 타입 안전한 결과
  return parsed;
}
```

## 3. Anthropic SDK

### 기본 설정

```typescript
import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
  timeout: 60_000,
  maxRetries: 2,
});
```

### Messages API

```typescript
async function claudeCompletion(
  systemPrompt: string,
  messages: Anthropic.MessageParam[],
): Promise<string> {
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 4096,
    system: systemPrompt,
    messages,
  });

  // content 배열에서 텍스트 추출
  const textBlock = response.content.find(block => block.type === 'text');
  return textBlock?.text ?? '';
}
```

### Extended Thinking

```typescript
async function claudeWithThinking(question: string): Promise<{ thinking: string; answer: string }> {
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 16000,
    thinking: {
      type: 'enabled',
      budget_tokens: 10000, // thinking에 할당할 최대 토큰
    },
    messages: [{ role: 'user', content: question }],
  });

  let thinking = '';
  let answer = '';
  for (const block of response.content) {
    if (block.type === 'thinking') thinking = block.thinking;
    if (block.type === 'text') answer = block.text;
  }

  return { thinking, answer };
}
```

## 4. 스트리밍

### OpenAI 스트리밍

```typescript
async function* streamOpenAI(messages: OpenAI.Chat.ChatCompletionMessageParam[]): AsyncGenerator<string> {
  const stream = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages,
    stream: true,
  });

  for await (const chunk of stream) {
    const content = chunk.choices[0]?.delta?.content;
    if (content) yield content;
  }
}
```

### Anthropic 스트리밍

```typescript
async function* streamAnthropic(messages: Anthropic.MessageParam[]): AsyncGenerator<string> {
  const stream = anthropic.messages.stream({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 4096,
    messages,
  });

  for await (const event of stream) {
    if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
      yield event.delta.text;
    }
  }
}
```

## 5. 에러 처리

### 공통 에러 패턴

```typescript
import OpenAI from 'openai';

async function robustCompletion(messages: OpenAI.Chat.ChatCompletionMessageParam[]): Promise<string> {
  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages,
    });
    return response.choices[0].message.content ?? '';
  } catch (error) {
    if (error instanceof OpenAI.RateLimitError) {
      // 429: Rate limit — SDK가 자동 재시도하지만 초과 시 여기 도달
      console.error('Rate limit exceeded, backing off');
      await sleep(error.headers?.['retry-after'] ? parseInt(error.headers['retry-after']) * 1000 : 10_000);
      return robustCompletion(messages); // 재시도
    }

    if (error instanceof OpenAI.APIConnectionError) {
      // 네트워크 문제
      console.error('Connection error:', error.message);
      throw new Error('LLM 서비스에 연결할 수 없습니다');
    }

    if (error instanceof OpenAI.AuthenticationError) {
      // 401: API 키 문제
      throw new Error('잘못된 API 키입니다');
    }

    if (error instanceof OpenAI.BadRequestError) {
      // 400: 요청 문제 (토큰 초과 등)
      if (error.message.includes('maximum context length')) {
        throw new Error('입력이 모델의 최대 컨텍스트를 초과합니다');
      }
      throw error;
    }

    throw error;
  }
}
```

### 재시도 + 폴백 전략

```typescript
interface LLMConfig {
  primary: { model: string; provider: 'openai' | 'anthropic' };
  fallback: { model: string; provider: 'openai' | 'anthropic' };
  maxRetries: number;
}

class ResilientLLMClient {
  private config: LLMConfig;

  async complete(messages: any[]): Promise<string> {
    // 1차: primary 모델 시도
    try {
      return await this.callProvider(this.config.primary, messages);
    } catch (primaryError) {
      console.warn(`Primary model failed: ${primaryError}`);
    }

    // 2차: fallback 모델로 전환
    try {
      return await this.callProvider(this.config.fallback, messages);
    } catch (fallbackError) {
      console.error(`Fallback model also failed: ${fallbackError}`);
      throw new Error('모든 LLM 제공자가 실패했습니다');
    }
  }

  private async callProvider(
    config: { model: string; provider: string },
    messages: any[],
  ): Promise<string> {
    switch (config.provider) {
      case 'openai':
        return this.callOpenAI(config.model, messages);
      case 'anthropic':
        return this.callAnthropic(config.model, messages);
      default:
        throw new Error(`Unknown provider: ${config.provider}`);
    }
  }
}

// 사용 예시
const client = new ResilientLLMClient({
  primary: { model: 'gpt-4o', provider: 'openai' },
  fallback: { model: 'claude-sonnet-4-20250514', provider: 'anthropic' },
  maxRetries: 3,
});
```

## 6. 토큰 사용량 추적

```typescript
interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  estimatedCost: number;
}

class TokenTracker {
  private usageLog: TokenUsage[] = [];
  private costPerToken: Record<string, { input: number; output: number }> = {
    'gpt-4o': { input: 2.5 / 1_000_000, output: 10 / 1_000_000 },
    'gpt-4o-mini': { input: 0.15 / 1_000_000, output: 0.6 / 1_000_000 },
    'claude-sonnet-4-20250514': { input: 3 / 1_000_000, output: 15 / 1_000_000 },
  };

  track(model: string, usage: OpenAI.CompletionUsage): TokenUsage {
    const rates = this.costPerToken[model] ?? { input: 0, output: 0 };
    const tracked: TokenUsage = {
      promptTokens: usage.prompt_tokens,
      completionTokens: usage.completion_tokens,
      totalTokens: usage.total_tokens,
      estimatedCost: usage.prompt_tokens * rates.input + usage.completion_tokens * rates.output,
    };

    this.usageLog.push(tracked);
    return tracked;
  }

  getTotalCost(): number {
    return this.usageLog.reduce((sum, u) => sum + u.estimatedCost, 0);
  }
}
```

## 7. 프로바이더 추상화

```typescript
interface LLMProvider {
  complete(params: CompletionParams): Promise<CompletionResult>;
  stream(params: CompletionParams): AsyncGenerator<string>;
  embed(input: string[]): Promise<number[][]>;
}

interface CompletionParams {
  messages: { role: string; content: string }[];
  temperature?: number;
  maxTokens?: number;
  responseFormat?: 'text' | 'json';
}

interface CompletionResult {
  content: string;
  usage: { inputTokens: number; outputTokens: number };
  model: string;
  finishReason: string;
}

// 구현체를 주입받아 사용
class AIService {
  constructor(private provider: LLMProvider) {}

  async summarize(text: string): Promise<string> {
    const result = await this.provider.complete({
      messages: [
        { role: 'system', content: '텍스트를 3줄로 요약하세요.' },
        { role: 'user', content: text },
      ],
    });
    return result.content;
  }
}
```
