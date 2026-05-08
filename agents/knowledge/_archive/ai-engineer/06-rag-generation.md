# RAG 생성 전략

> 참조 링크: https://docs.anthropic.com/en/docs/build-with-claude/citations, https://arxiv.org/abs/2305.14627

---

## 1. 컨텍스트 주입 패턴

### 기본 시스템 프롬프트 패턴

```typescript
function buildRAGPrompt(context: string, question: string): ChatMessage[] {
  return [
    {
      role: 'system',
      content: `당신은 제공된 문서를 기반으로 정확하게 답변하는 어시스턴트입니다.

## 규칙
1. 제공된 문서에 있는 정보만 사용하세요.
2. 문서에 답이 없으면 "제공된 문서에서 해당 정보를 찾을 수 없습니다"라고 답하세요.
3. 답변에 출처를 명시하세요.

## 참고 문서
${context}`,
    },
    { role: 'user', content: question },
  ];
}
```

### Stuffing vs Map-Reduce vs Refine

| 패턴 | 방식 | 적합한 경우 |
|------|------|-----------|
| **Stuffing** | 모든 문서를 한 번에 주입 | 컨텍스트 윈도우 내 문서량 |
| **Map-Reduce** | 문서별 답변 생성 → 합산 | 문서 수가 많을 때 |
| **Refine** | 순차적으로 답변 개선 | 정밀한 답변이 필요할 때 |

### Map-Reduce 구현

```typescript
class MapReduceGenerator {
  async generate(question: string, documents: Document[]): Promise<string> {
    // Map: 각 문서에서 부분 답변 추출
    const partialAnswers = await Promise.all(
      documents.map(doc => this.extractAnswer(question, doc.content)),
    );

    // 빈 답변 제거
    const validAnswers = partialAnswers.filter(a => a.trim() !== '');

    // Reduce: 부분 답변들을 하나로 합산
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: `다음 부분 답변들을 종합하여 하나의 일관된 답변을 작성하세요.
중복을 제거하고, 정보를 구조화하세요.`,
        },
        {
          role: 'user',
          content: `질문: ${question}\n\n부분 답변:\n${validAnswers.map((a, i) => `[${i + 1}] ${a}`).join('\n\n')}`,
        },
      ],
    });

    return response.choices[0].message.content ?? '';
  }

  private async extractAnswer(question: string, docContent: string): Promise<string> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o-mini', // Map 단계는 경량 모델 사용
      messages: [
        {
          role: 'system',
          content: '문서에서 질문과 관련된 정보만 추출하세요. 관련 정보가 없으면 빈 문자열을 반환하세요.',
        },
        { role: 'user', content: `질문: ${question}\n\n문서:\n${docContent}` },
      ],
    });

    return response.choices[0].message.content ?? '';
  }
}
```

### Refine 구현

```typescript
class RefineGenerator {
  async generate(question: string, documents: Document[]): Promise<string> {
    let currentAnswer = '';

    for (const doc of documents) {
      if (!currentAnswer) {
        // 첫 문서: 초기 답변 생성
        currentAnswer = await this.initialAnswer(question, doc.content);
      } else {
        // 후속 문서: 기존 답변을 개선
        currentAnswer = await this.refineAnswer(question, doc.content, currentAnswer);
      }
    }

    return currentAnswer;
  }

  private async refineAnswer(question: string, newContext: string, existingAnswer: string): Promise<string> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: `기존 답변을 새로운 문서의 정보로 보완하세요.
- 새 정보가 기존 답변과 충돌하면 문서 기반으로 수정하세요.
- 새 정보가 관련 없으면 기존 답변을 유지하세요.
- 이미 있는 정보를 중복하지 마세요.`,
        },
        {
          role: 'user',
          content: `질문: ${question}\n\n기존 답변:\n${existingAnswer}\n\n새 문서:\n${newContext}`,
        },
      ],
    });

    return response.choices[0].message.content ?? existingAnswer;
  }
}
```

## 2. Hallucination 방지

### Grounded Generation

```typescript
const groundedSystemPrompt = `당신은 제공된 문서만을 근거로 답변하는 어시스턴트입니다.

## 절대 규칙
1. 제공된 문서에 **명시적으로 있는 정보만** 사용하세요.
2. 문서의 정보를 추론하거나 확장하지 마세요.
3. 확실하지 않은 정보에는 "문서에 명확히 나와있지 않습니다"를 붙이세요.
4. 문서에 없는 질문에는 답하지 마세요.

## 답변 형식
- 각 주장 뒤에 [출처: 문서명] 형태로 출처를 표기하세요.
- 여러 문서의 정보를 결합할 때는 각 문서의 출처를 별도로 표기하세요.`;
```

### Chain-of-Note (CoN)

검색된 문서 각각의 관련성을 먼저 평가하고, 관련 문서만으로 답변을 생성한다.

```typescript
class ChainOfNoteGenerator {
  async generate(question: string, documents: Document[]): Promise<string> {
    // 1단계: 각 문서에 대한 관련성 노트 작성
    const notes = await this.generateNotes(question, documents);

    // 2단계: 관련 노트만 필터링
    const relevantNotes = notes.filter(n => n.isRelevant);

    if (relevantNotes.length === 0) {
      return '제공된 문서에서 질문에 대한 답변을 찾을 수 없습니다.';
    }

    // 3단계: 관련 노트 기반 최종 답변 생성
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: '다음 분석 노트를 기반으로 질문에 답하세요. 노트에 있는 정보만 사용하세요.',
        },
        {
          role: 'user',
          content: `질문: ${question}\n\n분석 노트:\n${relevantNotes.map(n => n.note).join('\n\n')}`,
        },
      ],
    });

    return response.choices[0].message.content ?? '';
  }

  private async generateNotes(question: string, documents: Document[]): Promise<NoteResult[]> {
    const results = await Promise.all(
      documents.map(async (doc, i) => {
        const response = await this.openai.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `문서를 읽고 질문과의 관련성을 분석하세요.
JSON 형식: { "isRelevant": boolean, "note": "관련 정보 요약 또는 무관한 이유" }`,
            },
            { role: 'user', content: `질문: ${question}\n\n문서 [${i + 1}]:\n${doc.content}` },
          ],
        });

        return JSON.parse(response.choices[0].message.content ?? '{}') as NoteResult;
      }),
    );

    return results;
  }
}
```

## 3. Citation (출처 표기)

### 인라인 Citation

```typescript
const citationPrompt = `답변 시 다음 규칙으로 출처를 표기하세요:

1. 각 문장 끝에 [1], [2] 형식으로 출처 번호를 붙이세요.
2. 여러 문서에서 가져온 정보는 [1][3] 처럼 복수 표기하세요.
3. 답변 끝에 출처 목록을 추가하세요.

## 참고 문서
{{#each documents}}
[{{@index}}] {{this.title}} - {{this.content}}
{{/each}}`;

// 출력 예시:
// NestJS에서 TypeORM을 설정하려면 먼저 패키지를 설치합니다 [1].
// 연결 설정은 app.module.ts에서 TypeOrmModule.forRoot()를 사용합니다 [1][2].
//
// 출처:
// [1] NestJS TypeORM 공식 문서
// [2] TypeORM 연결 가이드
```

### 구조화된 Citation 응답

```typescript
interface CitedAnswer {
  answer: string;
  citations: Citation[];
}

interface Citation {
  text: string;        // 인용한 원문
  documentId: string;  // 출처 문서 ID
  documentTitle: string;
  startIndex: number;  // 원문에서의 위치
  endIndex: number;
}

async function generateWithCitations(
  question: string,
  documents: Document[],
  openai: OpenAI,
): Promise<CitedAnswer> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o',
    messages: [
      {
        role: 'system',
        content: `질문에 답변하고 출처를 구조화된 JSON으로 반환하세요.
형식:
{
  "answer": "답변 텍스트 [1] ...",
  "citations": [
    { "text": "인용한 원문", "documentId": "doc_id", "documentTitle": "제목" }
  ]
}`,
      },
      {
        role: 'user',
        content: `질문: ${question}\n\n문서:\n${documents.map((d, i) => `[${i + 1}] (${d.id}) ${d.title}\n${d.content}`).join('\n\n')}`,
      },
    ],
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content ?? '{}');
}
```

## 4. 컨텍스트 윈도우 관리

```typescript
class ContextWindowManager {
  private maxTokens: number;      // 모델의 최대 컨텍스트 (예: 128000)
  private reservedForOutput: number; // 출력용 예약 (예: 4096)
  private systemPromptTokens: number;

  // 문서를 토큰 한도 내에서 최대한 포함
  selectDocuments(documents: Document[]): Document[] {
    const available = this.maxTokens - this.reservedForOutput - this.systemPromptTokens;
    const selected: Document[] = [];
    let totalTokens = 0;

    for (const doc of documents) {
      const docTokens = this.countTokens(doc.content);
      if (totalTokens + docTokens > available) break;
      selected.push(doc);
      totalTokens += docTokens;
    }

    return selected;
  }

  // 토큰 수 추정 (tiktoken 대신 간이 계산)
  private countTokens(text: string): number {
    return Math.ceil(text.length / 3.5); // 영문 기준 ~4, 한국어 기준 ~2-3
  }
}
```

## 5. Conversational RAG

대화 히스토리를 고려한 RAG. 이전 질문의 맥락을 유지한다.

```typescript
class ConversationalRAG {
  async query(question: string, history: ChatMessage[]): Promise<string> {
    // 1단계: 대화 히스토리를 고려해 독립 질문으로 재작성
    const standaloneQuestion = await this.rewriteWithHistory(question, history);

    // 2단계: 재작성된 질문으로 검색
    const docs = await this.retrieve(standaloneQuestion);

    // 3단계: 히스토리 + 문서 + 질문으로 답변 생성
    const messages: ChatMessage[] = [
      { role: 'system', content: this.buildSystemPrompt(docs) },
      ...history.slice(-6), // 최근 3턴만 유지
      { role: 'user', content: question },
    ];

    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o',
      messages,
    });

    return response.choices[0].message.content ?? '';
  }

  private async rewriteWithHistory(question: string, history: ChatMessage[]): Promise<string> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `대화 히스토리를 참고하여, 사용자의 마지막 질문을 독립적인 검색 쿼리로 재작성하세요.
대명사나 생략된 주어를 명시적으로 바꾸세요. 재작성된 질문만 반환하세요.`,
        },
        {
          role: 'user',
          content: `대화:\n${history.map(m => `${m.role}: ${m.content}`).join('\n')}\n\n마지막 질문: ${question}`,
        },
      ],
    });

    return response.choices[0].message.content ?? question;
  }
}

// 예시 대화:
// User: "NestJS의 가드에 대해 알려줘"
// Assistant: "NestJS 가드는 CanActivate 인터페이스를 구현합니다..."
// User: "그걸 어떻게 테스트해?" 
// → 재작성: "NestJS 가드(Guard)를 단위 테스트하는 방법"
```

## 6. 생성 품질 체크리스트

```
☐ 시스템 프롬프트에 grounding 규칙 명시
☐ 문서에 없는 정보 생성 방지 (hallucination guard)
☐ Citation 형식 결정 (인라인 vs 구조화)
☐ 컨텍스트 윈도우 토큰 관리
☐ Lost-in-the-middle 대응 (중요 문서를 앞/뒤에 배치)
☐ 대화형인 경우 히스토리 기반 질문 재작성
☐ 문서가 부족할 때의 폴백 메시지 정의
☐ 답변 길이/형식 가이드라인 설정
```
