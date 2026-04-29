# CLAUDE.md 작성

> 참조 링크: https://docs.anthropic.com/en/docs/claude-code/memory

---

## CLAUDE.md의 역할

CLAUDE.md는 Claude Code가 세션 시작 시 자동으로 읽는 설정 파일이다. 프로젝트 컨벤션, 코드 스타일, 아키텍처 규칙 등을 정의하여 모든 세션에서 일관된 동작을 보장한다.

## 파일 위치와 스코프

### 3단계 스코프

```
~/.claude/CLAUDE.md          ← 글로벌 (모든 프로젝트 공통)
<project-root>/CLAUDE.md     ← 프로젝트 (해당 프로젝트 전체)
<subdirectory>/CLAUDE.md     ← 디렉토리 (특정 하위 경로)
```

### 스코프별 용도

```markdown
# 글로벌 (~/.claude/CLAUDE.md)
- 개인 코드 스타일 (주석 방식, 변수 명명 등)
- 선호 언어/프레임워크 기본값
- 커뮤니케이션 방식 (서두 금지, 간결함 등)
- 에이전트 시스템 설정

# 프로젝트 (project/CLAUDE.md)
- 기술 스택 정의 (NestJS + TypeORM + MariaDB 등)
- 디렉토리 구조 설명
- 빌드/테스트 명령어
- 프로젝트 고유 컨벤션

# 디렉토리 (project/src/modules/CLAUDE.md)
- 해당 모듈의 아키텍처 패턴
- 모듈 고유 네이밍 규칙
- 관련 파일 간 의존성 설명
```

## 레이어 설계

### 레이어 분리 원칙

글로벌 CLAUDE.md에서 여러 관심사를 레이어로 분리한다.

```markdown
# Layer 1 — 나라는 사람 (모든 툴 공통)
코드 스타일, 커뮤니케이션 방식, 금지 행동 등
→ Claude Code뿐 아니라 API, 웹 등 어디서든 적용

# Layer 2 — Claude Code 전용
에이전트 시스템, MCP 설정, 파이프라인 규칙 등
→ Claude Code 환경에서만 의미 있는 설정
```

### 레이어 분리 기준

```markdown
# 분리해야 하는 경우
- 적용 범위가 다를 때 (전체 vs 특정 도구)
- 변경 빈도가 다를 때 (고정 vs 자주 업데이트)
- 관심사가 다를 때 (코드 스타일 vs 에이전트 시스템)

# 하나로 합쳐도 되는 경우
- 내용이 3줄 이하인 레이어
- 적용 범위가 완전히 동일한 설정
```

## 컨벤션 작성법

### Stack 정의

프로젝트의 기술 스택을 명확히 나열한다.

```markdown
## Stack
- 백엔드: NestJS, TypeORM, MariaDB
- 프론트: React, Next.js
- 언어: TypeScript (strict), Node 20+
- 인프라: Docker, AWS ECS
- CI/CD: GitHub Actions
```

### 코드 스타일 정의

모델이 생성할 코드의 스타일을 지정한다.

```markdown
## 코드 스타일
- 주석은 코드 안에 인라인으로 넣는다
- 함수명: camelCase
- 클래스명: PascalCase
- 파일명: kebab-case
- 상수: UPPER_SNAKE_CASE
- 들여쓰기: 2 spaces
- 세미콜론: 사용
- 따옴표: single quote
```

### 디렉토리 구조 설명

```markdown
## 디렉토리 구조
src/
├── modules/          # 도메인별 모듈 (users, orders, products)
│   └── [module]/
│       ├── dto/      # Request/Response DTO
│       ├── entities/ # TypeORM Entity
│       ├── [module].controller.ts
│       ├── [module].service.ts
│       └── [module].module.ts
├── common/           # 공통 유틸, 데코레이터, 가드
├── config/           # 환경 설정
└── main.ts
```

### 빌드/테스트 명령어

```markdown
## 명령어
- 빌드: `npm run build`
- 테스트: `npm test`
- 린트: `npm run lint`
- 개발 서버: `npm run start:dev`
- DB 마이그레이션: `npm run migration:run`
```

## 에이전트 시스템 설정

### 에이전트 카탈로그

사용 가능한 에이전트를 표로 정리한다.

```markdown
### 에이전트 카탈로그
| 에이전트 | 호출명 | 역할 | 모델 |
|---------|-------|------|------|
| backend-developer | 백엔드 | BE 개발 | opus |
| frontend-developer | 프론트 | FE 개발 | opus |
| code-reviewer | 코드리뷰어 | 코드 리뷰 | sonnet |
| code-tester | 코드테스터 | 테스트 | sonnet |
```

### 에이전트 호출 규칙

```markdown
### 에이전트 호출 규칙
- 에이전트는 Agent 도구로 실행한다
- 사용자가 호출명으로 부르면 해당 에이전트를 실행한다
- 에이전트 세션 유지: agentId를 보관하고 SendMessage로 이어 보낸다
- 에이전트 내부에서 다른 에이전트를 직접 호출하지 않는다
```

## 효과적인 CLAUDE.md 작성 원칙

### 1. 구체적으로 작성

```markdown
# 나쁜 예
깔끔한 코드를 작성해줘

# 좋은 예
- 함수는 20줄 이하로 유지
- 매개변수는 3개 이하
- 중첩은 2단계 이하
- early return 패턴 사용
```

### 2. 검증 가능한 규칙

```markdown
# 나쁜 예
읽기 좋은 변수명을 사용해줘

# 좋은 예
- boolean 변수: is/has/can 접두사 (isActive, hasPermission)
- 배열 변수: 복수형 (users, items)
- 핸들러 함수: handle 접두사 (handleClick, handleSubmit)
```

### 3. 우선순위 명시

```markdown
## 우선순위 (높은 순)
1. 타입 안전성: any 타입 사용 금지
2. 에러 핸들링: try-catch 필수
3. 성능: N+1 쿼리 금지
4. 가독성: 매직 넘버 금지, 상수화
```

### 4. 예외 상황 정의

```markdown
## 기본 규칙
모든 함수에 JSDoc을 작성한다.

## 예외
- private 메서드 중 3줄 이하인 것은 생략 가능
- 테스트 파일에서는 생략
- DTO 클래스의 getter/setter는 생략
```

## CLAUDE.md 안티패턴

### 1. 너무 긴 CLAUDE.md

```markdown
# 문제
500줄 이상의 CLAUDE.md
→ 뒤쪽 규칙이 무시될 가능성 증가

# 해결
- 글로벌/프로젝트/디렉토리로 분산
- 에이전트별 규칙은 에이전트 파일로 분리
- CLAUDE.md는 50~150줄이 적정
```

### 2. 중복 규칙

```markdown
# 문제
글로벌과 프로젝트 CLAUDE.md에 같은 규칙 중복
→ 하나를 수정하면 다른 쪽과 불일치

# 해결
- 공통 규칙은 글로벌에만 작성
- 프로젝트에서는 오버라이드할 것만 작성
```

### 3. 모호한 규칙

```markdown
# 문제
"적절히 에러 핸들링을 해줘"

# 해결
## 에러 핸들링 규칙
- Controller: HttpException 계열만 throw
- Service: 비즈니스 예외는 커스텀 Exception 클래스
- Repository: DB 에러는 catch 후 서비스 레벨 예외로 변환
```

## CLAUDE.md 유지보수

### 업데이트 시점

```markdown
# CLAUDE.md 업데이트가 필요한 시점
- 새 기술 스택 도입 시
- 코드 컨벤션 변경 시
- 디렉토리 구조 변경 시
- 반복적으로 모델이 같은 실수를 할 때
- 에이전트 추가/제거 시
```

### 변경 관리

```markdown
# CLAUDE.md는 코드와 함께 버전 관리한다
- Git에 커밋하여 이력 추적
- PR 리뷰 대상에 포함
- 프로젝트 루트의 CLAUDE.md는 팀원 합의 하에 변경
- 글로벌 CLAUDE.md는 개인 설정이므로 자유롭게 수정
```

### 효과 측정

```markdown
# CLAUDE.md 규칙의 효과 확인 방법
1. 규칙 추가 전후로 동일 요청을 테스트
2. 모델이 규칙을 따르는 비율 확인
3. 따르지 않는 경우 규칙 표현을 강화
4. 여전히 무시되면 위치(상단으로 이동)나 강도 조절
```
