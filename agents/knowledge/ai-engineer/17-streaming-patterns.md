# Streaming Patterns

> 참조 링크: https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events, https://sdk.vercel.ai/docs/ai-sdk-ui/streaming

---

## 1. 스트리밍이 필요한 이유

LLM 응답은 수 초~수십 초 걸린다. 전체 응답을 기다리면 UX가 나쁘다. 토큰 단위로 스트리밍하면 첫 토큰까지의 지연(TTFT)을 크게 줄인다.

## 2. SSE (Server-Sent Events)

### 서버 (Next.js App Router)

```typescript
// app/api/chat/route.ts
import Anthropic from '@anthropic-ai/sdk';

export async function POST(req: Request) {
  const { messages } = await req.json();
  const client = new Anthropic();

  const stream = await client.messages.stream({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    messages,
  });

  const encoder = new TextEncoder();

  const readableStream = new ReadableStream({
    async start(controller) {
      for await (const event of stream) {
        if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
          const data = JSON.stringify({ text: event.delta.text });
          controller.enqueue(encoder.encode(`data: ${data}\n\n`));
        }
      }
      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      controller.close();
    },
  });

  return new Response(readableStream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    },
  });
}
```

### 클라이언트

```typescript
async function streamChat(message: string, onChunk: (text: string) => void) {
  const response = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ messages: [{ role: 'user', content: message }] }),
  });

  const reader = response.body!.getReader();
  const decoder = new TextDecoder();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const text = decoder.decode(value);
    const lines = text.split('\n').filter(l => l.startsWith('data: '));

    for (const line of lines) {
      const data = line.slice(6); // 'data: ' 제거
      if (data === '[DONE]') return;
      const parsed = JSON.parse(data);
      onChunk(parsed.text);
    }
  }
}

// React에서 사용
const [response, setResponse] = useState('');
await streamChat('Hello', (chunk) => {
  setResponse(prev => prev + chunk);
});
```

## 3. Vercel AI SDK 스트리밍

가장 간단한 구현.

```typescript
// 서버
import { anthropic } from '@ai-sdk/anthropic';
import { streamText } from 'ai';

export async function POST(req: Request) {
  const { messages } = await req.json();
  const result = streamText({
    model: anthropic('claude-sonnet-4-20250514'),
    messages,
  });
  return result.toDataStreamResponse();
}

// 클라이언트
import { useChat } from 'ai/react';

function Chat() {
  const { messages, input, handleInputChange, handleSubmit, isLoading } = useChat();
  // messages가 자동으로 스트리밍 업데이트됨
}
```

## 4. OpenAI 스트리밍

```typescript
const stream = await openai.chat.completions.create({
  model: 'gpt-4o',
  messages: [{ role: 'user', content: 'Hello' }],
  stream: true,
});

for await (const chunk of stream) {
  const text = chunk.choices[0]?.delta?.content;
  if (text) process.stdout.write(text);
}
```

## 5. Anthropic 스트리밍

```typescript
const stream = client.messages.stream({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  messages: [{ role: 'user', content: 'Hello' }],
});

// 이벤트 기반
stream.on('text', (text) => process.stdout.write(text));
stream.on('message', (message) => console.log('완료:', message.usage));
stream.on('error', (error) => console.error(error));

// 또는 async iterator
for await (const event of stream) {
  if (event.type === 'content_block_delta') {
    process.stdout.write(event.delta.text);
  }
}
```

## 6. Tool Use 스트리밍

도구 호출 중에도 스트리밍이 가능하다.

```typescript
import { streamText } from 'ai';

const result = streamText({
  model: anthropic('claude-sonnet-4-20250514'),
  messages,
  tools: { getWeather: weatherTool },
  onStepFinish({ toolCalls, toolResults }) {
    // 도구 호출 완료 시 콜백
    console.log('Tool calls:', toolCalls);
    console.log('Tool results:', toolResults);
  },
});

// 도구 결과 후 텍스트 응답도 스트리밍됨
```

## 7. 백프레셔 처리

클라이언트가 느릴 때 서버가 데이터를 과도하게 보내지 않도록 한다.

```typescript
const readableStream = new ReadableStream({
  async start(controller) {
    for await (const event of stream) {
      // backpressure: desiredSize가 0 이하면 대기
      while (controller.desiredSize !== null && controller.desiredSize <= 0) {
        await sleep(10);
      }
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
    }
    controller.close();
  },
});
```

## 8. 에러 처리

```typescript
// 서버: 스트리밍 중 에러 발생
const readableStream = new ReadableStream({
  async start(controller) {
    try {
      for await (const event of stream) {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
      }
    } catch (error: any) {
      // 에러를 SSE 이벤트로 전송
      controller.enqueue(encoder.encode(
        `data: ${JSON.stringify({ error: error.message })}\n\n`
      ));
    } finally {
      controller.close();
    }
  },
});

// 클라이언트: 연결 끊김 재시도
const eventSource = new EventSource('/api/stream');
eventSource.onerror = () => {
  // 자동 재연결 (EventSource 기본 동작)
  // 또는 수동 재시도 로직
};
```

## 9. WebSocket vs SSE

| | SSE | WebSocket |
|---|-----|-----------|
| 방향 | 서버 → 클라이언트 (단방향) | 양방향 |
| 프로토콜 | HTTP | ws:// |
| 자동 재연결 | ✅ (내장) | ❌ (직접 구현) |
| LLM 스트리밍 | ✅ 적합 | 과도함 (양방향 불필요) |
| 실시간 채팅 | ⚠️ (요청마다 새 연결) | ✅ 적합 |

**LLM 응답 스트리밍에는 SSE가 적합**하다. 단방향이면 충분하고, HTTP 기반이라 인프라 호환성이 좋다.
