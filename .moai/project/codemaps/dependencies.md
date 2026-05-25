---
title: "의존성 그래프"
type: codemap
subtype: dependencies
version: "1.0"
created: "2026-05-25"
---

# 의존성 그래프

> 내부 모듈 간 의존성과 외부 도구·서비스 의존성을 서술한다.
> 모듈별 상세 인터페이스는 [modules.md](./modules.md) 참조.
> MCP 서버 상세는 [../tech.md MCP 서버 표](../tech.md) 참조.

---

## 내부 모듈 의존성

```mermaid
graph LR
    subgraph 설정 파일
        SJ[settings.json\n이벤트 버스 + 훅 레지스트리]
        MCJ[.mcp.json\nMCP 서버 3종]
        CL[CLAUDE.md\nP0-P6 라우팅 테이블]
    end

    subgraph 이벤트 처리
        HK[hooks/\n87개 최상위 훅]
    end

    subgraph 지식·능력
        SK[skills/\n70개 사용자 정의]
        SKF[.claude/skills/\n48개 MoAI 프레임워크]
        WF[workflows/\n16개 조건부 문서]
        RU[rules/\n34개 헌법 규칙]
    end

    subgraph 실행
        AG[agents/\n14개 에이전트]
        CMD[commands/\n14개 슬래시 명령]
    end

    subgraph 저장소
        INT[intent/\n13 project hashes]
        MEM[memory/\n2개 글로벌 기억]
        CACHE[cache/\n실측+RAG+스냅샷]
        TEL[telemetry/]
        SMOD[self-model/\n53개 디렉토리]
    end

    subgraph MoAI 통합
        MOAI[.moai/\nmanifest + 28 YAML]
        PLG[plugins/\n8개 활성]
    end

    SJ -->|이벤트 발화 → 훅 실행| HK
    MCJ -->|MCP 서버 등록| AG
    CL -->|라우팅 결정| AG

    HK -->|키워드 감지 신호| SK
    HK -->|학습 기록| MEM
    HK -->|실측 기록| CACHE
    HK -->|메트릭| TEL
    HK -->|행동 흔적| SMOD
    HK -->|프로젝트 식별| INT

    SK -->|컨텍스트 주입| AG
    SKF -->|프레임워크 스킬 주입| AG
    WF -->|조건부 절차 주입| AG
    RU -->|행동 제약| AG

    CMD -->|Skill() 위임| SK
    CMD -->|Skill() 위임| SKF

    AG -->|SPEC 조회| MOAI
    AG -->|도구 실행| HK

    MOAI -->|브랜드·품질 기준| AG
    MOAI -->|스킬 레지스트리| SKF

    PLG -->|추가 스킬| SK
    PLG -->|추가 훅| HK

    CACHE -->|P5 피드백| CL
    INT -->|프로젝트 컨텍스트| AG
    MEM -->|과거 학습| AG
```

**핵심 의존 관계 요약**:

- `settings.json`은 모든 훅 실행의 진입점이다. 이 파일 없이는 자동화가 작동하지 않는다.
- `CLAUDE.md`는 라우팅의 진입점이다. P0-P6 테이블이 에이전트 위임의 원천이다.
- `.mcp.json` + `settings.json`은 MCP의 이중 진입점이다. 두 파일에 걸쳐 6개 MCP 서버가 등록된다.
- `cache/md-live/suggestion-outcomes.jsonl`은 `CLAUDE.md`로 역방향 피드백을 제공하는 자기 교정 루프다.

---

## 외부 CLI 의존성

| CLI 도구 | 역할 | 사용 위치 | Fallback 정책 |
|----------|------|----------|--------------|
| `gh` | GitHub PR 생성, 이슈 조회, CI 상태 | hooks/, commands/, agents/ | 없음. gh 미설치 시 해당 기능 불가 |
| `git` | 버전 관리, 프로젝트 식별(remote URL 해시) | session-start-router.sh, hooks/ | 없음. git 없이 프로젝트 식별 불가 |
| `agy` (Antigravity CLI) | 멀티 에이전트 디스패치, Gemini 모델 접근, Phase 0 스캔 | gemini-prescan-enforcer, ask-gemini 스킬 | 🔴 agy 외부 서비스 중단 시 prescan-enforcer 훅 실패 → 코드 수정 블로킹 가능 |
| `codex` | OpenAI Codex CLI 구현·검증·리뷰 | codex-cli MCP, ask-codex 스킬 | codex:rescue 불가, 세컨드 오피니언 없음 |
| `ollama` | 로컬 LLM 서버 (leonard.local:11434) | ask-ollama 스킬, local-rag MCP, Stop 훅 학습 캡처 | ollama 서버 다운 시 학습 캡처·RAG 검색 불가 |
| `jules` | 백그라운드 작업 (테스트/문서/PR) | agents/ (Jules 에이전트) | 없음. Jules 서비스 종속 |
| `gemini` | Google Gemini CLI | 비활성화 (agy로 대체됨, f109710) | — (deprecated) |

**CLI 의존성 위험도**:
- 🔴 `agy`: 외부 서비스 의존. 중단 시 `gemini-prescan-enforcer` 훅이 코드 수정을 블로킹할 수 있다. 가장 높은 가용성 리스크.
- 🟡 `ollama`: 로컬 서버지만 `leonard.local:11434` 호스트에 종속. Stop 훅 학습 캡처 여러 곳에서 의존.
- 🟢 `gh`, `git`: 표준 CLI. 설치 전제가 합리적.

---

## MCP 서버 의존성

총 6개 MCP 서버. `.mcp.json`(3개)과 `settings.json`(3개)에 분산 등록.

| 이름 | 등록 위치 | transport | 주요 용도 | 가용성 리스크 |
|------|----------|-----------|----------|-------------|
| `context7` | `.mcp.json` | stdio | 공식 라이브러리 문서 JIT 로드 | 외부 API — 네트워크 장애 시 문서 로드 불가 |
| `sequential-thinking` | `.mcp.json` | stdio | 복잡한 추론 체인 지원 | 외부 서비스 의존 |
| `moai-lsp` | `.mcp.json` | stdio | 16개 언어 서버 프로토콜 (powernap v0.1.4) | 로컬 빌드. 상대적으로 안정 |
| `codex-cli` | `settings.json` | stdio | Codex 병렬 구현·검증·리뷰 | OpenAI API 의존 |
| `local-rag` | `settings.json` | stdio | 로컬 RAG (Ollama 연동, leonard.local:11434) | ollama 서버 가용성에 종속 |
| `gitlab` | `settings.json` | stdio | GitLab API 접근 | GitLab 서비스 및 인증 토큰 의존 |

**moai-lsp 상세**: `github.com/charmbracelet/x/powernap v0.1.4` 기반. 16개 언어 서버 지원 (gopls, pyright, tsserver 등). 상세: `.claude/.claude/rules/moai/core/lsp-client.md`

**MCP 이중 진입점 구조**:
```
.mcp.json          → Claude Code 프로젝트 범위 MCP (context7, sequential-thinking, moai-lsp)
settings.json      → 글로벌 범위 MCP (codex-cli, local-rag, gitlab)
plugins/ (자동)    → 플러그인 관리 MCP (gitlab, playwright 등 중복 가능)
```

**주의**: MCP 서버가 `.mcp.json`과 `settings.json` 양쪽에 등록되면 중복이 발생할 수 있다. `moai doctor`(v2.1.110+)가 중복을 감지하고 경고한다.

---

## 로컬 LLM 의존성

Ollama 서버(`leonard.local:11434`)에서 운영되는 모델 라우팅:

| 모델 | 라우팅 조건 | 접근 스킬/훅 |
|------|------------|------------|
| `qwen2.5-coder:14b` | 코딩 관련 질의 (코딩 키워드 감지) | `ask-ollama` |
| `qwen3.5:9b` | 한국어 / 일반 질의 (기본 라우팅) | `ask-ollama` |
| `gemma4:e4b` | 빠른 단순 질의 (속도 우선) | `ask-ollama`, `ask-gemma` |
| `gemma4:26b` | 깊은 추론 필요 | `ask-ollama`, `ask-gemma` |

모델 라우팅은 `ask-ollama` 스킬이 키워드 기반으로 처리한다. 사용자가 모델을 명시하면 명시된 모델이 우선 적용된다.

**Stop 훅 로컬 LLM 사용**:
- `gemma-session-stop-unified` — 세션 종합 학습 캡처 (gemma4 모델 사용)
- `qwen-learning-capture` — Qwen 기반 학습 추출
- `qwen-decision-capture` — Qwen 기반 결정 캡처

---

## 외부 LLM 의존성

| LLM 서비스 | 접근 방법 | 용도 |
|-----------|----------|------|
| Claude (Anthropic) | Claude Code 자체 | 메인 오케스트레이터·에이전트 실행 |
| Gemini (Google) | `agy` CLI (Antigravity) | Phase 0 1M 토큰 스캔, 테스트 생성, 3중 리뷰 |
| OpenAI Codex | `codex` CLI + `codex-cli` MCP | 병렬 구현, 세컨드 오피니언, rescue |
| 로컬 Ollama | `ollama` (leonard.local:11434) | 학습 캡처, RAG 임베딩, 로컬 질의 |

**LLM 역할 분담 원칙** (CLAUDE.md에서):
- Claude Code: 판단·채택·최종 구현·의사결정
- Codex MCP: 병렬 구현·검증·리뷰·세컨드 오피니언
- Gemini (agy): Phase 0 스캔(1M토큰)·테스트 생성·3중 리뷰·최종 통합 검증
- Antigravity: 멀티 에이전트 디스패치
- Jules: 백그라운드 (테스트/문서/PR)

---

## Plugin 마켓플레이스 의존성

8개 마켓플레이스에서 8개 플러그인이 설치되어 있다.

| 마켓플레이스 | 활성 플러그인 |
|-----------|------------|
| `claude-code-plugins` | claude-mem |
| `openai-codex` | codex |
| `superpowers-marketplace` | superpowers |
| `gitkraken` | gitkraken-hooks |
| `claude-plugins-official` | gitlab, playwright |
| `thedotmack` | frontend-design |
| `ouroboros` | rust-analyzer-lsp |
| `anthropic-agent-skills` | (추가 스킬 포함) |

**플러그인 의존성 특성**:
- 각 플러그인은 독립적으로 설치되며 Claude Code 플러그인 런타임에 의존한다.
- 플러그인이 제공하는 MCP 서버(`gitlab`, `playwright`)는 `settings.json`의 동일 이름 서버와 중복될 수 있다.
- 플러그인이 제공하는 스킬은 `claude-mem:*`, `codex:*`, `superpowers:*` 등 네임스페이스로 구분된다.

---

## 의존성 리스크 요약

| 리스크 | 위치 | 영향 | 현황 |
|--------|------|------|------|
| 🔴 **agy 외부 서비스** | `gemini-prescan-enforcer`, `ask-gemini` | agy 중단 시 코드 수정 블로킹 가능 | 미해결. Fallback 없음 |
| 🔴 **RAG 임베딩 stale** | `cache/` (795MB) | 코드 변경 후 재색인 없이 stale 상태 유지 → 검색 정확도 저하 | 정리 정책 ad-hoc |
| 🟡 **ollama 로컬 서버** | Stop 훅 학습 캡처, local-rag MCP | 서버 다운 시 학습 캡처·RAG 불가 | 로컬 서버로 외부보다 안정하나 호스트 의존 |
| 🟡 **plugins 파일 누적** | `plugins/` (6107 파일 / 133MB) | 디스크 사용량 증가, 비활성 플러그인 포함 가능 | 정리 정책 ad-hoc |
| 🟡 **MCP 중복 등록** | `.mcp.json` + `settings.json` + `plugins/` | 동일 서버 중복 시 충돌 가능 | `moai doctor`로 감지 가능 (v2.1.110+) |
| 🟢 **cache 용량** | `cache/` (795MB) | 디스크 사용량 증가 | 성능 영향 없으나 정리 필요 |

---

*모듈 인터페이스: [modules.md](./modules.md)*
*아키텍처 개요: [overview.md](./overview.md)*
*진입점: [entry-points.md](./entry-points.md)*
*데이터 흐름: [data-flow.md](./data-flow.md)*

Last updated: 2026-05-25
