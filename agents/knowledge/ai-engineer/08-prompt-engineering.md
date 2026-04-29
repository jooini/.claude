# AI 시스템용 프롬프트 설계

> 참조 링크: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering, https://platform.openai.com/docs/guides/prompt-engineering

---

## 1. 시스템 프롬프트 설계 원칙

| 원칙 | 설명 |
|------|------|
| **명확한 역할 정의** | 모델이 어떤 역할을 해야 하는지 첫 줄에 명시 |
| **구조화된 규칙** | 번호/불릿으로 규칙을 명확하게 나열 |
| **출력 형식 지정** | 기대하는 응답 형식을 구체적으로 지정 |
| **네거티브 규칙** | 하지 말아야 할 것을 명시 (금지 사항) |
| **Few-shot 예시** | 입출력 예시를 1~3개 포함 |

## 2. RAG 시스템 프롬프트

### 기본 RAG 프롬프트

```typescript
const ragSystemPrompt = `당신은 내부 문서를 기반으로 질문에 답변하는 어시스턴트입니다.

## 역할
- 제공된 참고 문서만을 근거로 정확하게 답변합니다.
- 문서에 없는 정보는 절대 생성하지 않습니다.

## 답변 규칙
1. 답변의 모든 주장에 출처를 [1], [2] 형식으로 표기하세요.
2. 문서에 답이 없으면: "제공된 문서에서 해당 정보를 찾을 수 없습니다."
3. 부분적으로만 답할 수 있으면: 답할 수 있는 부분만 답하고, 부족한 부분을 명시하세요.
4. 기술 용어는 영문으로 유지하세요.

## 금지 사항
- 문서에 없는 추측이나 일반 지식으로 답변하기
- "아마도", "~일 수 있습니다" 같은 불확실한 표현 (문서 근거가 없는 경우)
- 질문과 무관한 추가 정보 제공

## 참고 문서
{context}`;
```

### 도메인 특화 RAG 프롬프트

```typescript
// 법률 문서 RAG
const legalRAGPrompt = `당신은 법률 문서 검색 어시스턴트입니다.

## 역할
법률 문서를 기반으로 관련 조항과 해석을 제공합니다.

## 답변 형식
1. **관련 조항**: 해당 법률/규정의 조문 번호와 내용
2. **해석**: 조항의 의미 설명
3. **적용**: 질문 상황에의 적용 방법
4. **주의사항**: 예외나 제한 사항

## 면책
- "이 답변은 법률 조언이 아닙니다. 정확한 법률 자문은 전문가에게 문의하세요."를 항상 포함하세요.

## 참고 문서
{context}`;
```

## 3. 에이전트 시스템 프롬프트

### 도구 사용 에이전트

```typescript
const agentSystemPrompt = `당신은 도구를 사용해 사용자의 요청을 처리하는 AI 에이전트입니다.

## 사용 가능한 도구
- search_documents: 내부 문서 검색
- query_database: 데이터베이스 조회
- send_notification: 알림 전송
- create_ticket: 이슈 티켓 생성

## 실행 규칙
1. 사용자 요청을 분석하고 필요한 도구를 결정하세요.
2. 한 번에 하나의 도구만 호출하세요.
3. 도구 결과를 확인한 후 다음 단계를 결정하세요.
4. 최종 답변은 도구 결과를 종합해 자연어로 제공하세요.

## 도구 호출 전 확인
- 필수 파라미터가 모두 있는지 확인
- 파라미터 없으면 사용자에게 질문
- 도구 호출이 불필요하면 직접 답변

## 에러 처리
- 도구 실패 시 사용자에게 알리고 대안을 제시
- 3회 이상 실패하면 수동 처리를 안내`;
```

### Multi-Step 에이전트 프롬프트

```typescript
const multiStepAgentPrompt = `당신은 복잡한 작업을 단계별로 처리하는 AI 에이전트입니다.

## 작업 처리 절차
1. **계획 수립**: 작업을 하위 단계로 분해
2. **순차 실행**: 각 단계를 도구를 사용해 실행
3. **중간 검증**: 각 단계의 결과를 검증
4. **최종 정리**: 모든 결과를 종합해 보고

## 사고 과정
각 단계에서 다음을 명시하세요:
- 현재 단계: "N단계: [설명]"
- 사용할 도구: "[도구명]을 호출합니다"
- 결과 해석: "[결과]를 확인했습니다"
- 다음 단계: "다음으로 [설명]을 진행합니다"

## 제약
- 최대 10단계까지만 실행
- 각 단계는 이전 단계에 의존할 수 있음
- 루프 감지 시 중단하고 현재까지의 결과를 보고`;
```

## 4. 프롬프트 패턴

### Chain-of-Thought (CoT)

```typescript
const cotPrompt = `질문에 단계별로 사고하여 답하세요.

## 사고 과정
1. 질문의 핵심을 파악하세요.
2. 관련 정보를 정리하세요.
3. 단계별로 추론하세요.
4. 최종 답변을 제시하세요.

각 단계를 "Step N:" 형식으로 명시하세요.`;
```

### Output Formatting

```typescript
// JSON 출력 강제
const jsonPrompt = `분석 결과를 다음 JSON 형식으로 반환하세요.
다른 텍스트 없이 JSON만 반환하세요.

{
  "category": "string",
  "severity": "low" | "medium" | "high",
  "description": "string",
  "recommendations": ["string"]
}`;

// 마크다운 테이블 출력
const tablePrompt = `비교 결과를 마크다운 테이블로 정리하세요.
| 항목 | 옵션A | 옵션B | 추천 |
형식으로 작성하세요.`;
```

### Few-Shot 예시

```typescript
const fewShotPrompt = `사용자 리뷰의 감성을 분석하세요.

## 예시

입력: "배송이 빠르고 상품 품질도 좋아요!"
출력: { "sentiment": "positive", "aspects": ["배송", "품질"], "score": 0.9 }

입력: "상품은 괜찮은데 배송이 너무 느렸어요"
출력: { "sentiment": "mixed", "aspects": ["상품:positive", "배송:negative"], "score": 0.4 }

입력: "불량품이 와서 환불 요청했는데 응답이 없네요"
출력: { "sentiment": "negative", "aspects": ["품질", "고객서비스"], "score": 0.1 }

이제 다음 리뷰를 분석하세요:`;
```

## 5. 프롬프트 변수 처리

### 템플릿 엔진

```typescript
class PromptTemplate {
  private template: string;

  constructor(template: string) {
    this.template = template;
  }

  // 단순 변수 치환
  format(variables: Record<string, string>): string {
    let result = this.template;
    for (const [key, value] of Object.entries(variables)) {
      result = result.replaceAll(`{${key}}`, value);
    }
    return result;
  }

  // 조건부 섹션 처리
  formatWithConditions(variables: Record<string, any>): string {
    let result = this.template;

    // 변수 치환
    for (const [key, value] of Object.entries(variables)) {
      if (typeof value === 'string') {
        result = result.replaceAll(`{${key}}`, value);
      }
    }

    // 조건부 블록: {{#if key}}...{{/if}}
    result = result.replace(/\{\{#if (\w+)\}\}([\s\S]*?)\{\{\/if\}\}/g, (_, key, content) => {
      return variables[key] ? content : '';
    });

    return result;
  }
}

// 사용 예시
const template = new PromptTemplate(`당신은 {role}입니다.

## 참고 문서
{context}

{{#if history}}
## 이전 대화
{history}
{{/if}}

## 질문
{question}`);

const prompt = template.formatWithConditions({
  role: '기술 문서 어시스턴트',
  context: docs.join('\n'),
  history: chatHistory.length > 0 ? chatHistory.join('\n') : '',
  question: userQuestion,
});
```

## 6. 프롬프트 버전 관리

```typescript
interface PromptVersion {
  id: string;
  version: string;
  template: string;
  variables: string[];
  createdAt: Date;
  metrics?: { accuracy: number; latency: number };
}

class PromptRegistry {
  private prompts = new Map<string, PromptVersion[]>();

  register(name: string, version: PromptVersion): void {
    const versions = this.prompts.get(name) ?? [];
    versions.push(version);
    this.prompts.set(name, versions);
  }

  // 최신 버전 가져오기
  getLatest(name: string): PromptVersion | undefined {
    const versions = this.prompts.get(name);
    return versions?.[versions.length - 1];
  }

  // 특정 버전 가져오기
  getVersion(name: string, version: string): PromptVersion | undefined {
    return this.prompts.get(name)?.find(v => v.version === version);
  }

  // A/B 테스트: 비율에 따라 버전 선택
  getABVersion(name: string, ratio: number = 0.5): PromptVersion | undefined {
    const versions = this.prompts.get(name);
    if (!versions || versions.length < 2) return versions?.[0];
    return Math.random() < ratio ? versions[versions.length - 1] : versions[versions.length - 2];
  }
}
```

## 7. 안티패턴

| 안티패턴 | 문제 | 개선 |
|---------|------|------|
| 모호한 역할 | "잘 답해줘" → 일관성 없는 응답 | 구체적 역할과 제약 조건 명시 |
| 규칙 과다 | 20개 이상의 규칙 → 무시/충돌 | 핵심 5~7개로 축소 |
| 예시 없음 | 기대 형식 불분명 → 형식 불일치 | 1~3개 few-shot 예시 |
| 네거티브만 | "~하지 마"만 나열 → 해야 할 것 불분명 | 긍정 규칙 + 금지 사항 병행 |
| 하드코딩 | 변수 없이 고정 텍스트 → 재사용 불가 | 템플릿 변수 활용 |
