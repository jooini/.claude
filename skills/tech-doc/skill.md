---
name: tech-doc
description: 이슈 분석 + 기술 설계 문서를 Obsidian Vault에 작성/업데이트합니다.
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Write, Bash(basename *), Bash(ls *), Bash(date *)
---

# tech-doc

이슈의 전체 라이프사이클을 기술 문서로 작성한다.

- **이슈 착수 시:** 분석 문서 (Context, Problem, Root Cause)
- **이슈 해결 후:** 완성 문서 (Approach, Result, Future Improvements 추가)

단순한 문제 해결 설명이 아니라 **엔지니어링 의사결정 과정**을 보여주는 문서.

## 작성 원칙

- 시스템 관점에서 설명
- Root Cause 분석 필수
- 여러 해결 방법 비교는 **실제로 검토한 경우에만** 작성 (억지 Trade-offs 금지)
- 선택한 방법의 이유를 명확히 설명
- 결과와 시스템 영향(Impact) 포함
- 기술적 근거 포함 (가능한 경우)
- 불필요한 마케팅 표현 / 수식어 금지
- 논리적, 객관적 서술

## 문서 구조

내용이 없는 섹션은 생략한다.

```
## 1. Context
- 시스템 배경, 현재 구조/동작 방식

## 2. Problem
- 발생한 문제, 발생 조건, 시스템 영향

## 3. Root Cause
- 근본 원인 분석

## 4. Approach
- 해결 전략, 구조 변경, 주요 구현 아이디어
- Before / After 비교 (필요 시)

## 5. Trade-offs (대안을 실제로 검토한 경우에만)
- 고려한 대안, 각 장단점, 선택 이유

## 6. Result
- 해결 결과, 안정성 개선, 사용자 영향

## 7. Future Improvements
- 향후 개선 가능성, 추가 고려 사항
```

## 실행 절차

### 1단계: 프로젝트 및 기존 문서 탐색

현재 작업 디렉토리(`basename $(pwd)`)에서 프로젝트를 추론한다.

**프로젝트 매핑:**

| 디렉토리/키워드 | 프로젝트 폴더 |
|---------------|-------------|
| `identity-hub` | `identity-hub` |
| `identity-keycloak`, keycloak 관련 | `identity-keycloak` |
| `identity-hub-frontend` | `identity-hub-frontend` |
| `maxai-b2c-backend` | `maxai-b2c-backend` |
| `speakingmax-backend` | `speakingmax-backend` |
| `speech-hub` | `speech-hub` |
| `maxai-stt-engine` | `maxai-stt-engine` |
| SSO, 인증 아키텍처 | `sso-architecture` |
| docker, 인프라 | `maxai-docker` |
| 프로젝트 무관 | `misc` |

기존 문서 탐색:
```
Glob: ~/Workspace/weaversbrain/weaversbrain/Projects/{project}/YYYY-MM/*tech-doc*
Glob: ~/Workspace/weaversbrain/weaversbrain/Projects/{project}/YYYY-MM/*{이슈키워드}*
```

- 기존 tech-doc 파일이 있으면 → **업데이트** (새로 만들지 않음)
- 없으면 → 새로 생성

### 2단계: 이슈 분석

`$ARGUMENTS`에서 이슈 내용을 파악한다.

- 브랜치명, 에러 메시지, 이슈 설명 등에서 맥락 추출
- 필요 시 코드베이스 탐색 (Grep, Glob, Read)
- git log/diff로 관련 변경사항 확인

### 3단계: 문서 작성

**착수 단계** (해결 전):
- Context, Problem, Root Cause 작성
- Approach는 가설만 작성하거나 비워둠

**완성 단계** (해결 후):
- 기존 문서를 Read → Approach, Result, Future Improvements 추가/업데이트
- Trade-offs는 실제 대안 검토 시에만

### 4단계: 파일명 및 경로 결정

**기본 경로:** `~/Workspace/weaversbrain/weaversbrain/`

**저장 경로:** `Projects/{project}/YYYY-MM/YYYY-MM-DD-HHMM-{파일명}.md`

- `YYYY-MM-DD-HHMM`: 현재 시각 (`date +"%Y-%m-%d-%H%M"`)
- `{파일명}`: 이슈 주제에서 생성 (공백 → 하이픈, 한글/영문 허용)
- 기존 문서 업데이트 시 파일명 유지, frontmatter `updated` 갱신
- 월 폴더(`YYYY-MM/`)가 없으면 생성

**태그 선택** (최소 2개, 최대 6개):

| 카테고리 | 태그 |
|---------|------|
| 주제 | api, auth, database, docker, infra, frontend, backend, sso |
| 활동 | debugging, deployment, migration, review, testing, integration |
| 성격 | architecture, guide, performance, security, fallback, tech-doc |
| 도구 | keycloak, redis, nginx, terraform, fastapi |

### 5단계: frontmatter 및 저장

```markdown
---
date: "YYYY-MM-DD"
updated: "YYYY-MM-DD"
type: tech-doc
project: {프로젝트명}
topic: {주제 한 줄 요약}
status: in-progress | resolved
branch: "feature/branch-name"
tags: [{태그들}]
---

# {문서 제목}

{본문}
```

- `status: in-progress` → 착수 단계
- `status: resolved` → 해결 완료
- 업데이트 시 `updated` 날짜 갱신

### 6단계: 저장 확인

obsidian:// URI로 출력:

```
저장 완료: obsidian://open?vault=weaversbrain&file={URL인코딩된 경로(확장자 제외)}
프로젝트: {project} | 상태: {status} | 태그: [{tags}]
```

## 주의사항

- 한국어 작성, 코드/기술 용어는 영어 유지
- 민감 정보 (토큰, 비밀번호, API 키) 마스킹
- frontmatter `date` 필드만 따옴표, 나머지는 따옴표 없음
- misc는 최후 수단 — 프로젝트 폴더에 넣을 수 있으면 넣는다
- 파일 상단에 수정이력 주석 금지

## 입력

$ARGUMENTS

위 내용과 프로젝트 내 관련 코드/문서를 참고하여 기술 문서를 작성/업데이트하세요.
