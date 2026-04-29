---
name: save-doc
description: 현재 대화에서 생성된 콘텐츠를 Obsidian Vault에 구조화된 마크다운 문서로 저장합니다.
disable-model-invocation: true
allowed-tools: Bash(basename *), Bash(ls *), Read, Write, Glob
---

# save-doc

현재 대화에서 Claude가 작성한 콘텐츠를 Obsidian Vault에 문서로 저장한다.

## 실행 절차

### 1단계: 저장할 콘텐츠 식별

현재 대화에서 가장 최근에 작성한 구조화된 콘텐츠를 찾는다:
- 코드 설명, 아키텍처 분석, 기술 가이드, 설계 문서, 비교 분석 등
- 단순 대화(인사, 확인)는 무시

### 2단계: 프로젝트 및 경로 결정

현재 작업 디렉토리(`basename $(pwd)`)와 콘텐츠 내용에서 자동 추론한다.

**프로젝트 매핑:**

| 디렉토리/키워드 | 프로젝트 폴더 |
|---------------|-------------|
| `identity-hub` | `identity-hub` |
| `identity-keycloak`, keycloak 관련 | `identity-keycloak` |
| `identity-hub-frontend` | `identity-hub-frontend` |
| `maxai-b2c-backend` | `maxai-b2c-backend` |
| SSO, 인증 아키텍처 | `sso-architecture` |
| docker, 인프라 | `maxai-docker` |
| superset | `superset` |
| 프로젝트 무관 | `misc` |

**참고:** `identity-platform-docker`, `keycloak-md5`, `python` 폴더는 `misc/`로 통합됨. 새 문서도 `misc/`에 저장할 것.

**MOC 연결:** fallback, deployment, clustering 관련 문서 작성 시, 해당 MOC 파일에 링크를 추가할 것:
- `Projects/sso-architecture/MOC-sso-fallback.md`
- `Projects/sso-architecture/MOC-sso-deployment.md`
- `Projects/sso-architecture/MOC-keycloak-clustering.md`

**문서 유형:**

| 유형 | 경로 | 판단 기준 |
|------|------|----------|
| 프로젝트 문서 (기본) | `Projects/{프로젝트}/YYYY-MM/YYYY-MM-DD-{파일명}.md` | 특정 프로젝트 관련 |
| 설계/계획 | `Plans/YYYY-MM/YYYY-MM-DD-{파일명}.md` | 설계, 계획, 의사결정 |
| 일반 문서 | `Projects/misc/YYYY-MM/YYYY-MM-DD-{파일명}.md` | 프로젝트 무관, 최후 수단 |

판단이 어려우면 AskUserQuestion으로 확인. **misc는 최후 수단** — 프로젝트 폴더에 넣을 수 있으면 넣는다.

**기본 경로:** `~/Workspace/weaversbrain/weaversbrain/`

### 3단계: 파일명 및 태그 결정

**파일명:**
1. 인자로 지정되었으면 그대로 사용
2. 없으면 콘텐츠 제목/주제에서 자동 생성 (공백 → 하이픈, 한글/영문 허용)
3. 월 폴더(`YYYY-MM/`)가 없으면 생성
4. 동일 파일 존재 시 `-2`, `-3` 증번

**태그 생성** — 콘텐츠 내용에서 관련 태그 선택:

| 카테고리 | 태그 |
|---------|------|
| 주제 | api, auth, database, docker, infra, frontend, backend |
| 활동 | debugging, deployment, migration, review, testing, integration |
| 성격 | architecture, guide, performance, security, fallback |
| 도구 | keycloak, sdk, nginx, terraform |

- 최소 2개, 최대 6개
- 내용과 무관한 태그는 넣지 않는다

### 4단계: 문서 작성 및 저장

```markdown
---
date: "YYYY-MM-DD"
type: document | plan | guide | analysis
project: {프로젝트명}
topic: {주제 한 줄 요약}
tags: [{태그1}, {태그2}]
---

{콘텐츠 — 대화 맥락 제거, 문서 형태로 정리}
{코드 블록, 표, 구조는 보존}
```

### 5단계: 저장 확인

```
저장 완료: ~/Workspace/weaversbrain/weaversbrain/Projects/{프로젝트명}/YYYY-MM/YYYY-MM-DD-{파일명}.md
태그: [api, auth, guide]
```

## 주의사항

- 대화에서 실제로 작성된 콘텐츠만 저장. 새로 만들지 않는다.
- 민감 정보 (토큰, 비밀번호, API 키) 마스킹.
- frontmatter 필드에 따옴표 사용하지 않는다 (date 제외).
- **misc에 저장하기 전에 한 번 더 생각한다** — 정말 프로젝트 폴더에 안 맞는지.
