---
name: claude-docs-reader
description: ~/.claude 디렉토리의 설정, 에이전트, 스킬, MCP 서버 등을 분석하고 요약합니다.
argument-hint: "[에이전트|스킬|MCP|전체]"
allowed-tools: Read, Glob, Bash(ls *)
---

# Claude Docs Reader

`~/.claude` 디렉토리의 구조와 설정을 분석하여 사용자에게 요약을 제공한다.

## ~/.claude 디렉토리 맵

| 경로 | 용도 | 파일 형태 |
|------|------|----------|
| `CLAUDE.md` | 글로벌 설정 (모든 프로젝트에 적용) | 마크다운 |
| `settings.json` | 사용자 설정 (MCP 서버, 플러그인 등) | JSON |
| `agents/` | 커스텀 에이전트 정의 | `.md` 파일 |
| `agents/knowledge/` | 에이전트 도메인 지식 (빌드 시 삽입) | `.md` 파일 |
| `agents/pipelines/` | 에이전트 파이프라인 정의 | `.md` 파일 |
| `commands/` | 커스텀 슬래시 커맨드 | `.md` 파일 |
| `skills/` | 스킬 정의 | `SKILL.md` |
| `hooks/` | 이벤트 훅 스크립트 | `.sh` 파일 |
| `plans/` | 자동 생성된 플랜 파일 | `.md` 파일 |
| `projects/` | 프로젝트별 컨텍스트 (세션, 메모리 등) | 디렉토리 |
| `{프로젝트명}/CLAUDE.md` | 프로젝트별 CLAUDE.md | 마크다운 |
| `plugins/` | 설치된 플러그인 | 디렉토리 |

## 실행 절차

### 1단계: 사용자 요청 분류

| 질문 유형 | 읽을 대상 | 예시 |
|----------|----------|------|
| 전체 개요 | 디렉토리 구조 + 핵심 파일 | "설정 전체 보여줘" |
| 에이전트 | `agents/*.md` + `agents/knowledge/` | "에이전트 뭐 있어?" |
| 스킬 | `skills/*/SKILL.md` | "스킬 뭐 있어?" |
| MCP 서버 | `settings.json` (mcpServers) | "MCP 서버 확인" |
| 프로젝트 설정 | `{프로젝트명}/CLAUDE.md` | "identity-hub 설정" |
| 파이프라인 | `agents/pipelines/` | "파이프라인 어떻게 동작해?" |
| 훅 | `hooks/` | "훅 뭐 있어?" |
| 글로벌 설정 | `CLAUDE.md` | "글로벌 규칙 보여줘" |

### 2단계: 해당 파일 읽기

분류된 카테고리에 해당하는 파일만 읽는다. `CLAUDE.md`는 이미 시스템 프롬프트에 로드되므로 재읽기 불필요.

### 3단계: 분석 결과 제공

카테고리별 요약:

- **에이전트**: 이름, 역할, 사용 도구, 파이프라인 연동 여부
- **스킬**: 이름, description, 주요 기능, 산출물 경로
- **MCP 서버**: 서버명, 패키지, 연결 대상 (토큰은 `***`로 마스킹)
- **전체 개요**: 테이블 형태로 구성요소 수량 + 항목 나열

## 주의사항

- `settings.json`의 API 토큰, 비밀번호는 절대 출력하지 않는다. 마스킹 필수.
- `history.jsonl`은 대용량이므로 읽지 않는다.
