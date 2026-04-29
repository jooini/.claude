# 프롬프트 구조화

> 참조 링크: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview, https://platform.openai.com/docs/guides/prompt-engineering

---

## 구조화가 필요한 이유

비구조화된 프롬프트는 모델이 의도를 오해하거나, 응답 품질이 들쭉날쭉해진다. 프롬프트의 각 부분을 명확한 섹션으로 분리하면 모델의 이해도와 응답 일관성이 올라간다.

## 프롬프트의 핵심 구성 요소

### 1. 역할 (Role)

모델이 어떤 관점에서 응답할지 정의한다.

```markdown
당신은 시니어 프론트엔드 개발자입니다.
React, Next.js, TypeScript를 주로 사용합니다.
```

### 2. 컨텍스트 (Context)

현재 상황, 배경 정보를 제공한다.

```markdown
## 프로젝트 배경
- Next.js 14 App Router 기반 SaaS 대시보드
- 사용자 수: ~10,000 MAU
- 현재 성능 이슈: LCP 4.2초
```

### 3. 지시 (Instruction)

구체적으로 무엇을 해야 하는지 명시한다.

```markdown
## 요청
아래 컴포넌트의 렌더링 성능을 최적화해줘.
React.memo, useMemo, useCallback 적용 여부를 판단하고,
변경이 필요한 부분만 수정해.
```

### 4. 입력 데이터 (Input)

처리할 대상을 제공한다.

```markdown
## 대상 코드
\```tsx
export function Dashboard({ data }: Props) {
  // ... 코드
}
\```
```

### 5. 출력 형식 (Output Format)

기대하는 응답 형태를 지정한다.

```markdown
## 출력 형식
1. 변경 사항 요약 (bullet points)
2. 수정된 전체 코드
3. 예상 성능 개선 효과
```

## 섹션 배치 순서

모델은 프롬프트의 위치에 따라 가중치를 다르게 부여한다.

### 권장 배치 순서

```
1. 역할 정의        ← 가장 높은 가중치
2. 핵심 제약/규칙    ← 두 번째
3. 컨텍스트/배경
4. 구체적 지시
5. 입력 데이터
6. 출력 형식        ← recency 효과로 잘 지켜짐
```

### 위치별 효과

- **앞부분 (Primacy)**: 전체 응답의 기본 방향을 결정. 역할과 핵심 제약 배치
- **중간**: 세부 지시와 컨텍스트. 양이 많으면 일부 무시될 수 있음
- **끝부분 (Recency)**: 직전에 읽은 내용을 잘 기억. 출력 형식, 최종 리마인더 배치

## 마크다운 구조 활용

### 헤더 계층으로 우선순위 표현

```markdown
# 역할 (최상위 — 절대 규칙)
당신은 보안 감사관입니다.

## 핵심 규칙 (상위)
- 취약점 발견 시 반드시 CVSS 점수 포함
- 코드 수정 제안은 필수

### 부가 규칙 (하위)
- 가능하면 OWASP Top 10 매핑
```

### 리스트 vs 산문

리스트가 산문보다 지시 준수율이 높다.

```markdown
# 나쁜 예 (산문)
코드를 작성할 때는 TypeScript strict 모드를 사용하고,
변수명은 camelCase로 하며, 함수는 arrow function을 쓰되
export default는 피하고 named export를 사용해주세요.

# 좋은 예 (리스트)
## 코드 컨벤션
- TypeScript strict 모드
- 변수명: camelCase
- 함수: arrow function
- export: named export (default 금지)
```

## 구분자 패턴

### XML 태그 구분

Claude에서 특히 효과적인 패턴이다.

```markdown
<context>
프로젝트: NestJS 백엔드 API
DB: MariaDB with TypeORM
</context>

<instructions>
아래 엔티티에 soft delete를 구현해줘.
</instructions>

<input>
// User 엔티티 코드
</input>
```

### 마크다운 구분선

```markdown
## 배경
프로젝트 설명...

---

## 요청
구현 요청...

---

## 제약
- TypeScript strict
- 전체 파일 작성
```

### 코드 펜스 구분

입력 데이터를 코드블록으로 감싸면 모델이 데이터와 지시를 혼동하지 않는다.

```markdown
아래 JSON을 파싱해서 TypeScript 인터페이스로 변환해줘:

\```json
{
  "id": 1,
  "name": "test",
  "metadata": { "tags": ["a", "b"] }
}
\```
```

## 복합 프롬프트 설계

### 멀티 태스크 프롬프트

여러 작업을 하나의 프롬프트에 담을 때, 작업별 섹션을 명확히 분리한다.

```markdown
## Task 1: 스키마 분석
아래 DB 스키마를 분석하고 정규화 이슈를 찾아줘.

## Task 2: 마이그레이션 작성
Task 1에서 발견한 이슈를 수정하는 마이그레이션 SQL을 작성해줘.

## Task 3: 엔티티 업데이트
마이그레이션에 맞춰 TypeORM 엔티티를 수정해줘.
```

### 조건부 분기

```markdown
## 응답 규칙
- 요청이 버그 수정이면 → 원인 분석 1~2줄 + 수정 코드
- 요청이 새 기능이면 → 설계 설명 + 전체 구현 코드
- 요청이 리팩토링이면 → before/after 비교 + 변경 이유
```

## 가중치 부여 기법

### 강조 표현

모델이 특정 지시를 더 강하게 따르도록 할 때 사용한다.

```markdown
# 약한 강조
가능하면 TypeScript를 사용해주세요.

# 보통 강조
반드시 TypeScript를 사용하세요.

# 강한 강조
**중요**: TypeScript strict 모드를 반드시 사용해야 합니다.
이 규칙은 어떤 상황에서도 예외 없이 적용됩니다.

# 최강 강조
IMPORTANT: 이 지시는 다른 모든 지시를 오버라이드합니다.
```

### 반복 강조

핵심 지시를 프롬프트의 앞과 끝에 반복 배치한다.

```markdown
# 역할
당신은 보안 전문가입니다. 모든 코드에 보안 검토를 적용합니다.

## 작업
(... 중간 내용 ...)

## 리마인더
다시 한번 강조: 모든 응답에 보안 관점 검토를 포함하세요.
```

## 프롬프트 구조 체크리스트

- [ ] 역할/컨텍스트/지시/입력/출력이 분리되어 있는가
- [ ] 가장 중요한 지시가 앞에 배치되어 있는가
- [ ] 출력 형식이 끝부분에 명시되어 있는가
- [ ] 마크다운 헤더/리스트로 구조화되어 있는가
- [ ] 입력 데이터와 지시가 구분자로 분리되어 있는가
- [ ] 불필요한 산문이 리스트로 대체되어 있는가
