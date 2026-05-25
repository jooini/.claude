---
title: "모듈 설명 및 공개 인터페이스"
type: codemap
subtype: modules
version: "1.0"
created: "2026-05-25"
---

# 모듈 설명 및 공개 인터페이스

> 각 모듈의 책임·입출력·핵심 파일을 카드 형식으로 서술한다.
> 전체 아키텍처는 [overview.md](./overview.md), 의존성은 [dependencies.md](./dependencies.md) 참조.

---

## 1. `hooks/` — 이벤트 자동화 모듈

**책임**: Claude Code 런타임 이벤트에 반응하여 보안 검증, 학습 캡처, 메트릭 기록, 에이전트 컨텍스트 주입, 경고 발령 등 모든 자동화 작업을 수행한다. 이 모듈이 전체 하네스의 자동화 엔진이다.

**입력 인터페이스**:
- `settings.json` 훅 레지스트리로부터 이벤트 수신 (JSON via stdin)
- 이벤트 타입: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `PreCompact`, `Notification`, `TaskCreate`, `TaskUpdate`
- 각 이벤트 페이로드에는 이벤트 타입, 도구 이름, 입력 파라미터 등이 포함됨

**출력 인터페이스**:
- `cache/md-live/suggestion-outcomes.jsonl` — 라우팅 제안 채택률 기록
- `cache/md-live/hook-outcomes.jsonl` — 훅 실행 결과 기록
- `cache/md-live/` — decision-capture 산출물
- `memory/MEMORY.md`, `memory/lessons.md` — 학습 캡처 결과
- `telemetry/` — 파이프라인 실행 메트릭
- `self-model/` — 에이전트 행동 흔적
- stdout/stderr — PreToolUse 훅의 경우 차단 신호 또는 컨텍스트 주입 텍스트

**핵심 파일 (표본)**:
| 파일 | 이벤트 | 역할 |
|------|--------|------|
| `session-start-router.sh` | SessionStart | git remote 기반 프로젝트 식별, intent 로드 |
| `user-prompt-router.sh` | UserPromptSubmit | 스킬 키워드 감지, 라우팅 결정 |
| `gemini-prescan-enforcer` | PreToolUse(Edit\|Write) | 코드 수정 전 agy Phase 0 스캔 강제 |
| `commit-no-coauthor` | PreToolUse(Bash) | Co-Authored-By 태그 포함 커밋 차단 |
| `dangerous-command-detect` | PostToolUse(Bash) | 위험 명령 실행 후 감지·경고 |
| `error-codex-remind` | PostToolUse(Bash) — 오류 시 | 3회 실패 시 codex:rescue 트리거 안내 |
| `decision-capture` | PostToolUse(Agent) | 의사결정 비동기 캡처 (8초 딜레이) |
| `suggestion-outcome-track` | PostToolUse(Agent) | 라우팅 채택 여부 추적 (3초 딜레이) |
| `gemma-session-stop-unified` | Stop | 세션 종합 학습 캡처 (타임아웃 90초) |
| `qwen-learning-capture` | Stop | Qwen 기반 학습 추출 (타임아웃 60초) |
| `daily-learning-capture.sh` | Stop | 일일 교훈 누적 (타임아웃 15초) |
| `pipeline-metrics-log` | PostToolUse(Agent) | 파이프라인 실행 시간 기록 |

**외부 도구 의존성**: `agy`(Antigravity CLI), `ollama`(로컬 LLM), `git`, `gh`, `codex`

**구조적 리스크**: Stop 이벤트에 12개 훅이 병렬로 실행되며 cascading timeout 위험 존재. 각 훅은 독립 타임아웃(5초~90초)으로 실행되어 일부 캡처 누락 가능. 최근 hook audit(c267d50)에서 일부 완화됨.

---

## 2. `skills/` + `.claude/.claude/skills/` — 스킬 자동 로드 모듈

**책임**: 에이전트가 특정 도메인 작업을 수행하는 데 필요한 지식과 절차를 캡슐화한다. YAML frontmatter 기반으로 컨텍스트에 맞는 스킬이 자동으로 에이전트 컨텍스트에 주입되거나, 슬래시 명령으로 직접 호출된다.

**입력 인터페이스**:
- `user-prompt-router.sh`로부터 키워드 감지 신호
- 슬래시 명령 직접 호출 (`/forecast`, `/debug`, `/qq` 등)
- `Skill()` 함수 호출 (commands/*.md에서 위임)

**출력 인터페이스**:
- 에이전트 컨텍스트에 스킬 본문 주입 (마크다운 텍스트)
- 슬래시 명령의 경우 사용자에게 직접 결과 반환

**핵심 파일 (표본)**:
| 경로 | 스킬 | 역할 |
|------|------|------|
| `skills/forecast/` | `forecast` | 작업 예측·위험 분석 |
| `skills/debug/` | `debug` | 7단계 디버깅 절차 가이드 |
| `skills/qq/` | `qq` | 빠른 질의응답 |
| `skills/witness/` | `witness` | 세션 목격자 기록 |
| `skills/usage/` | `usage` | 토큰 사용량 분석 |
| `.claude/skills/moai-foundation-core/` | `moai-foundation-core` | TRUST 5 프레임워크, SPEC-First DDD |
| `.claude/skills/moai-library-nextra/` | `moai-library-nextra` | Nextra 문서 아키텍처 |
| `.claude/skills/moai-workflow-project/` | `moai-workflow-project` | 프로젝트 문서 통합 관리 |
| `.claude/skills/ask-gemini/` | `ask-gemini` | Antigravity CLI를 통한 Gemini 질의 |
| `.claude/skills/ask-codex/` | `ask-codex` | Codex CLI를 통한 세컨드 오피니언 |
| `.claude/skills/ask-ollama/` | `ask-ollama` | 로컬 Ollama 모델 질의 및 키워드 라우팅 |

**이중 경로 구조**:
- `.claude/skills/` (즉 `~/.claude/skills/`) — 사용자 정의 70개: 프로젝트별 커스텀 스킬, 도구 연동 스킬
- `.claude/.claude/skills/` (즉 `~/.claude/.claude/skills/`) — MoAI 프레임워크 48개: moai-* 네임스페이스

**외부 도구 의존성**: 스킬별 상이. `agy`, `codex`, `ollama`, `gh`, `git` 등.

**알려진 리스크**: 두 경로 간 동일 이름 스킬 존재 시 로드 우선순위 불명확.

---

## 3. `agents/` — 특화 위임 모듈

**책임**: 도메인별 전문 에이전트 역할·권한·시스템 프롬프트를 정의한다. `CLAUDE.md`의 P0-P6 라우팅 결정표에 따라 사용자 요청이 해당 에이전트로 위임되며, 에이전트는 자신의 도메인 전문성으로 작업을 수행한다.

**입력 인터페이스**:
- P0-P6 라우팅 결정 (CLAUDE.md에서 매칭)
- `@에이전트명` 직접 호출 (`@dev`, `@team`)
- 한글 에이전트명 호출 (`백엔드`, `프론트`, `큐에이` 등)

**출력 인터페이스**:
- 도구 실행 결과 (Read/Edit/Bash/Agent 등)
- `PostToolUse(Agent)` 이벤트를 통해 hooks 모듈로 결과 전달
- 사용자에게 마크다운 형식의 응답

**핵심 파일 (표본)**:
| 파일 | 에이전트 | 역할 |
|------|----------|------|
| `agents/dev-lead.md` | dev-lead | 오케스트레이터, @dev 폴백 |
| `agents/backend-developer.md` | backend-developer | API/DB/마이그레이션/인증 구현 |
| `agents/frontend-developer.md` | frontend-developer | UI/컴포넌트/스타일 구현 |
| `agents/code-reviewer.md` | code-reviewer | 코드 품질 리뷰 |
| `agents/code-tester.md` | code-tester | lint/build/test 실행 |
| `agents/qa.md` | qa | 테스트 설계·케이스·시나리오 |
| `agents/designer.md` | designer | UI/UX 디자인 |
| `agents/data-analyst.md` | data-analyst | 쿼리·대시보드·데이터 분석 |

**빌드 구조**:
```
agents-src/{lang}/*.md  (소스 원본 13개)
  → build-agents.sh
  → agents/builds/{lang}/*.md  (빌드 결과)
  → agents/*.md  (활성 정의 14개)
```

**외부 도구 의존성**: 에이전트 내부에서 `MCP 서버`, `agy`, `codex`, `gh`, `git` 등 호출.

**알려진 리스크**: 소스 원본(`agents-src/`) → 빌드 과정에서 프롬프트 뉘앙스 손실 가능. 원본이 항상 정본.

---

## 4. `commands/` — 슬래시 라우터 모듈

**책임**: 사용자가 입력하는 슬래시 명령을 적절한 스킬이나 에이전트로 위임하는 얇은 라우팅 래퍼다. 모든 명령 파일은 20줄 이하이며, 로직 없이 `Skill()` 호출만 수행한다.

**입력 인터페이스**:
- 사용자 직접 입력 (`/명령 [인수]`)

**출력 인터페이스**:
- `Skill()` 호출 → 해당 스킬 실행
- 에이전트 위임 (`Agent()` 호출)

**14개 슬래시 명령 목록**:
| 명령 파일 | 위임 대상 | 역할 |
|----------|----------|------|
| `retro.md` | `retro` 스킬 | 회고 및 패턴 분석 |
| `decisions.md` | `decisions` 스킬 | 의사결정 이력 조회 |
| `backlog.md` | `backlog` 스킬 | 백로그 등록·조회 |
| `project-status.md` | `project-status` 스킬 | 프로젝트 현황 보고 |
| `morning.md` | `morning` 스킬 | 아침 종합 시작 루틴 |
| `yesterday.md` | `yesterday` 스킬 | 전일 요약 |
| `today-tasks.md` | `today-tasks` 스킬 | 오늘 작업 목록 |
| `moai.md` | `moai` 스킬 | MoAI 통합 오케스트레이터 |
| `debug.md` | `debug` 스킬 | 7단계 디버깅 절차 |
| `safe-deploy.md` | `safe-deploy` 스킬 | 배포 전 안전 검증 |
| `deploy-status.md` | `deploy-status` 스킬 | 배포 현황 확인 |
| `usage.md` | `usage` 스킬 | 토큰 사용량 분석 |
| `logs.md` | `logs` 스킬 | 로그 조회 |
| `session-handoff.md` | `session-handoff` 스킬 | 세션 인계 문서 생성 |

**외부 도구 의존성**: 없음 (라우팅만 수행).

---

## 5. `workflows/` — 조건부 로드 절차 모듈

**책임**: 도메인별 상세 실행 절차를 담은 문서 16개를 보관한다. CLAUDE.md 키워드 트리거 테이블에 따라 조건부로 로드되어 에이전트 컨텍스트에 주입된다. CLAUDE.md 본문의 토큰 비용을 줄이면서도 필요 시 전체 절차를 제공하는 구조다.

**입력 인터페이스**:
- CLAUDE.md의 키워드 트리거 매칭 결과 (에이전트가 `Read` 도구로 조건부 로드)

**출력 인터페이스**:
- 마크다운 문서 텍스트 → 에이전트 컨텍스트에 주입

**16개 워크플로우 문서 목록**:
| 파일 | 트리거 키워드 | 내용 |
|------|------------|------|
| `pipeline.md` | 파이프라인/backend/frontend/fullstack | 파이프라인 실행 절차 |
| `codex.md` | Codex 호출 | Codex 연동 가이드 |
| `projects.md` | 프로젝트 목록/무슨 스택 | 관리 중인 프로젝트 목록 |
| `sso.md` | SSO/BFF/Identity Hub | SSO 디버깅 절차 |
| `docs-convention.md` | Obsidian/문서 작성/vault | 문서 작성 컨벤션 |
| `standard-routines.md` | feature/bugfix/refactor/design/data/ops/docs | 타입별 표준 루틴 |
| `self-modification-pattern.md` | CLAUDE.md/settings.json 수정 | 자기 수정 패턴 |
| `llm-routing.md` | Gemma/Gemini/Codex/Ollama 라우팅 | LLM 라우팅 결정 |
| `debugging.md` | 에러/버그/디버깅 | 7단계 디버깅 절차 |
| `coding-convention.md` | 코드 작성/코딩 컨벤션 | 코딩 컨벤션 상세 |
| `automation.md` | 자동화/메트릭/hook 동작 | 자동화 훅 상세 |
| `growth.md` | 학습/회고/큰 결정/3중 LLM | 성장·회고 패턴 |
| `sdd-tdd.md` | SDD/TDD/컨텍스트 관리 | SDD+TDD 워크플로우 |
| `backlog-policy.md` | 백로그 등록/트랙 | 백로그 정책 |
| `search-priority.md` | 코드 검색/RAG/Grep | 검색 우선순위 |
| `debugging.md` (상세) | 추가 디버깅 시나리오 | 확장 디버깅 절차 |

**외부 도구 의존성**: 없음 (문서 보관소).

---

## 6. `.claude/.claude/rules/` — 헌법 모듈

**책임**: 시스템 전체를 지배하는 헌법적 규칙을 보관한다. 세션 시작 시 프로젝트 인스트럭션으로 자동 로드되어 모든 에이전트의 행동 제약 조건을 형성한다. FROZEN 존 규칙은 어떤 에이전트도 수정할 수 없다.

**입력 인터페이스**:
- 세션 시작 시 Claude Code가 자동 로드 (project instructions)

**출력 인터페이스**:
- 에이전트 시스템 프롬프트에 규칙 텍스트 주입
- FROZEN 규칙 위반 시 실행 차단

**핵심 파일 (표본)**:
| 파일 | 역할 |
|------|------|
| `moai/design/constitution.md` | 디자인 시스템 헌법 v3.3.0 — FROZEN 존 포함 |
| `moai/core/moai-constitution.md` | MoAI 오케스트레이터 핵심 원칙 |
| `moai/core/agent-common-protocol.md` | 모든 에이전트 공통 프로토콜 |
| `moai/core/lsp-client.md` | LSP 클라이언트 선택 결정 (powernap v0.1.4) |
| `moai/development/coding-standards.md` | 코딩 표준 (언어 정책, 파일 크기, 얇은 명령 패턴) |
| `moai/workflow/worktree-integration.md` | Worktree 통합 가이드 |
| `moai/workflow/file-reading-optimization.md` | 파일 읽기 최적화 (4단계 토큰 절약) |
| `moai/workflow/team-protocol.md` | 팀 에이전트 공통 프로토콜 |

**4개 네임스페이스**:
- `moai/design/` — 디자인 시스템 헌법·GAN Loop 계약·평가자 편향 방지
- `moai/core/` — MoAI 오케스트레이터 원칙·에이전트 공통 프로토콜·LSP 결정
- `moai/development/` — 코딩 표준·언어 정책·얇은 명령 패턴
- `moai/workflow/` — 워크트리·파일 읽기·팀 프로토콜

**외부 도구 의존성**: 없음 (헌법 문서 보관소).

---

## 7. `intent/` — 프로젝트 컨텍스트 저장소

**책임**: git remote URL 기반으로 13개 프로젝트를 해시화하여 식별하고, 프로젝트별 의도·작업 이력·컨텍스트를 세션 간에 유지한다. `SessionStart` 훅이 현재 작업 디렉토리의 git remote를 확인하여 해당 해시 디렉토리를 로드한다.

**입력 인터페이스**:
- `session-start-router.sh`에서 git remote URL 해시 전달
- `Stop` 훅에서 세션 종료 시 컨텍스트 갱신 신호

**출력 인터페이스**:
- 에이전트 컨텍스트에 프로젝트별 의도·이력 주입
- 13개 해시 디렉토리 내 파일 (작업 이력, 활성 계획, 메모 등)

**핵심 파일 (구조)**:
```
intent/
├── {git-remote-url-hash-1}/   # 프로젝트 1 (예: weaversbrain 레포)
│   ├── active/                # 활성 작업 파일
│   ├── memory/                # 프로젝트별 메모리
│   └── *.md                   # 의도 문서
├── {git-remote-url-hash-2}/   # 프로젝트 2
│   └── ...
...
└── {git-remote-url-hash-13}/  # 프로젝트 13
```

**외부 도구 의존성**: `git`(remote URL 조회).

---

## 8. `memory/` — 글로벌 기억 저장소

**책임**: 세션 횡단 글로벌 기억 인덱스(`MEMORY.md`)와 도메인별 교훈 목록(`lessons.md`)을 보관한다. 에이전트는 새 세션 시작 시 이 파일을 참조하여 과거 학습을 컨텍스트에 반영한다.

**입력 인터페이스**:
- `Stop` 훅(`daily-learning-capture.sh`, `qwen-learning-capture`)에서 학습 데이터 기록
- 에이전트가 직접 Write/Edit 도구로 갱신 (메모리 저장 지시 시)

**출력 인터페이스**:
- 에이전트가 `Read` 도구로 조회하여 컨텍스트 보강
- `lessons.md` — 도메인별 교훈 (최대 50건, 초과 시 아카이브)

**핵심 파일**:
| 파일 | 내용 |
|------|------|
| `MEMORY.md` | 에이전트 기억 인덱스 (각 항목: name, description, type, 파일 포인터) |
| `lessons.md` | 도메인별 교훈 (category, incorrect pattern, correct approach, date) |

**외부 도구 의존성**: 없음.

---

## 9. `cache/` — 캐시 저장소

**책임**: RAG 임베딩 캐시, 실측 데이터(라우팅 채택률·훅 결과), 세션 스냅샷, 결정 이력을 저장한다. P5 라우팅 자기 교정의 데이터 원천이자 `/retro`·`/decisions` 스킬의 조회 대상이다.

**입력 인터페이스**:
- `PostToolUse` 훅 비동기 기록 (suggestion-outcome-track, decision-capture)
- `Stop` 훅 기록 (qwen-decision-capture)
- `local-rag` MCP 서버의 RAG 임베딩 결과

**출력 인터페이스**:
- `cache/md-live/suggestion-outcomes.jsonl` — P5 규칙 자기 교정 데이터
- `cache/md-live/hook-outcomes.jsonl` — 훅 노이즈 감지 데이터
- `cache/md-live/` decision 파일들 — `/retro`, `/decisions` 스킬 조회
- RAG 임베딩 — `local-rag` MCP 서버가 코드 검색에 활용

**구조**:
```
cache/
├── md-live/
│   ├── suggestion-outcomes.jsonl   # 라우팅 제안 채택률 (16건 분석 기록)
│   ├── hook-outcomes.jsonl         # 훅 실행 결과
│   └── *.jsonl, *.md               # decision-capture 산출물
├── (RAG 임베딩 디렉토리)            # Ollama 임베딩 캐시 (주 용량)
└── (세션 스냅샷)                    # 세션별 컨텍스트 스냅샷
```

**총 크기**: 1291개 이상 항목 / 약 795MB (정리 정책 ad-hoc — 알려진 리스크).

**외부 도구 의존성**: `ollama`(RAG 임베딩), `local-rag` MCP 서버.

---

## 10. `.moai/` — MoAI 통합 레이어

**책임**: MoAI 프레임워크의 설정·상태·산출물을 관리한다. `manifest.json`이 SHA256 기반 템플릿 레지스트리 역할을 하고, 28개 YAML 섹션이 에이전트 스폰·품질 게이트·SPEC 관리 기준을 정의한다.

**입력 인터페이스**:
- `/moai` 명령군 (plan/run/sync/design 등)
- `moai-*` 스킬 호출
- 에이전트가 SPEC 조회 시 Read 도구

**출력 인터페이스**:
- 에이전트 스폰 컨텍스트 (브랜드·SPEC·품질 기준 제공)
- `specs/SPEC-XXX/spec.md` — SPEC 문서
- `design/` — 디자인 반복 산출물
- `sprints/` — Sprint Contract 산출물
- `state/checkpoints/` — 에이전트 체크포인트
- `evolution-log.md` — 진화 이력

**핵심 구조**:
```
.moai/
├── manifest.json          # 2958줄 SHA256 템플릿 레지스트리
├── config/sections/       # 28개 YAML 설정 섹션
├── project/               # product/structure/tech/interview/codemaps
├── brand/                 # 브랜드 컨텍스트 (헌법적 제약)
├── specs/                 # SPEC-XXX/ 스펙 문서
├── design/                # 디자인 반복 산출물
├── sprints/               # Sprint Contract
├── state/checkpoints/     # 에이전트 체크포인트
└── evolution-log.md       # evolvable 구역 변경 기록
```

**외부 도구 의존성**: MoAI 프레임워크 CLI(내부), `agy`.

---

## 11. `plugins/` — 외부 플러그인 모듈

**책임**: 8개 마켓플레이스에서 설치된 8개 활성 플러그인을 보관한다. 각 플러그인은 추가 스킬, 훅, MCP 서버를 제공한다.

**입력 인터페이스**:
- 플러그인 마켓플레이스 설치 프로세스
- Claude Code 플러그인 런타임

**출력 인터페이스**:
- 추가 스킬 (`claude-mem` 스킬군, `codex:rescue`, `superpowers:*` 등)
- 추가 훅 (`gitkraken-hooks`)
- 추가 MCP 서버 (`gitlab`, `playwright`)

**활성 8개 플러그인**:
| 플러그인 | 제공 기능 |
|----------|----------|
| `claude-mem` | 크로스 세션 퍼시스턴트 메모리 DB + 스킬군 |
| `codex` | Codex CLI MCP + rescue 서브에이전트 스킬 |
| `frontend-design` | 프론트엔드 디자인 특화 스킬 |
| `gitkraken-hooks` | GitKraken 통합 훅 |
| `gitlab` | GitLab API MCP 서버 |
| `playwright` | 브라우저 자동화 테스트 스킬 |
| `rust-analyzer-lsp` | Rust 언어 서버 (moai-lsp 연동) |
| `superpowers` | 서브에이전트 드리븐 개발 스킬군 |

**총 크기**: 약 6107 파일 / 133MB.

**알려진 리스크**: 비활성 플러그인 파일 누적, 정리 정책 ad-hoc.

---

## 12. `scripts/` — 유틸리티 스크립트 모듈

**책임**: 훅 로직과 분리된 독립형 유틸리티 스크립트 82개를 보관한다. 하네스 초기화, 데이터 처리, 진단, RAG 서버 실행 등 다양한 작업을 지원한다.

**입력 인터페이스**:
- 사용자 직접 실행 (Bash 명령)
- 훅 스크립트에서 호출

**출력 인터페이스**:
- 초기화 결과, 진단 보고서, 처리된 데이터 파일

**핵심 파일 (표본)**:
| 파일 | 역할 |
|------|------|
| `package.sh` | 전체 하네스 패키징 |
| `setup.sh` | 하네스 초기화 |
| `run-local-rag.sh` | 로컬 RAG 서버 실행 (Ollama 연동) |
| `failure-forecaster.py` | 실패 예측 분석 |
| `agents/build-agents.sh` | 에이전트 빌드 스크립트 |

**외부 도구 의존성**: `git`, `ollama`, `gh`, `python3`, `bash`.

---

## 13. `self-model/` — 에이전트 행동 모델

**책임**: 53개 에이전트 디렉토리에서 에이전트별 상호작용 패턴과 의사결정 흔적을 누적한다. 현재는 관찰 데이터 수집 단계이며, 미래의 `self-research` 기능(하네스 진화 방향)을 위한 데이터 원천이다.

**입력 인터페이스**:
- `Stop` 훅, `PostToolUse` 훅에서 에이전트 실행 흔적 기록

**출력 인터페이스**:
- 에이전트별 패턴 파일 (미래 self-research 기능에서 활용 예정)
- 현재는 관찰 데이터 누적 역할

**구조**:
```
self-model/
├── {agent-name-1}/    # 에이전트별 디렉토리 (53개)
│   ├── interactions/  # 상호작용 패턴
│   └── decisions/     # 의사결정 흔적
└── ...
```

**외부 도구 의존성**: 없음 (관찰 데이터 저장소).

---

*아키텍처 개요: [overview.md](./overview.md)*
*의존성 그래프: [dependencies.md](./dependencies.md)*
*진입점 목록: [entry-points.md](./entry-points.md)*
*데이터 흐름: [data-flow.md](./data-flow.md)*

Last updated: 2026-05-25
