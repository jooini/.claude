# 도구 사용 프롬프팅

> 참조 링크: https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/overview, https://docs.anthropic.com/en/docs/agents-and-tools/mcp

---

## 도구 사용의 핵심

LLM이 외부 도구를 호출하려면 프롬프트가 도구의 존재, 용도, 호출 시점, 파라미터를 명확히 안내해야 한다. 잘못된 도구 프롬프팅은 불필요한 호출, 잘못된 파라미터, 도구 미사용으로 이어진다.

## Function Calling 프롬프팅

### 도구 설명 작성 원칙

도구의 description이 모델의 도구 선택을 결정한다.

```markdown
# 나쁜 도구 설명
name: search
description: "검색합니다"
→ 어떤 검색인지, 언제 사용하는지 불명확

# 좋은 도구 설명
name: search_codebase
description: "코드베이스에서 파일 내용을 정규식 패턴으로 검색합니다.
파일명이 아닌 코드 내용(함수명, 변수명, 문자열 등)을 찾을 때 사용합니다.
파일명/경로로 찾으려면 glob 도구를 사용하세요."
```

### 파라미터 설명

```markdown
# 나쁨 — 파라미터 목적 불명확
parameters:
  query:
    type: string
    description: "검색어"

# 좋음 — 용법과 예시 포함
parameters:
  query:
    type: string
    description: "검색할 정규식 패턴. 예: 'async function \\w+Service',
    'import.*from.*typeorm'. 리터럴 문자열은 이스케이프 불필요."
  path:
    type: string
    description: "검색 시작 디렉토리. 기본값은 프로젝트 루트.
    특정 모듈만 검색하려면 'src/modules/users' 형태로 지정."
```

### 도구 간 관계 명시

```markdown
# 도구 카탈로그에서 관계 설명
## 검색 도구 관계
- Glob: 파일 경로/이름으로 검색. "*.service.ts" 패턴 지원.
  → 파일 위치 모를 때 먼저 사용
- Grep: 파일 내용으로 검색. 정규식 지원.
  → 코드 내 특정 문자열/패턴 찾을 때
- Read: 특정 파일 읽기. 경로를 이미 알 때.
  → Glob/Grep으로 파일을 찾은 후 상세 확인
- RAG: 의미 기반 검색. 자연어 쿼리 지원.
  → 개념/주제로 관련 문서 찾을 때

사용 순서: 파일 위치 모름 → Glob → Read
          코드 내용 검색 → Grep → Read
          개념 검색 → RAG → Read
```

## MCP 호출 유도

### MCP 도구 프롬프팅

MCP(Model Context Protocol) 서버의 도구를 호출하도록 유도하는 방법.

```markdown
# MCP 도구 사용 지시
## MCP 서버: local-rag
도구: mcp__local-rag__query_documents
용도: knowledge 파일들을 벡터 검색
사용 시점: 도메인 지식이 필요할 때

호출 예시:
- "NestJS Guard 구현 방법" → query_documents("NestJS Guard 인증 가드")
- "TypeORM 관계 설정" → query_documents("TypeORM relation 엔티티 관계")
```

### MCP 도구 선택 기준 설계

```markdown
# 프롬프트에서 MCP 도구 선택 기준 정의
검색 도구 선택은 목적에 따른다:
- 디렉토리 구조/파일 목록 파악 → Glob, ls
- 코드/문서 내용 검색 (의미 기반) → RAG → Grep → Glob → Read 순서
- 특정 파일 내용 읽기 → Read 직접 사용
- 외부 라이브러리 문서 → context7 MCP 서버
```

## 도구 선택 기준 설계

### 의사결정 트리

에이전트가 여러 도구 중 올바른 것을 선택하도록 의사결정 트리를 제공한다.

```markdown
## 도구 선택 의사결정 트리

작업 유형은?
├── 정보 탐색
│   ├── 파일 위치 모름 → Glob
│   ├── 코드 내용 검색 → Grep
│   ├── 개념/주제 검색 → RAG
│   └── 파일 경로 알고 있음 → Read
├── 코드 수정
│   ├── 기존 파일 일부 수정 → Read → Edit
│   ├── 새 파일 생성 → Write
│   └── 파일 전체 재작성 → Read → Write
├── 실행/검증
│   ├── 빌드 확인 → Bash: npm run build
│   ├── 테스트 실행 → Bash: npm test
│   └── 파일 시스템 조회 → Bash: ls
└── 외부 도구
    ├── 문서 조회 → context7
    ├── 지식 검색 → local-rag
    └── 웹 검색 → WebSearch
```

### 조건부 도구 사용 규칙

```markdown
## 도구 사용 조건
- Edit 전에 반드시 Read (현재 파일 내용 확인)
- Write 전에 기존 파일이면 반드시 Read
- Bash로 파일 수정 금지 (sed, awk 대신 Edit 사용)
- Grep 결과 없으면 다른 키워드로 재시도, 그래도 없으면 Glob
- 3회 연속 도구 실패 시 사용자에게 보고
```

## 도구 호출 순서 패턴

### 탐색-확인-실행 패턴

```markdown
# 코드 수정 작업의 표준 순서
1. 탐색: Grep/Glob으로 관련 파일 찾기
2. 확인: Read로 현재 코드 확인
3. 실행: Edit/Write로 수정 적용
4. 검증: Bash로 빌드/테스트 실행
5. 재시도: 실패 시 2~4 반복
```

### 병렬 도구 호출

독립적인 도구 호출은 병렬로 실행하여 효율을 높인다.

```markdown
# 병렬 가능한 경우
- 여러 파일을 동시에 Read
- 서로 다른 패턴으로 동시에 Grep
- 독립적인 Bash 명령 동시 실행

# 병렬 불가 — 순차 필수
- Read 후 Edit (Read 결과로 old_string 결정)
- Edit 후 Bash (수정이 반영된 후 빌드)
- Grep 후 Read (검색 결과로 파일 경로 결정)
```

## 도구 실패 처리 프롬프팅

### 실패 시 행동 지시

```markdown
## 도구 실패 대응 규칙

Edit 실패 (old_string 불일치):
→ Read로 현재 파일 내용 재확인
→ old_string을 정확히 복사하여 재시도
→ 2회 실패 시 더 큰 컨텍스트로 old_string 확장

Bash 실패 (빌드/테스트 에러):
→ 에러 메시지를 분석
→ 관련 코드를 Read로 확인
→ Edit으로 수정 후 재실행

Grep 결과 없음:
→ 패턴을 더 일반적으로 변경 (정규식 완화)
→ 다른 키워드로 재검색
→ Glob으로 파일 구조 확인 후 직접 Read

Read 실패 (파일 없음):
→ Glob으로 유사한 파일 검색
→ 경로 오타 확인
→ 사용자에게 정확한 경로 확인 요청
```

### 에스컬레이션 규칙

```markdown
## 도구 에스컬레이션
동일 도구 3회 연속 실패 시:
1. 시도한 내용과 에러 메시지를 정리
2. 다른 접근 방식을 시도
3. 그래도 실패하면 사용자에게 상황 보고

보고 형식:
"[도구명]이 반복 실패했습니다.
시도: [시도한 내용]
에러: [에러 메시지]
가능한 원인: [추정 원인]
필요한 조치: [사용자에게 요청할 것]"
```

## 도구 사용 안티패턴

### 1. 불필요한 도구 호출

```markdown
# 나쁜 예
이미 대화에서 파일 내용을 확인했는데 다시 Read
→ 컨텍스트에 있는 정보를 활용

# 예외
파일이 Edit으로 수정된 후에는 최신 상태 확인을 위해 Read 허용
```

### 2. 과도한 탐색

```markdown
# 나쁜 예
프로젝트 전체를 Glob/Grep으로 스캔한 후 작업 시작
→ 필요한 범위만 탐색

# 좋은 예
사용자가 지정한 파일/모듈만 확인
관련 파일은 import/dependency 추적으로 최소 범위 탐색
```

### 3. 도구 결과 무시

```markdown
# 나쁜 예
Grep으로 검색했지만 결과를 활용하지 않고 추측으로 코드 작성
→ 도구 결과를 반드시 반영

# 좋은 예
Grep 결과에서 기존 패턴을 확인하고, 동일 패턴으로 새 코드 작성
```

## 도구 프롬프팅 체크리스트

```markdown
□ 각 도구의 용도와 사용 시점이 명시되어 있는가?
□ 도구 간 선택 기준이 의사결정 트리로 제공되는가?
□ 파라미터 설명에 예시가 포함되어 있는가?
□ 도구 호출 순서(순차/병렬)가 정의되어 있는가?
□ 실패 시 대응 방법이 도구별로 정의되어 있는가?
□ 에스컬레이션 기준과 형식이 정의되어 있는가?
□ 불필요한 도구 호출을 금지하는 규칙이 있는가?
```
