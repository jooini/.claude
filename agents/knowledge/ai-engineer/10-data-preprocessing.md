# Data Preprocessing

> 참조 링크: https://python.langchain.com/docs/concepts/text_splitters/, https://unstructured.io/docs

---

## 1. 전처리 파이프라인 개요

```
원본 데이터 (PDF, HTML, 마크다운, DB)
  ↓
1. 추출 (Extract) — 텍스트 추출
  ↓
2. 정제 (Clean) — 노이즈 제거
  ↓
3. 정규화 (Normalize) — 일관된 형식
  ↓
4. 메타데이터 추출 — 구조화된 속성
  ↓
5. 청킹 — 임베딩 가능한 크기로 분할
  ↓
6. 임베딩 — 벡터 변환
```

## 2. 텍스트 추출

### PDF

```python
# PyMuPDF (빠르고 정확)
import fitz

def extract_pdf(path: str) -> list[dict]:
    doc = fitz.open(path)
    pages = []
    for i, page in enumerate(doc):
        pages.append({
            'content': page.get_text(),
            'page': i + 1,
            'metadata': doc.metadata,
        })
    return pages

# Unstructured (구조 인식)
from unstructured.partition.pdf import partition_pdf

elements = partition_pdf("document.pdf", strategy="hi_res")
for el in elements:
    print(el.category, el.text)  # Title, NarrativeText, Table 등
```

### HTML

```typescript
import * as cheerio from 'cheerio';

function extractHtml(html: string): string {
  const $ = cheerio.load(html);
  // 불필요 요소 제거
  $('script, style, nav, footer, header, aside').remove();
  // 본문 텍스트 추출
  return $('body').text().replace(/\s+/g, ' ').trim();
}

// 마크다운 변환 (구조 보존)
import TurndownService from 'turndown';
const turndown = new TurndownService();
const markdown = turndown.turndown(html);
```

### 데이터베이스

```typescript
// DB 레코드를 텍스트로 변환
function recordToText(record: Record<string, any>, template: string): string {
  return template.replace(/\{(\w+)\}/g, (_, key) => record[key] ?? '');
}

// 예: "제목: {title}\n내용: {content}\n카테고리: {category}"
const text = recordToText(article, '제목: {title}\n내용: {content}\n카테고리: {category}');
```

## 3. 텍스트 정제

### 공통 정제 규칙

```typescript
function cleanText(text: string): string {
  return text
    .replace(/\r\n/g, '\n')                    // 줄바꿈 통일
    .replace(/\n{3,}/g, '\n\n')                // 과도한 빈 줄 제거
    .replace(/\t/g, ' ')                        // 탭 → 공백
    .replace(/ {2,}/g, ' ')                     // 연속 공백 제거
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, '') // 제어 문자 제거
    .replace(/\u200B/g, '')                     // zero-width space 제거
    .replace(/\uFEFF/g, '')                     // BOM 제거
    .trim();
}
```

### HTML 특화 정제

```typescript
function cleanHtmlText(text: string): string {
  return text
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/<!--[\s\S]*?-->/g, '')  // HTML 주석
    .replace(/<[^>]+>/g, '');          // 남은 태그
}
```

### 코드 정제

```typescript
function cleanCode(code: string): string {
  return code
    .replace(/\/\/.*$/gm, '')          // 단일 행 주석 (선택적)
    .replace(/\/\*[\s\S]*?\*\//g, '') // 블록 주석 (선택적)
    .replace(/^\s*\n/gm, '');          // 빈 줄 제거
}
// 주의: 주석에 중요한 정보가 있을 수 있으므로 용도에 따라 판단
```

## 4. 텍스트 정규화

```typescript
// 유니코드 정규화 (NFC 권장)
function normalize(text: string): string {
  return text.normalize('NFC');
}

// 한국어 특화
function normalizeKorean(text: string): string {
  return text
    .normalize('NFC')
    .replace(/ㄱ-ㅎㅏ-ㅣ/g, '')  // 단독 자모 제거 (필요 시)
    .replace(/[！？。，]/g, m => {   // 전각 문장부호 → 반각
      const map: Record<string, string> = { '！': '!', '？': '?', '。': '.', '，': ',' };
      return map[m] || m;
    });
}
```

## 5. 메타데이터 추출

```typescript
interface DocumentMetadata {
  source: string;         // 원본 파일/URL
  title?: string;         // 문서 제목
  author?: string;        // 작성자
  createdAt?: string;     // 생성일
  updatedAt?: string;     // 수정일
  language?: string;      // 언어
  category?: string;      // 카테고리
  tags?: string[];        // 태그
  pageCount?: number;     // 페이지 수
  wordCount?: number;     // 단어 수
  fileType: string;       // pdf, html, md, csv
}

function extractMetadata(content: string, source: string): DocumentMetadata {
  return {
    source,
    fileType: source.split('.').pop() || 'unknown',
    wordCount: content.split(/\s+/).length,
    language: detectLanguage(content),
  };
}
```

### 마크다운 frontmatter 파싱

```typescript
import matter from 'gray-matter';

const { data, content } = matter(markdownText);
// data: { title: '...', date: '...', tags: [...] }
// content: frontmatter 제외한 본문
```

## 6. 토큰 카운팅

```typescript
// tiktoken (OpenAI 모델용)
import { encoding_for_model } from 'tiktoken';

const enc = encoding_for_model('gpt-4');

function countTokens(text: string): number {
  return enc.encode(text).length;
}

function truncateToTokens(text: string, maxTokens: number): string {
  const tokens = enc.encode(text);
  if (tokens.length <= maxTokens) return text;
  return enc.decode(tokens.slice(0, maxTokens));
}
```

```python
# Python
import tiktoken

enc = tiktoken.encoding_for_model("gpt-4")

def count_tokens(text: str) -> int:
    return len(enc.encode(text))
```

## 7. 중복 제거

```typescript
// 정확히 동일한 청크 제거
function deduplicateExact(chunks: string[]): string[] {
  return [...new Set(chunks)];
}

// 유사 중복 제거 (MinHash)
function deduplicateNear(chunks: string[], threshold: number = 0.85): string[] {
  // SimHash 또는 MinHash로 유사도 계산
  // threshold 이상 유사한 청크 중 하나만 유지
  const result: string[] = [];
  for (const chunk of chunks) {
    const isDuplicate = result.some(r => jaccardSimilarity(r, chunk) > threshold);
    if (!isDuplicate) result.push(chunk);
  }
  return result;
}
```

## 8. 전처리 품질 검증

```typescript
// 전처리 결과 검증 체크리스트
function validateChunk(chunk: string): { valid: boolean; issues: string[] } {
  const issues: string[] = [];

  if (chunk.length < 50) issues.push('너무 짧음 (< 50자)');
  if (chunk.length > 5000) issues.push('너무 김 (> 5000자)');
  if (/^[\s\n]*$/.test(chunk)) issues.push('빈 청크');
  if (/[^\x20-\x7E\xA0-\xFF\u3000-\u9FFF\uAC00-\uD7AF]/.test(chunk)) {
    issues.push('비정상 문자 포함');
  }
  if (countTokens(chunk) > 512) issues.push('토큰 제한 초과');

  return { valid: issues.length === 0, issues };
}
```
