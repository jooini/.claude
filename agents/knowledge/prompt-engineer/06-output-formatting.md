# 출력 형식 제어

> 참조 링크: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags, https://platform.openai.com/docs/guides/structured-outputs

---

## 출력 형식 제어의 중요성

모델의 응답을 후속 시스템이 파싱하거나, 사용자가 일관된 형태로 소비해야 할 때, 출력 형식을 명확히 지정해야 한다. 형식 미지정 시 모델은 매번 다른 구조로 응답한다.

## JSON 출력 유도

### 기본 JSON 출력

```markdown
아래 코드를 분석하고 결과를 JSON으로 출력해줘.

출력 형식:
\```json
{
  "file": "파일 경로",
  "issues": [
    {
      "line": 라인번호,
      "severity": "critical | warning | info",
      "message": "이슈 설명",
      "suggestion": "수정 제안"
    }
  ],
  "summary": "전체 요약"
}
\```
```

### JSON Schema 제공

정확한 타입과 필수 필드를 명시하면 준수율이 높아진다.

```markdown
아래 JSON Schema에 맞춰 출력해줘:

{
  "type": "object",
  "required": ["status", "data"],
  "properties": {
    "status": { "type": "string", "enum": ["success", "error"] },
    "data": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "name", "score"],
        "properties": {
          "id": { "type": "integer" },
          "name": { "type": "string" },
          "score": { "type": "number", "minimum": 0, "maximum": 100 }
        }
      }
    }
  }
}
```

### JSON 출력 안정성 확보

```markdown
## JSON 출력 규칙
- 반드시 유효한 JSON만 출력 (trailing comma 금지)
- 코드블록 없이 raw JSON만 출력
- 설명 텍스트를 JSON 앞뒤에 추가하지 마
- null 대신 빈 문자열("") 또는 빈 배열([]) 사용
```

## 마크다운 출력 유도

### 구조화된 마크다운

```markdown
다음 형식으로 코드 리뷰 결과를 작성해줘:

## 리뷰 요약
(1~2문장 전체 요약)

## 이슈 목록

### [CRITICAL] 이슈 제목
- **파일**: `파일경로:라인번호`
- **설명**: 이슈 내용
- **수정 제안**:
\```typescript
// 수정된 코드
\```

### [WARNING] 이슈 제목
(같은 형식)

## 총평
(최종 판단: approve / request changes)
```

### 마크다운 테이블

```markdown
분석 결과를 아래 테이블 형식으로 출력해줘:

| 항목 | 현재 상태 | 권장 사항 | 우선순위 |
|------|----------|----------|---------|
| 인증 | ... | ... | 상/중/하 |
| DB 쿼리 | ... | ... | 상/중/하 |
```

## 코드 출력 제어

### 전체 파일 출력

```markdown
## 출력 규칙
- 수정된 파일은 전체 내용을 출력
- `// ...동일` 또는 `// 나머지 생략` 처리 금지
- 파일 경로를 코드블록 위에 표시

예시:
`src/user/user.service.ts`
\```typescript
// 전체 파일 내용
\```
```

### 변경 부분만 출력

diff 형식이 필요한 경우:

```markdown
변경 사항을 unified diff 형식으로 출력해줘:

\```diff
--- a/src/user/user.service.ts
+++ b/src/user/user.service.ts
@@ -10,7 +10,9 @@
   async findOne(id: number) {
-    return this.repo.findOne(id);
+    const user = await this.repo.findOne({ where: { id } });
+    if (!user) throw new NotFoundException(`User #${id} not found`);
+    return user;
   }
\```
```

### 다중 파일 출력

```markdown
## 파일 출력 순서
1. 스키마/타입 정의 파일
2. 서비스/비즈니스 로직 파일
3. 컨트롤러/라우트 파일
4. 테스트 파일

각 파일은 다음 형식으로:
---
📄 `파일경로`
\```언어
코드
\```
---
```

## XML 태그 구조화

Claude에서 특히 효과적인 XML 태그 기반 구조화다.

### 응답 섹션 분리

```markdown
응답을 다음 XML 태그로 구분해줘:

<analysis>
코드 분석 내용
</analysis>

<solution>
수정된 코드
</solution>

<testing>
테스트 방법
</testing>
```

### 메타데이터 포함

```markdown
<response>
  <metadata>
    <confidence>high | medium | low</confidence>
    <complexity>O(n) | O(n^2) | ...</complexity>
    <breaking_change>true | false</breaking_change>
  </metadata>
  <code>
    수정된 코드
  </code>
  <explanation>
    변경 이유 (1~2문장)
  </explanation>
</response>
```

## 조건부 형식 분기

### 입력 유형별 출력 형식

```markdown
## 응답 형식 규칙

요청 유형에 따라 출력 형식을 다르게 적용:

1. **버그 리포트** →
   - 원인: (1~2문장)
   - 수정 코드: (전체 파일)
   
2. **새 기능 요청** →
   - 설계: (bullet points)
   - 구현: (전체 파일, 파일별로 분리)
   - 테스트: (테스트 코드)

3. **코드 리뷰** →
   - 이슈 목록: (테이블 형식)
   - 수정 제안: (코드블록)

4. **질문** →
   - 답변: (2~3문장)
   - 코드 예시: (필요 시만)
```

## 출력 길이 제어

### 길이 제한 기법

```markdown
# 명시적 길이 제한
- 요약은 3문장 이내
- 코드 주석은 한 줄로
- 대안은 최대 2개

# 상세도 레벨 지정
상세도: 간결 (코드 위주, 설명 최소화)
상세도: 보통 (코드 + 핵심 설명)
상세도: 상세 (코드 + 상세 설명 + 대안)
```

### 점진적 상세화

```markdown
먼저 한 줄 요약을 제시하고,
그 아래에 상세 분석을 작성해줘.

## TL;DR
(한 줄 요약)

## 상세 분석
(전체 내용)
```

## 형식 준수 강화 기법

### 예시 제공

출력 형식을 설명하는 것보다 예시를 보여주는 것이 더 효과적이다.

```markdown
아래 형식으로 출력해줘:

예시:
---
**함수명**: `calculateTotal`
**복잡도**: O(n)
**이슈**: 배열이 비어있을 때 0 대신 undefined 반환
**수정**:
\```typescript
function calculateTotal(items: number[]): number {
  return items.reduce((sum, item) => sum + item, 0); // 빈 배열 시 0 반환
}
\```
---
```

### 형식 위반 시 지시

```markdown
**중요**: 위 형식을 정확히 따라야 합니다.
- JSON 출력 시 마크다운 코드블록으로 감싸지 마
- 형식 외 추가 텍스트를 출력하지 마
- 모든 필드는 필수 (빈 값이라도 포함)
```

## 출력 형식 체크리스트

- [ ] 기대하는 출력 구조가 명확히 정의되어 있는가
- [ ] 예시가 제공되어 있는가
- [ ] 필수 필드와 선택 필드가 구분되어 있는가
- [ ] 형식 위반 시 행동이 정의되어 있는가
- [ ] 파싱 가능한 형식인가 (후속 시스템 연동 시)
- [ ] 길이 제한이 명시되어 있는가
