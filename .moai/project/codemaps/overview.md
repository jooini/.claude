---
title: "~/.claude 아키텍처 개요"
type: codemap
subtype: overview
version: "1.0"
created: "2026-05-25"
---

# ~/.claude 아키텍처 개요

> 본 문서는 `/Users/leonard/.claude` 개인 Claude Code 하네스의 최상위 아키텍처를 서술한다.
> 모듈별 상세 인터페이스는 [modules.md](./modules.md), 의존성 그래프는 [dependencies.md](./dependencies.md) 참조.

---

## 시스템 정체성 — Hook-Driven Event Mesh

`~/.claude`는 **개인 R&D 자가 적응형 Claude Code 하네스**다. 단일 사용자(`joo.leonard@gmail.com`)를 위한 관찰·자동화 도구이며, 타인 공유 또는 일반 배포를 위해 설계되지 않았다.

이 시스템의 핵심 아키텍처 패턴은 **Hook-Driven Event Mesh**다. `settings.json` 훅 레지스트리가 이벤트 버스 역할을 수행하고, 9개 이벤트 타입(`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `PreCompact`, `Notification`, `TaskCreate`, `TaskUpdate`)에 87개 최상위 훅이 구독자로 연결된다. 모든 자동화는 이 이벤트 흐름 위에서 실행되며, 하네스 자체는 응용 프로그램 코드가 아니라 **오케스트레이션·설정·자동화 도구**다.

사용하면 할수록 더 정확해지는 **자기 교정 시스템**이기도 하다. `cache/md-live/suggestion-outcomes.jsonl`에 실측 데이터가 누적되고, 이 데이터로 P0-P6 라우팅 결정표(CLAUDE.md)가 주기적으로 정정된다. 최근 정정 사례(2026-05-21): P5 frontend 추천 채택률 0/15(0%) 확인 후 "불명확 시 현재 호출 유지" 규칙 추가.

---

## 6대 핵심 서브시스템

### 1. Hooks (이벤트 자동화)

`hooks/` 디렉토리에 87개 최상위 훅(Bash `.sh` + Python `.py`)이 위치한다. `_archive/`, `_disabled/`, `_lib/` 포함 시 총 108개. `settings.json`의 훅 레지스트리에 이벤트별로 등록되며, Claude Code 런타임이 해당 이벤트 발생 시 자동으로 실행한다. 병렬 실행이 기본이며, `Stop` 이벤트에는 최대 12개 훅이 동시에 실행된다. 보안 훅(`commit-no-coauthor`, `dangerous-command-detect`, `gemini-prescan-enforcer`), 학습 캡처 훅(`qwen-learning-capture`, `daily-learning-capture`), 메트릭 훅(`pipeline-metrics-log`, `suggestion-outcome-track`) 등 역할별로 세분화되어 있다.

### 2. Skills (능력 자동 로드)

두 개의 스킬 경로가 병존한다. `.claude/skills/`(사용자 정의 70개)와 `.claude/.claude/skills/`(MoAI 프레임워크 48개), 합계 약 118개. 각 스킬은 YAML frontmatter에 트리거 키워드를 선언하고, `UserPromptSubmit` 훅의 `user-prompt-router.sh`가 사용자 발화에서 키워드를 감지하면 해당 스킬이 에이전트 컨텍스트에 자동으로 주입된다. 슬래시 명령(`/forecast`, `/debug`, `/qq` 등)으로 직접 호출도 가능하다.

### 3. Agents (특화 위임)

`agents/` 디렉토리에 14개 특화 에이전트 정의가 존재한다. `agents-src/` 13개 소스 원본을 `build-agents.sh`로 빌드해 생성한다. `CLAUDE.md`의 P0-P6 우선순위 라우팅 결정표에 따라 사용자 발화가 적절한 에이전트로 위임된다. `dev-lead`가 오케스트레이터 역할을 수행하며, `backend-developer`, `frontend-developer`, `code-reviewer`, `code-tester` 등 도메인 특화 에이전트가 병렬로 실행될 수 있다.

### 4. Commands (슬래시 라우터)

`commands/` 디렉토리에 14개 슬래시 명령 정의가 있다. 모든 명령 파일은 20줄 이하의 얇은 라우팅 래퍼(Thin Command Pattern)로, 로직 없이 `Skill()` 호출 또는 에이전트 위임만 수행한다. 사용자가 `/retro`, `/backlog`, `/project-status` 등을 입력하면 이 파일이 해당 스킬이나 에이전트로 위임한다. `/moai` 명령은 MoAI 통합 오케스트레이터(`moai` 스킬)로 라우팅된다.

### 5. Workflows (조건부 로드 절차)

`workflows/` 디렉토리에 16개 워크플로우 문서가 있다. CLAUDE.md의 키워드 트리거 테이블에 따라 관련 워크플로우 문서가 조건부로 로드된다. 예를 들어 "파이프라인" 키워드가 감지되면 `workflows/pipeline.md`가 로드되고, "Obsidian" 키워드에는 `workflows/docs-convention.md`가 로드된다. 도메인별 상세 절차를 CLAUDE.md 본문에서 분리하여 토큰 효율을 높이는 구조다.

### 6. Rules (헌법)

`.claude/.claude/rules/` 디렉토리에 34개 헌법적 규칙 파일이 4개 하위 네임스페이스(moai/design, moai/core, moai/development, moai/workflow)로 구성된다. 세션 시작 시 프로젝트 인스트럭션으로 자동 로드되어 모든 에이전트의 행동 제약 조건을 형성한다. `design/constitution.md`의 FROZEN 존 규칙은 어떤 에이전트도 수정할 수 없다.

---

## 자가 진화 메커니즘

이 하네스는 4개의 데이터 루프를 통해 스스로 진화한다.

**suggestion-outcome 루프**: `PostToolUse` 훅이 에이전트 라우팅 제안 이벤트를 감지하면 `suggestion-outcome-track` 훅이 채택 여부를 `cache/md-live/suggestion-outcomes.jsonl`에 기록한다. 누적 데이터는 CLAUDE.md P5 규칙을 정정하는 데 사용된다.

**hook-outcome 루프**: 각 훅 실행 결과가 `cache/md-live/hook-outcomes.jsonl`에 기록된다. 이 데이터로 훅 노이즈를 감지하고 불필요한 훅을 비활성화한다(최근 사례: c267d50 커밋에서 노이즈 훅 정리 수행).

**decision-capture 루프**: `PostToolUse(Agent)` 이벤트에서 비동기로 결정 이벤트가 `cache/md-live/`에 기록된다. `/retro` 스킬이 이 데이터를 조회하여 패턴 분석·회고를 생성한다.

**self-model 루프**: `self-model/` 디렉토리에 53개 에이전트 디렉토리가 있으며, 에이전트별 상호작용 패턴과 의사결정 흔적이 누적된다. 미래의 `self-research` 기능(진화 방향)을 위한 관찰 데이터 원천이다.

---

## 통합 레이어

**`.moai/` 통합**: `manifest.json`(2958줄 SHA256 템플릿 레지스트리)과 28개 YAML 설정 섹션이 MoAI 프레임워크와의 통합 지점을 형성한다. `/moai` 명령군, `moai-*` 스킬이 이 레이어를 통해 에이전트 스폰·품질 게이트·SPEC 관리를 수행한다.

**MCP 레이어**: 6개 MCP 서버(`.mcp.json` 3개 + `settings.json` 3개)가 외부 도구를 Claude Code에 연결한다. `context7`(공식 문서), `sequential-thinking`(추론 체인), `moai-lsp`(언어 서버), `codex-cli`(Codex), `local-rag`(로컬 RAG), `gitlab`(GitLab API). (상세는 [tech.md MCP 서버 표](../tech.md) 참조)

**plugins/ 레이어**: 8개 활성 플러그인이 8개 마켓플레이스에서 관리된다. `claude-mem`(크로스 세션 메모리), `codex`(Codex rescue), `superpowers`(병렬 에이전트) 등이 추가 스킬·훅·MCP를 제공한다. 총 약 6107 파일 / 133MB — 정리 정책 ad-hoc.

**intent/ 레이어**: 13개 프로젝트 해시 디렉토리가 git remote URL 기반으로 프로젝트를 식별한다. `SessionStart` 훅이 현재 git 저장소의 remote URL을 해시화하여 해당 `intent/{hash}/` 디렉토리를 로드하고, 프로젝트별 의도·컨텍스트를 에이전트에 주입한다.

**memory/ 레이어**: `MEMORY.md`(에이전트 기억 인덱스)와 `lessons.md`(도메인 교훈)가 글로벌 기억 저장소를 구성한다. `Stop` 훅의 학습 캡처 스크립트들이 세션 종료 시 이 파일들을 업데이트한다.

**cache/ 레이어**: 1291개 이상의 캐시 항목(약 795MB)이 RAG 임베딩, 실측 데이터, 세션 스냅샷을 저장한다. `cache/md-live/`가 핵심 실측 데이터(`suggestion-outcomes.jsonl`, `hook-outcomes.jsonl`, decision-capture 산출물)를 보관한다.

---

## 책임 경계 다이어그램

```mermaid
graph TD
    subgraph 진입점
        U[사용자 발화]
        SC[슬래시 명령]
        SE[SessionStart 이벤트]
    end

    subgraph 이벤트 버스
        SJ[settings.json\n훅 레지스트리]
        CLAUDE[CLAUDE.md\nP0-P6 라우팅 테이블]
    end

    subgraph 서브시스템
        HK[hooks/\n87개 최상위 훅]
        SK[skills/\n~118개 스킬]
        AG[agents/\n14개 에이전트]
        CMD[commands/\n14개 슬래시 명령]
        WF[workflows/\n16개 조건부 문서]
        RU[rules/\n34개 헌법 규칙]
    end

    subgraph 통합 레이어
        MOAI[.moai/\nMoAI 통합]
        MCP[MCP 서버 6종]
        PLG[plugins/ 8개]
    end

    subgraph 영속 저장소
        INT[intent/\n13개 프로젝트 해시]
        MEM[memory/\n2개 글로벌 기억]
        CACHE[cache/\n실측+RAG+스냅샷]
        TEL[telemetry/\n파이프라인 메트릭]
        SMOD[self-model/\n53개 에이전트 모델]
    end

    SE -->|이벤트 발생| SJ
    U -->|발화 입력| SJ
    SC -->|명령 입력| CMD

    SJ -->|UserPromptSubmit| HK
    SJ -->|PreToolUse/PostToolUse/Stop| HK
    HK -->|키워드 감지| SK
    HK -->|라우팅 결정| CLAUDE
    CLAUDE -->|에이전트 위임| AG

    CMD -->|Skill() 호출| SK
    SK -->|컨텍스트 주입| AG
    WF -->|조건부 로드| AG
    RU -->|행동 제약| AG

    AG -->|도구 실행| MCP
    AG -->|SPEC 조회| MOAI
    MOAI -->|브랜드·품질 기준| AG

    HK -->|학습 기록| MEM
    HK -->|실측 기록| CACHE
    HK -->|메트릭| TEL
    HK -->|행동 흔적| SMOD
    SJ -->|프로젝트 식별| INT
    INT -->|컨텍스트| AG

    PLG -->|추가 스킬·훅| HK
    PLG -->|추가 스킬| SK

    CACHE -->|피드백| CLAUDE
```

---

## 핵심 설계 결정

**Frozen Zone (의도적 불변성)**: `.claude/.claude/rules/moai/design/constitution.md`의 FROZEN 존 규칙은 에이전트 또는 학습 시스템이 수정할 수 없다. 설계 헌법·안전 아키텍처·GAN Loop 계약이 여기에 속한다. 이 규칙들은 시스템이 자기 수정을 통해 핵심 원칙을 훼손하는 것을 방지한다.

**라이브 P5 튜닝 (실측 기반 자기 교정)**: P5 라우팅 규칙은 `suggestion-outcomes.jsonl` 실측 데이터에 따라 지속적으로 정정된다. 이것은 안정성과 정확성 사이의 의도적 균형이다. 고정 규칙보다 느리게 수렴하지만 실제 사용 패턴에 더 정확히 적응한다.

**CI 의도적 부재**: 단위·통합·E2E 테스트 자동화 파이프라인이 없다. 대신 87개 훅 기반 self-validation, suggestion-outcome 추적, agy prescan, codex rescue 자동 트리거로 대체한다. 이는 개인 R&D 도구에서 CI 오버헤드를 피하는 의도적 선택이다(인터뷰 Round 2).

**이중 스킬 경로**: `.claude/skills/`(사용자 정의)와 `.claude/.claude/skills/`(MoAI 프레임워크)가 병존한다. 네임스페이스 충돌 가능성이 알려진 리스크로 인식되어 있으나, MoAI 프레임워크 스킬과 사용자 정의 스킬의 역할을 명확히 분리하는 장점이 있다.

**에이전트 빌드 두 단계**: `agents-src/`(소스 원본)와 `agents/`(빌드 결과)를 분리한다. 빌드 과정에서 프롬프트 뉘앙스 손실이 발생할 수 있어 `agents-src`를 정본으로 유지한다.

---

*상세 모듈 인터페이스: [modules.md](./modules.md)*
*의존성 그래프: [dependencies.md](./dependencies.md)*
*진입점 목록: [entry-points.md](./entry-points.md)*
*데이터 흐름: [data-flow.md](./data-flow.md)*

Last updated: 2026-05-25
