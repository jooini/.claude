# Agent Frameworks

> 참조 링크: https://js.langchain.com/docs/, https://docs.llamaindex.ai/, https://sdk.vercel.ai/docs

---

## 1. 프레임워크 비교

| | LangChain | LlamaIndex | Vercel AI SDK |
|---|-----------|------------|---------------|
| 강점 | 범용 에이전트/체인 | RAG 특화 | 스트리밍 UI 통합 |
| 언어 | Python, JS/TS | Python, TS | TS (Next.js) |
| 추상화 수준 | 높음 | 높음 (RAG) | 낮음 (가벼움) |
| 적합한 경우 | 복잡한 에이전트 워크플로우 | 문서 검색/Q&A | 프론트엔드 통합 |
| 학습 곡선 | 높음 | 중간 | 낮음 |

## 2. Vercel AI SDK

Next.js와 가장 자연스럽게 통합된다. 스트리밍, UI 컴포넌트 내장.

```typescript
// app/api/chat/route.ts
import { anthropic } from '@ai-sdk/anthropic';
import { streamText } from 'ai';

export async function POST(req: Request) {
  const { messages } = await req.json();

  const result = streamText({
    model: anthropic('claude-sonnet-4-20250514'),
    system: 'You are a helpful assistant.',
    messages,
  });

  return result.toDataStreamResponse();
}
```

```typescript
// 클라이언트
'use client';
import { useChat } from 'ai/react';

export function Chat() {
  const { messages, input, handleInputChange, handleSubmit } = useChat();

  return (
    <div>
      {messages.map(m => (
        <div key={m.id}>{m.role}: {m.content}</div>
      ))}
      <form onSubmit={handleSubmit}>
        <input value={input} onChange={handleInputChange} />
      </form>
    </div>
  );
}
```

### Tool Use (AI SDK)

```typescript
import { tool } from 'ai';
import { z } from 'zod';

const result = streamText({
  model: anthropic('claude-sonnet-4-20250514'),
  messages,
  tools: {
    getWeather: tool({
      description: 'Get weather for a location',
      parameters: z.object({
        location: z.string().describe('City name'),
      }),
      execute: async ({ location }) => {
        const weather = await fetchWeather(location);
        return weather;
      },
    }),
  },
});
```

## 3. LangChain

### 기본 체인

```typescript
import { ChatAnthropic } from '@langchain/anthropic';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { StringOutputParser } from '@langchain/core/output_parsers';

const model = new ChatAnthropic({ model: 'claude-sonnet-4-20250514' });

const prompt = ChatPromptTemplate.fromMessages([
  ['system', 'You are a {role}. Answer concisely.'],
  ['human', '{question}'],
]);

const chain = prompt.pipe(model).pipe(new StringOutputParser());

const result = await chain.invoke({
  role: 'technical writer',
  question: 'What is RAG?',
});
```

### RAG 체인

```typescript
import { createRetrievalChain } from 'langchain/chains/retrieval';
import { createStuffDocumentsChain } from 'langchain/chains/combine_documents';

const retriever = vectorStore.asRetriever({ k: 5 });

const combineDocsChain = await createStuffDocumentsChain({
  llm: model,
  prompt: ChatPromptTemplate.fromMessages([
    ['system', 'Answer based on the following context:\n{context}'],
    ['human', '{input}'],
  ]),
});

const ragChain = await createRetrievalChain({
  retriever,
  combineDocsChain,
});

const result = await ragChain.invoke({ input: 'What is vector search?' });
// result.answer, result.context
```

### 에이전트

```typescript
import { createToolCallingAgent, AgentExecutor } from 'langchain/agents';

const tools = [searchTool, calculatorTool, webBrowserTool];

const agent = createToolCallingAgent({
  llm: model,
  tools,
  prompt: ChatPromptTemplate.fromMessages([
    ['system', 'You are a helpful assistant with access to tools.'],
    ['human', '{input}'],
    ['placeholder', '{agent_scratchpad}'],
  ]),
});

const executor = new AgentExecutor({ agent, tools });
const result = await executor.invoke({ input: 'Search for the latest AI news' });
```

## 4. LlamaIndex

### 기본 RAG

```typescript
import { VectorStoreIndex, SimpleDirectoryReader } from 'llamaindex';

// 문서 로드
const documents = await new SimpleDirectoryReader().loadData('./docs');

// 인덱스 생성 (자동 청킹 + 임베딩)
const index = await VectorStoreIndex.fromDocuments(documents);

// 쿼리
const queryEngine = index.asQueryEngine();
const response = await queryEngine.query('What is RAG?');
console.log(response.toString());
```

### 커스텀 설정

```typescript
import { Settings } from 'llamaindex';
import { Anthropic } from '@llamaindex/anthropic';

Settings.llm = new Anthropic({ model: 'claude-sonnet-4-20250514' });
Settings.embedModel = new OpenAIEmbedding({ model: 'text-embedding-3-small' });
Settings.chunkSize = 512;
Settings.chunkOverlap = 50;
```

## 5. 프레임워크 없이 (직접 구현)

간단한 RAG는 프레임워크 없이 구현하는 것이 더 명확하다.

```typescript
// 직접 구현한 RAG 파이프라인
class SimpleRAG {
  constructor(
    private embedder: EmbedFunction,
    private vectorDB: VectorDB,
    private llm: LLMClient,
  ) {}

  async query(question: string): Promise<{ answer: string; sources: Source[] }> {
    // 1. 쿼리 임베딩
    const queryVector = await this.embedder(question);

    // 2. 검색
    const results = await this.vectorDB.search(queryVector, { limit: 5 });

    // 3. 컨텍스트 구성
    const context = results.map(r => r.content).join('\n\n---\n\n');

    // 4. 생성
    const answer = await this.llm.complete({
      system: `Answer based on the context. If unsure, say so.\n\nContext:\n${context}`,
      prompt: question,
    });

    return { answer, sources: results };
  }
}
```

## 6. 선택 가이드

| 상황 | 추천 |
|------|------|
| Next.js + 채팅 UI | Vercel AI SDK |
| 복잡한 에이전트 워크플로우 | LangChain |
| 문서 Q&A (빠른 프로토타입) | LlamaIndex |
| 간단한 RAG (프로덕션) | 직접 구현 |
| 프레임워크 학습/실험 | LangChain (생태계 가장 큼) |
