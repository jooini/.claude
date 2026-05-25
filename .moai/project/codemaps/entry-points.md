---
title: "진입점, 슬래시 명령, 훅 이벤트 매처"
type: codemap
subtype: entry-points
version: "1.0"
created: "2026-05-25"
---

# 진입점, 슬래시 명령, 훅 이벤트 매처

> 사용자와 시스템이 하네스에 접근하는 모든 진입점을 목록화한다.
> 의존성 그래프는 [dependencies.md](./dependencies.md), 데이터 흐름은 [data-flow.md](./data-flow.md) 참조.

---

## CLI 진입점

### `claude` — Claude Code CLI

모든 상호작용의 최상위 진입점. 사용자가 터미널에서 `claude` 명령을 실행하면 Claude Code 런타임이 시작되고, `settings.json`의 `SessionStart` 훅이 자동으로 실행된다.

```bash
# 기본 실행
claude

# 격리된 worktree 세션
claude --worktree [이름]
claude -w [이름]

# tmux 분할 표시 (tmux 또는 iTerm2 필요)
claude --worktree --tmux
```

### `package.sh` / `setup.sh` — 하네스 초기화

`scripts/` 디렉토리에 위치하는 하네스 수준 초기화 스크립트.

```bash
# 전체 하네스 패키징
/Users/leonard/.claude/scripts/package.sh

# 하네스 초기화 (신규 환경 설정)
/Users/leonard/.claude/scripts/setup.sh
```

### `agents/build-agents.sh` — 에이전트 빌드

`agents-src/`의 소스 원본을 빌드하여 `agents/`의 활성 정의를 생성한다.

```bash
/Users/leonard/.claude/agents/build-agents.sh
```

### `scripts/run-local-rag.sh` — RAG 서버 실행

`local-rag` MCP 서버가 사용하는 로컬 RAG 서버를 Ollama 연동으로 시작한다.

```bash
/Users/leonard/.claude/scripts/run-local-rag.sh
```

---

## 슬래시 명령 14종

`commands/` 디렉토리의 14개 파일이 슬래시 명령을 정의한다. 모든 파일은 얇은 라우팅 래퍼(20줄 이하)이며 로직 없이 스킬로 위임한다.

| 명령 | 위임 대상 스킬 | 역할 |
|------|-------------|------|
| `/retro` | `retro` | 회고 — `cache/md-live/` 결정 데이터 기반 패턴 분석 |
| `/decisions [검색어]` | `decisions` | 의사결정 이력 조회 및 검색 |
| `/backlog` | `backlog` | 백로그 등록·조회·우선순위 관리 |
| `/project-status` | `project-status` | 현재 프로젝트 현황 종합 보고 |
| `/morning` | `morning` | 아침 종합 시작 루틴 (캘린더·백로그·health 확인) |
| `/yesterday` | `yesterday` | 전일 작업 요약 |
| `/today-tasks` | `today-tasks` | 오늘 작업 목록 생성 |
| `/moai [서브명령]` | `moai` | MoAI 통합 오케스트레이터 |
| `/debug` | `debug` | 7단계 디버깅 절차 가이드 |
| `/safe-deploy` | `safe-deploy` | 배포 전 안전 검증 절차 |
| `/deploy-status` | `deploy-status` | 배포 현황 확인 |
| `/usage` | `usage` | 토큰 사용량 분석 |
| `/logs` | `logs` | 훅 실행 로그 조회 |
| `/session-handoff` | `session-handoff` | 세션 인계 문서 생성 |

---

## 사용자 호출 가능 스킬 (주요 직접 호출 대상)

슬래시 명령 외에도 다음 스킬들은 대화 중 직접 호출하거나 Skill() 함수로 호출할 수 있다. (전체 118개 중 주요 항목)

| 스킬 명 | 역할 | 호출 트리거 |
|---------|------|-----------|
| `forecast` | 작업 예측·위험 분석·예상 결과 | `/forecast` 또는 Skill("forecast") |
| `witness` | 세션 목격자 기록 (현재 상태 스냅샷) | `/witness` 또는 Skill("witness") |
| `qq` | 빠른 질의응답 (Quick Question) | `/qq` 또는 Skill("qq") |
| `trace` | 실행 흐름 추적 | `/trace` 또는 Skill("trace") |
| `go` | Go 언어 특화 작업 | `/go` 또는 Skill("go") |
| `ask-gemini` | Antigravity/Gemini CLI 질의 | Skill("ask-gemini") |
| `ask-codex` | Codex CLI 세컨드 오피니언 | Skill("ask-codex") |
| `ask-ollama` | 로컬 Ollama 모델 질의 | Skill("ask-ollama") |
| `ask-gemma` | Gemma 모델 특화 질의 | Skill("ask-gemma") |
| `vault-find` | Obsidian Vault 파일 검색 | Skill("vault-find") |
| `deep-learn` | 심층 학습 분석 | Skill("deep-learn") |
| `cross-check` | 교차 검증 | Skill("cross-check") |
| `hook-audit` | 훅 전체 점검 | Skill("hook-audit") |
| `hook-health` | 훅 건강 상태 확인 | Skill("hook-health") |
| `bisect` | git bisect 기반 버그 범위 축소 | Skill("bisect") |
| `dormant-chunks` | 사용되지 않는 코드 탐지 | Skill("dormant-chunks") |
| `decisions-wave` | 결정 파동 분석 | Skill("decisions-wave") |
| `vitality` | 시스템 생명력 지표 확인 | Skill("vitality") |
| `self-model` | 에이전트 자기 모델 조회 | Skill("self-model") |
| `badge` | 프로젝트 배지 생성 | Skill("badge") |
| `start` / `done` / `interrupt` | 작업 시작·완료·중단 신호 | Skill("start"), Skill("done"), Skill("interrupt") |
| `receipt-report` / `receipt-pdf` | 영수증 형식 보고서 생성 | Skill("receipt-report") |
| `closure` | 세션 마감 절차 | Skill("closure") |
| `sync-antigravity` | Antigravity 동기화 | Skill("sync-antigravity") |
| `codex:rescue` | Codex 구조 요청 (3회 실패 시) | 자동 트리거 또는 Skill("codex:rescue") |
| `claude-mem:mem-search` | claude-mem 크로스 세션 메모리 검색 | Skill("claude-mem:mem-search") |
| `superpowers:dispatching-parallel-agents` | 병렬 에이전트 디스패치 | Skill("superpowers:dispatching-parallel-agents") |

---

## 훅 이벤트 매처

`settings.json`의 `hooks` 섹션에 정의된 이벤트별 훅 핸들러 매핑이다.

### SessionStart

세션 시작 시 실행. 프로젝트 컨텍스트 로드, MCP 서버 점검, 캘린더·백로그 상태 확인.

| 훅 핸들러 | 역할 |
|----------|------|
| `session-start-router.sh` | git remote 기반 프로젝트 식별, intent/{hash}/ 로드 |
| `mcp-healthcheck` | MCP 서버 가용성 사전 점검 |
| `calendar-check` | 오늘 일정 확인 |
| `backlog-check` | 백로그 상태 확인 |

### UserPromptSubmit

사용자 발화 입력 시 실행. 스킬 키워드 감지, 라우팅 결정, 발화 기록.

| 훅 핸들러 | 역할 |
|----------|------|
| `user-prompt-router.sh` | 스킬 키워드 감지, 스킬 자동 로드 신호 |
| `taskhub-utterance.sh` | 발화 내용 taskhub에 기록 |
| `agent-routing-suggest.sh` | P5 라우팅 제안 생성 |

### PreToolUse(Bash)

Bash 도구 실행 전. 위험 명령 감지, 커밋 규칙 적용.

| 훅 핸들러 | 조건 | 역할 |
|----------|------|------|
| `commit-no-coauthor` | `git commit` 명령 포함 시 | Co-Authored-By 태그 차단 |
| `dangerous-command-pre` | rm -rf, force push 등 패턴 | 위험 명령 사전 경고 |

### PreToolUse(Edit|Write)

파일 수정 도구 실행 전. 코드 변경 전 Gemini 스캔 강제.

| 훅 핸들러 | 조건 | 역할 |
|----------|------|------|
| `gemini-prescan-enforcer` | 코드 파일(.py/.go/.ts 등) 수정 시 | agy Phase 0 스캔 강제 실행 |
| `dependency-change-detect` | package.json/go.mod 등 수정 시 | 의존성 파일 변경 감지 → 스캔 요청 |

### PreToolUse(Agent)

에이전트 실행 전. 라우팅 제안, 컨텍스트 주입.

| 훅 핸들러 | 역할 |
|----------|------|
| `agent-routing-suggest.sh` | P5 기반 에이전트 라우팅 제안 |
| `agent-context-inject.sh` | intent/{hash}/ 컨텍스트 주입 |

### PostToolUse(Bash)

Bash 도구 실행 후. 오류 감지, 위험 명령 사후 경고, 타이밍 기록.

| 훅 핸들러 | 조건 | 역할 |
|----------|------|------|
| `bash-postproc-sync` | 항상 | 테스트 결과·에러 동기 처리 |
| `bash-postproc-async` | 항상 (비동기) | 타이밍 기록 |
| `error-codex-remind` | 오류 발생 시 | 3회 연속 실패 시 codex:rescue 안내 |
| `dangerous-command-detect` | rm -rf 등 실행 후 | 위험 명령 사후 감지·경고 |

### PostToolUse(Agent)

에이전트 실행 완료 후. 완료 알림, 메트릭 기록, 결정 캡처, 라우팅 채택 추적.

| 훅 핸들러 | 역할 |
|----------|------|
| `agent-complete-notify` | 에이전트 완료 알림 |
| `pipeline-metrics-log` | 파이프라인 실행 시간 telemetry/ 기록 |
| `decision-capture` | 의사결정 cache/md-live/ 비동기 캡처 (8초 딜레이) |
| `suggestion-outcome-track` | 라우팅 제안 채택 여부 추적 (3초 딜레이) |

### Stop

세션 종료 시. 12개 훅이 병렬로 실행. 학습·결정·핸드오프·예산 캡처.

| 훅 핸들러 | 타임아웃 | 역할 |
|----------|---------|------|
| `gemma-session-stop-unified` | 90초 | 세션 종합 학습 캡처 (Gemma 모델) |
| `qwen-decision-capture` | 60초 | 의사결정 Qwen 기반 캡처 |
| `qwen-learning-capture` | 60초 | 학습 내용 Qwen 기반 추출 |
| `qwen-handoff-suggest` | 5초 | 핸드오프 제안 생성 |
| `daily-learning-capture.sh` | 15초 | 일일 교훈 memory/lessons.md 업데이트 |
| `turn-summary` | 5초 | 세션 턴 요약 |
| `budget-alert` | 5초 | 토큰 예산 경고 |
| (기타 5개 병렬 훅) | 다양 | 추가 세션 종료 처리 |

**경고**: Stop 이벤트에 12개 훅이 병렬 실행되며 cascading timeout 위험이 있다. 각 훅은 독립 타임아웃으로 실행되어 일부 캡처가 누락될 수 있다.

### PreCompact

컨텍스트 압축 전. 필요 시 중요 데이터 보존.

| 훅 핸들러 | 역할 |
|----------|------|
| `precompact-snapshot` | 압축 전 컨텍스트 스냅샷 저장 |

### Notification

시스템 알림 발생 시. 사용자 알림 처리.

### TaskCreate / TaskUpdate

태스크 생성·갱신 이벤트. taskhub 연동.

| 훅 핸들러 | 이벤트 | 역할 |
|----------|--------|------|
| `taskhub-create.sh` | TaskCreate | 태스크 생성 taskhub 기록 |
| `taskhub-update.sh` | TaskUpdate | 태스크 상태 갱신 taskhub 반영 |

---

## MCP 진입점

| 서버 이름 | 등록 위치 | 접근 방법 |
|----------|----------|---------|
| `context7` | `.mcp.json` | 에이전트에서 MCP 도구 자동 사용 (`resolve-library-id`, `get-library-docs`) |
| `sequential-thinking` | `.mcp.json` | 에이전트에서 MCP 도구 자동 사용 (`create_thinking_session`) |
| `moai-lsp` | `.mcp.json` | 에이전트에서 MCP 도구 자동 사용 (LSP 진단, 코드 완성) |
| `codex-cli` | `settings.json` | `ask-codex` 스킬, `codex:rescue` 스킬 |
| `local-rag` | `settings.json` | `ask-ollama` 스킬, 코드 검색 시 자동 |
| `gitlab` | `settings.json` | GitLab 관련 명령 시 자동 |

---

## /moai 서브명령 진입점

`/moai` 명령은 `moai` 스킬(MoAI 통합 오케스트레이터)로 위임된다. 다음 서브명령을 지원한다.

| 서브명령 | 역할 | 관련 워크플로우 |
|---------|------|--------------|
| `plan` / `moai:plan` | SPEC-First Phase 1 — EARS 형식 스펙 생성 | `moai-workflow-spec` |
| `run` / `moai:run` | DDD Phase 2 — ANALYZE·PRESERVE·IMPROVE 실행 | `moai-foundation-core` |
| `sync` / `moai:sync` | Phase 3 — 문서·API·다이어그램 동기화 | `moai-workflow-project` |
| `design` / `moai:design` | 디자인 파이프라인 (GAN Loop) | `moai-domain-brand-design` |
| `db` / `moai:db` | 데이터베이스 스키마·마이그레이션 | `moai-platform-database-cloud` |
| `project` / `moai:project` | 프로젝트 문서 생성·갱신 | `moai-workflow-project` |
| `fix` / `moai:fix` | 버그 수정 워크플로우 | `moai-workflow-loop` |
| `loop` / `moai:loop` | 반복 개선 루프 | `moai-workflow-loop` |
| `mx` / `moai:mx` | MX 태그 관리 | MoAI 내부 |
| `feedback` / `moai:feedback` | 지속적 개선 피드백 | `moai-foundation-quality` |
| `review` / `moai:review` | PR/코드 리뷰 | `moai-foundation-quality` |
| `clean` / `moai:clean` | 코드 정리·정돈 | MoAI 내부 |
| `codemaps` / `moai:codemaps` | 코드맵 문서 생성 | `moai-workflow-project` |
| `coverage` / `moai:coverage` | 테스트 커버리지 분석 | `moai-workflow-testing` |
| `e2e` / `moai:e2e` | E2E 테스트 실행 | `moai-workflow-testing` |
| `context` | 컨텍스트 관리 | `moai-foundation-context` |
| `gate` | 품질 게이트 실행 | `moai-foundation-quality` |
| `security` | 보안 검토 | `moai-ref-owasp-checklist` |

---

*아키텍처 개요: [overview.md](./overview.md)*
*모듈 인터페이스: [modules.md](./modules.md)*
*의존성 그래프: [dependencies.md](./dependencies.md)*
*데이터 흐름: [data-flow.md](./data-flow.md)*

Last updated: 2026-05-25
