---
name: docs-update
description: SSO 프로젝트 통합 문서를 최신 코드 기반으로 갱신
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(find *), Read, Write, Edit, Glob, Grep
---

# docs-update 스킬

SSO 프로젝트 통합 문서(DOCS_INTEGRATED.md)와 서브 문서를 최신 코드 기반으로 갱신한다.

## 실행 흐름

### 1단계: 설정 파일 읽기

`~/.claude/docs-config.yaml`을 읽어 프로젝트 목록, 경로, 브랜치, 서브 문서 파일명을 확인한다.

### 2단계: 변경 감지

각 프로젝트의 현재 git commit hash를 수집한다:

```bash
cd {project.path} && git rev-parse HEAD
```

기존 `DOCS_INTEGRATED.md`의 YAML frontmatter에서 `commits` 메타데이터를 파싱하여 비교한다.

- 커밋 해시가 동일한 프로젝트는 **스킵**
- 커밋 해시가 다른 프로젝트만 **재생성 대상**

### 3단계: 서브 문서 재생성 (에이전트 병렬)

변경된 프로젝트마다 에이전트를 병렬로 생성하여 서브 문서를 재생성한다.

각 에이전트에게 전달할 프롬프트:

```
{project.name} 프로젝트의 서브 문서를 재생성하라.

코드/문서 검색 시 반드시 mcp__local-rag__query_documents를 1순위로 사용하라.
RAG 검색 → Grep → Glob → Read 순서를 지켜라.
RAG 없이 바로 Grep/Glob/Read로 시작하지 마라.

프로젝트 경로: {project.path}
브랜치: {project.branch}
기술 스택: {project.tech}
CLAUDE.md: {project.claude_md}
출력 파일: {output_dir}/{project.doc_file}

기존 서브 문서의 구조와 형식을 유지하되, 코드 변경사항을 반영하라.
YAML frontmatter의 commit을 현재 HEAD로 갱신하라.
```

### 4단계: 운영 문서 변경 감지

`operations.sources` 경로의 파일 변경을 감지한다:

```bash
cd {source_dir} && find . -name "*.md" -newer {output_dir}/DOCS_operations.md
```

변경된 소스 파일이 있으면 DOCS_operations.md를 재생성한다.

### 5단계: 허브 문서 메타데이터 갱신

`DOCS_INTEGRATED.md`의 YAML frontmatter를 갱신한다:

- `last_updated`: 현재 날짜 (YYYY-MM-DD)
- `commits`: 각 프로젝트의 최신 commit hash

Edit 도구로 frontmatter 부분만 수정한다.

### 6단계: Mermaid 다이어그램 재생성 판단

Mermaid 다이어그램은 아키텍처 변경이 있을 때만 재생성한다. 아키텍처 변경의 기준:

- 새 서비스/컴포넌트 추가 또는 제거
- 서비스 간 통신 방식 변경 (HTTP → gRPC 등)
- 새 외부 의존성 추가 (새 DB, 새 IDP 등)
- 인프라 구성 변경 (EC2 추가, RDS 변경 등)

단순 코드 수정, 버그 수정, 엔드포인트 추가 등은 다이어그램 재생성 불필요.

## 변경 없음 시 동작

모든 프로젝트의 커밋 해시가 동일하고, 운영 문서 소스에도 변경이 없으면:

```
모든 문서가 최신 상태입니다. 갱신이 필요하지 않습니다.
```

메시지를 출력하고 종료한다.

## 설정 파일 형식 (docs-config.yaml)

```yaml
output_dir: ~/Workspace/weaversbrain/weaversbrain/Projects/sso-architecture
hub_file: DOCS_INTEGRATED.md

projects:
  - name: identity-hub
    path: ~/Workspace/identity-hub
    branch: develop
    tech: "FastAPI + Python 3.11"
    doc_file: DOCS_identity-hub.md
    claude_md: ~/.claude/identity-hub/CLAUDE.md

operations:
  doc_file: DOCS_operations.md
  sources:
    - ~/Workspace/weaversbrain/weaversbrain/Projects/sso-architecture/
```

## 주의사항

- 서브에이전트 실행 시 RAG 검색 우선 순서를 반드시 프롬프트에 포함할 것
- 보안 민감 정보 (비밀번호, API 키, 토큰 값) 절대 포함 금지
- Obsidian 위키링크 [[문서명]] 형식 유지
- YAML frontmatter 필수 (date, type, project, commit 등)
