# Chunking Strategies

> 참조 링크: https://docs.llamaindex.ai/en/stable/module_guides/loading/node_parsers/, https://python.langchain.com/docs/concepts/text_splitters/

---

## 1. 청킹이 중요한 이유

임베딩 모델은 토큰 제한이 있고, 긴 텍스트를 통째로 임베딩하면 의미가 희석된다. 적절한 크기로 분할해야 검색 정확도가 올라간다.

## 2. 청킹 전략

### Fixed-size Chunking

고정 크기(문자 수 또는 토큰 수)로 분할한다.

```typescript
function fixedSizeChunk(text: string, chunkSize: number, overlap: number): string[] {
  const chunks: string[] = [];
  let start = 0;
  while (start < text.length) {
    chunks.push(text.slice(start, start + chunkSize));
    start += chunkSize - overlap;
  }
  return chunks;
}

// 사용
const chunks = fixedSizeChunk(document, 500, 50); // 500자, 50자 오버랩
```

| 장점 | 단점 |
|------|------|
| 구현 간단 | 문장/문단 중간에서 잘림 |
| 예측 가능한 크기 | 의미 단위 무시 |

### Recursive Character Splitting

구분자를 계층적으로 적용하여 분할한다. LangChain의 기본 전략이다.

```typescript
// 구분자 우선순위: 문단 > 문장 > 단어
const separators = ['\n\n', '\n', '. ', ' ', ''];

function recursiveSplit(text: string, maxSize: number, separators: string[]): string[] {
  const [sep, ...restSeps] = separators;
  const parts = text.split(sep);
  const chunks: string[] = [];
  let current = '';

  for (const part of parts) {
    if ((current + sep + part).length > maxSize) {
      if (current) chunks.push(current.trim());
      if (part.length > maxSize && restSeps.length > 0) {
        chunks.push(...recursiveSplit(part, maxSize, restSeps));
        current = '';
      } else {
        current = part;
      }
    } else {
      current = current ? current + sep + part : part;
    }
  }
  if (current) chunks.push(current.trim());
  return chunks;
}
```

| 장점 | 단점 |
|------|------|
| 자연스러운 분할 경계 | 청크 크기 불균일 |
| 의미 단위 보존 | 구분자 선택 필요 |

### Semantic Chunking

문장 간 의미 유사도를 계산하여, 유사도가 급격히 떨어지는 지점에서 분할한다.

```typescript
async function semanticChunk(sentences: string[], threshold: number = 0.5): Promise<string[][]> {
  const embeddings = await embedBatch(sentences);
  const chunks: string[][] = [];
  let currentChunk: string[] = [sentences[0]];

  for (let i = 1; i < sentences.length; i++) {
    const similarity = cosineSimilarity(embeddings[i - 1], embeddings[i]);
    if (similarity < threshold) {
      chunks.push(currentChunk);
      currentChunk = [sentences[i]];
    } else {
      currentChunk.push(sentences[i]);
    }
  }
  if (currentChunk.length) chunks.push(currentChunk);
  return chunks;
}
```

| 장점 | 단점 |
|------|------|
| 의미 기반 최적 분할 | 임베딩 비용 추가 |
| 검색 품질 최고 | 처리 시간 김 |

### Document-structure Chunking

마크다운 헤딩, HTML 태그, 코드 블록 등 문서 구조를 기반으로 분할한다.

```typescript
function markdownChunk(markdown: string): { content: string; metadata: { heading: string } }[] {
  const sections = markdown.split(/(?=^#{1,3}\s)/m);
  return sections.filter(s => s.trim()).map(section => {
    const headingMatch = section.match(/^(#{1,3})\s(.+)/);
    return {
      content: section.trim(),
      metadata: { heading: headingMatch?.[2] || '' },
    };
  });
}
```

## 3. 오버랩 (Overlap)

청크 경계에서 정보가 유실되는 것을 방지한다.

```
청크1: [........|overlap|]
청크2:          [overlap|........|overlap|]
청크3:                   [overlap|........]
```

### 권장 오버랩 크기

| 청크 크기 | 오버랩 | 비율 |
|----------|--------|------|
| 256 토큰 | 25-50 | 10-20% |
| 512 토큰 | 50-100 | 10-20% |
| 1024 토큰 | 100-200 | 10-20% |

## 4. 청크 크기 가이드

| 용도 | 권장 크기 | 이유 |
|------|---------|------|
| FAQ / Q&A | 128-256 토큰 | 짧고 구체적인 답변 |
| 기술 문서 | 256-512 토큰 | 한 주제 단위 |
| 법률/계약서 | 512-1024 토큰 | 조항 단위 |
| 코드 | 함수 단위 | 논리적 단위 |
| 대화 로그 | 대화 턴 단위 | 맥락 보존 |

## 5. 메타데이터 첨부

청크에 메타데이터를 붙이면 검색 시 필터링이 가능하다.

```typescript
interface Chunk {
  content: string;
  metadata: {
    source: string;        // 원본 파일/URL
    page?: number;         // 페이지 번호
    heading?: string;      // 소속 섹션 제목
    chunkIndex: number;    // 원본 내 순서
    totalChunks: number;   // 원본의 총 청크 수
    createdAt: string;     // 처리 시점
  };
}
```

## 6. 코드 청킹

코드는 일반 텍스트와 다른 전략이 필요하다.

```typescript
// AST 기반 분할 — 함수/클래스 단위
function codeChunk(code: string, language: string): string[] {
  // 1. 파일 → 함수/클래스 단위 분할
  // 2. 큰 함수는 논리 블록(if/for/try) 단위로 추가 분할
  // 3. import 문은 별도 청크 또는 모든 청크에 context로 포함
}
```

### 코드 청킹 규칙

- 함수/메서드를 중간에서 자르지 않는다
- 클래스는 메서드 단위로 분할하되, 클래스명/필드를 컨텍스트로 첨부
- import 문은 각 청크의 메타데이터에 포함
- 주석은 해당 코드와 같은 청크에 포함

## 7. 청킹 파이프라인

```
원본 문서
  ↓
1. 전처리 (HTML 태그 제거, 정규화)
  ↓
2. 문서 구조 파싱 (헤딩, 리스트, 코드 블록)
  ↓
3. 1차 분할 (문서 구조 기반)
  ↓
4. 2차 분할 (크기 초과 시 recursive split)
  ↓
5. 오버랩 적용
  ↓
6. 메타데이터 첨부
  ↓
7. 임베딩
```
