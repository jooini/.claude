# Codex Claude 호환 사용법

## 개요

지금 구성은 `~/.claude`를 원본으로 두고 Codex 쪽 설정과 Workspace 프로젝트 규칙을 자동 동기화하는 방식이다.

핵심 흐름:
- `~/.claude/CLAUDE.md` -> `~/.codex/AGENTS.md`
- `~/Workspace/*/CLAUDE.md` 또는 `~/Workspace/*/.claude/CLAUDE.md` -> 각 프로젝트 `AGENTS.md`
- `~/.claude/settings.json` -> `~/.codex/hooks.json`
- `~/.claude/skills/*` -> `~/.codex/skills/*`

## 언제 적용되나

- 새 Codex 세션: 바로 적용
- 이미 열려 있던 Codex 세션: 재시작 권장
- 세션 시작 시 `~/.codex/hooks.json`에서 `~/.claude/scripts/sync-codex.sh --quiet`가 자동 실행됨
- 프롬프트 제출 시 필요하면 Gemini/Claude 보조 훅이 백그라운드 실행됨

## 동기화 명령

전체 동기화:

```bash
~/.claude/scripts/sync-codex.sh
```

상태 확인:

```bash
~/.claude/scripts/sync-codex.sh status
```

미리보기:

```bash
~/.claude/scripts/sync-codex.sh --dry-run
```

## 프로젝트에서 쓰는 법

각 프로젝트에 생성된 `AGENTS.md`가 Claude식 호출을 Codex에서 해석하는 기준이 된다.

예:

```text
@dev backlog
@dev active
@dev 지금 작업 진행해
@team 이 API 변경 영향 범위 같이 봐
백엔드 현재 프로젝트 기능 구현해
리뷰어 현재 변경분 리뷰해
테스터 관련 테스트만 확인해
```

## 글로벌 역할 호출

아래는 바로 써도 되는 대표 호출명이다.

| 호출명 | 프롬프트 |
|--------|----------|
| `백엔드`, `backend`, `backend-developer` | `~/.claude/agents/backend-developer.md` |
| `프론트`, `frontend`, `frontend-developer` | `~/.claude/agents/frontend-developer.md` |
| `AI엔지니어`, `ai`, `ai-engineer` | `~/.claude/agents/ai-engineer.md` |
| `리뷰어`, `reviewer`, `code-reviewer` | `~/.claude/agents/code-reviewer.md` |
| `테스터`, `tester`, `code-tester` | `~/.claude/agents/code-tester.md` |
| `큐에이`, `qa` | `~/.claude/agents/qa.md` |
| `디자이너`, `designer` | `~/.claude/agents/designer.md` |
| `피오`, `po` | `~/.claude/agents/po.md` |
| `데이터`, `data`, `data-analyst` | `~/.claude/agents/data-analyst.md` |
| `옵스`, `ops`, `ops-lead` | `~/.claude/agents/ops-lead.md` |
| `프롬프트`, `prompt`, `prompt-engineer` | `~/.claude/agents/prompt-engineer.md` |
| `디버그`, `디버깅`, `debug-master` | `~/.claude/agents/debug-master.md` |
| `dev-lead` | `~/.claude/agents/dev-lead.md` |

## 파일명으로 직접 호출

매핑표에 없는 에이전트도 호출 가능하다.

예:

```text
~/.claude/agents/dev-lead.md처럼 진행해
~/.claude/agents/code-reviewer.md 기준으로 리뷰해
./.claude/agents/dev.md 기준으로 현재 프로젝트 작업 진행해
./.claude/agents/team.md 기준으로 영향 범위 판단해
```

규칙:
- 현재 프로젝트 `.claude/agents/{name}.md` 우선
- 없으면 전역 `~/.claude/agents/{name}.md`

## 서브에이전트와 같이 쓰는 법

Codex 내장 서브에이전트를 쓰고 싶으면 요청에 같이 적으면 된다.

```text
@dev 이 작업 진행해. 필요하면 서브에이전트로 나눠.
백엔드로 구현하고 리뷰어로 병렬 검토해.
```

실제로는:
- Codex 내장 `worker`, `explorer`, `default` 사용
- 역할 프롬프트는 Claude 에이전트 파일 기준으로 맞춤

## 자동 하이브리드 오케스트레이션

Codex `UserPromptSubmit` 훅이 아래 조건에서 보조 실행을 시작할 수 있다.

- Gemini 프로젝트 스캔:
  - `@dev`, `@team`, 구조, 설계, 아키텍처, 영향, 분석, 디버그 계열 요청
- Gemini 리뷰 프리스캔:
  - 리뷰, diff, PR, 회귀, `리뷰어`, `code-reviewer` 계열 요청
- Claude brief:
  - `@dev`, `@team`, `dev-lead`, 계획, 설계, backlog, active, 영향 범위 계열 요청

생성 파일:

- `~/.claude/cache/gemini/{project}-scan.md`
- `~/.claude/cache/gemini/{project}-review-prescan.md`
- `~/.claude/cache/claude/{project}-codex-brief.md`

인증 전제:

- Claude brief는 `claude auth status`가 로그인 상태일 때만 자동 실행
- Gemini 보조 실행은 `~/.gemini` 인증 파일이 있을 때만 시도

강제 트리거 예시:

```text
@dev 이 작업 진행해. gemini 같이.
@team 이 변경 영향 범위 보고 claude 같이 정리해.
하이브리드로 구조 먼저 스캔해
```

## 호환 키워드

아래 키워드도 Claude식 의미로 해석한다.

- `코드만`, `구현만`
- `리뷰 없이`, `검증 없이`
- `테스트 없이`
- `파이프라인 없이`, `단독으로`
- `TDD로`
- `스펙 없이`

예:

```text
백엔드 로그인 API 구현해. 테스트 없이.
리뷰어 현재 diff 리뷰해. 단독으로.
@dev 이 기능 TDD로 진행해
```

## 권장 사용 루틴

1. `~/.claude` 설정 수정
2. `~/.claude/scripts/sync-codex.sh`
3. 새 Codex 세션 시작
4. 요청 첫 줄에 역할 또는 `@dev`/`@team` 붙여서 지시

## 제한사항

- Claude 에이전트가 Codex에 네이티브 등록되는 것은 아님
- 프롬프트 파일을 읽어서 역할을 재현하는 방식
- Claude 훅 중 `PreToolUse`, `PostToolUse`, `PreCompact`, `Notification` 은 Codex에 그대로 옮기지 않음
- 저장소가 없는 경로의 설정 파일은 git 커밋 대상이 아님

## 확인 포인트

```bash
~/.claude/scripts/sync-codex.sh status
```

정상 상태 기준:
- 글로벌 AGENTS: 최신
- Codex hooks: 최신
- 스킬: 사용 가능
- 프로젝트 상태: 전부 최신
