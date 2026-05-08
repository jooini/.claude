# Function Calling / Tool Use

> 참조 링크: https://docs.anthropic.com/en/docs/build-with-claude/tool-use, https://platform.openai.com/docs/guides/function-calling

---

## 1. 개요

LLM이 외부 함수/API를 호출할 수 있도록 하는 패턴. 모델이 직접 실행하는 것이 아니라, **어떤 함수를 어떤 인자로 호출할지 결정**하고 애플리케이션이 실행한다.

## 2. Anthropic Tool Use

```typescript
import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic();

const response = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  tools: [
    {
      name: 'get_weather',
      description: 'Get current weather for a city. Use when the user asks about weather.',
      input_schema: {
        type: 'object',
        properties: {
          city: { type: 'string', description: 'City name (e.g., "Seoul")' },
          unit: { type: 'string', enum: ['celsius', 'fahrenheit'], default: 'celsius' },
        },
        required: ['city'],
      },
    },
  ],
  messages: [{ role: 'user', content: '서울 날씨 어때?' }],
});

// 응답에서 tool_use 블록 처리
for (const block of response.content) {
  if (block.type === 'tool_use') {
    const result = await executeFunction(block.name, block.input);

    // 결과를 모델에 반환
    const followUp = await client.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1024,
      tools: [/* 동일 */],
      messages: [
        { role: 'user', content: '서울 날씨 어때?' },
        { role: 'assistant', content: response.content },
        { role: 'user', content: [{ type: 'tool_result', tool_use_id: block.id, content: JSON.stringify(result) }] },
      ],
    });
  }
}
```

## 3. OpenAI Function Calling

```typescript
import OpenAI from 'openai';

const openai = new OpenAI();

const response = await openai.chat.completions.create({
  model: 'gpt-4o',
  messages: [{ role: 'user', content: '서울 날씨 어때?' }],
  tools: [
    {
      type: 'function',
      function: {
        name: 'get_weather',
        description: 'Get current weather for a city',
        parameters: {
          type: 'object',
          properties: {
            city: { type: 'string', description: 'City name' },
          },
          required: ['city'],
        },
      },
    },
  ],
});

const toolCall = response.choices[0].message.tool_calls?.[0];
if (toolCall) {
  const args = JSON.parse(toolCall.function.arguments);
  const result = await executeFunction(toolCall.function.name, args);

  const followUp = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      { role: 'user', content: '서울 날씨 어때?' },
      response.choices[0].message,
      { role: 'tool', tool_call_id: toolCall.id, content: JSON.stringify(result) },
    ],
    tools: [/* 동일 */],
  });
}
```

## 4. 도구 스키마 설계

### 좋은 스키마 원칙

```typescript
// ✅ 명확한 description — 모델이 언제 사용할지 판단하는 근거
{
  name: 'search_products',
  description: 'Search products in the catalog. Use when the user wants to find, browse, or filter products by name, category, or price range.',
  input_schema: {
    type: 'object',
    properties: {
      query: { type: 'string', description: 'Search keywords (e.g., "wireless headphones")' },
      category: { type: 'string', enum: ['electronics', 'clothing', 'food'], description: 'Product category filter' },
      maxPrice: { type: 'number', description: 'Maximum price in USD' },
      sortBy: { type: 'string', enum: ['relevance', 'price_asc', 'price_desc', 'rating'], default: 'relevance' },
    },
    required: ['query'],
  },
}

// ❌ 모호한 description
{
  name: 'search',
  description: 'Search for things', // 언제 사용해야 하는지 불명확
}
```

### Enum 활용

가능한 값이 제한된 경우 `enum`으로 명시하면 모델의 정확도가 올라간다.

### 필수 vs 선택 파라미터

- `required`: 반드시 필요한 파라미터만
- 나머지는 `default` 값과 함께 선택 파라미터로

## 5. 다중 도구 호출

```typescript
// Claude는 한 번의 응답에서 여러 도구를 호출할 수 있다
// 예: "서울과 도쿄 날씨 비교해줘" → get_weather("Seoul") + get_weather("Tokyo")

// 병렬 실행
const toolCalls = response.content.filter(b => b.type === 'tool_use');
const results = await Promise.all(
  toolCalls.map(tc => executeFunction(tc.name, tc.input))
);
```

## 6. 에러 핸들링

```typescript
async function executeFunction(name: string, input: any): Promise<any> {
  try {
    switch (name) {
      case 'get_weather': return await getWeather(input.city);
      case 'search_products': return await searchProducts(input);
      default: return { error: `Unknown function: ${name}` };
    }
  } catch (error: any) {
    // 에러를 모델에 반환 — 모델이 사용자에게 적절히 설명
    return {
      error: error.message,
      suggestion: 'Please try again or rephrase your request.',
    };
  }
}
```

## 7. 도구 선택 제어

```typescript
// Anthropic
tool_choice: { type: 'auto' }     // 모델이 판단 (기본)
tool_choice: { type: 'any' }      // 반드시 하나 이상 호출
tool_choice: { type: 'tool', name: 'get_weather' } // 특정 도구 강제

// OpenAI
tool_choice: 'auto'               // 기본
tool_choice: 'required'           // 반드시 호출
tool_choice: { type: 'function', function: { name: 'get_weather' } }
```

## 8. 도구 사용 루프

```typescript
async function agentLoop(userMessage: string, tools: Tool[], maxIterations: number = 10) {
  const messages: Message[] = [{ role: 'user', content: userMessage }];

  for (let i = 0; i < maxIterations; i++) {
    const response = await client.messages.create({
      model: 'claude-sonnet-4-20250514',
      tools,
      messages,
      max_tokens: 4096,
    });

    messages.push({ role: 'assistant', content: response.content });

    // 도구 호출이 없으면 최종 응답
    const toolUses = response.content.filter(b => b.type === 'tool_use');
    if (toolUses.length === 0) {
      return response.content.filter(b => b.type === 'text').map(b => b.text).join('');
    }

    // 도구 실행 + 결과 반환
    const toolResults = await Promise.all(
      toolUses.map(async tc => ({
        type: 'tool_result' as const,
        tool_use_id: tc.id,
        content: JSON.stringify(await executeFunction(tc.name, tc.input)),
      }))
    );

    messages.push({ role: 'user', content: toolResults });
  }

  throw new Error('Max iterations reached');
}
```
