---
title: "~/.claude — Personal Claude Code Harness"
type: product
version: "1.0"
created: "2026-05-25"
owner: "joo.leonard@gmail.com"
---

# ~/.claude — Personal Claude Code Harness

## 개요

`~/.claude`는 joo.leonard@gmail.com 단독 소유의 **개인 R&D 자가 적응형 Claude Code 하네스**다. 매일의 작업과 실측 피드백을 통해 스스로 진화하는 Hook-Driven Event Mesh 구조 위에, 14개 에이전트(`agents/*.md`)·약 118개 스킬(70 사용자 정의 + 48 MoAI 프레임워크)·87개 최상위 훅이 유기적으로 연결되어 있다. 이 하네스는 일상적인 코딩 세션부터 멀티 프로젝트 관리, 배포 검증, 회고/학습까지 모든 개발 워크플로우를 단일 관찰·자동화 시스템으로 통합한다.

## 타겟 사용자

| 대상 | 설명 |
|------|------|
| **현재 사용자** | joo.leonard@gmail.com — 유일한 사용자이자 시스템 설계자 |
| **미래의 자기 자신** | 하네스가 수집한 intent/, memory/, telemetry/ 기록으로 세션 연속성 확보 |
| **공유 대상** | 없음. 이 시스템은 타인과 공유하거나 일반 배포를 위해 설계되지 않았다 |

개인 환경 종속 구성 요소(`CHEATSHEET.md`, `identity-hub/`, `mcp-needs-auth-cache.json` 등)는 공유 대상 외로 명시적으로 분리된다.

## 핵심 기능

### Hook-Driven Event Mesh
settings.json 훅 레지스트리가 이벤트 버스 역할을 한다. `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop` 이벤트에 95개 훅이 구독자로 연결되어 자동으로 실행된다. 훅은 Bash(.sh)와 Python(.py)으로 구현되며 병렬 실행이 기본이다.

### Multi-Agent Orchestration
P0-P6 우선순위 라우팅 결정표(CLAUDE.md)에 따라 14개 특화 에이전트로 작업을 위임한다. dev-lead가 오케스트레이터 역할을 수행하며, 필요 시 병렬 에이전트 실행을 통해 처리량을 극대화한다. (`agents/` 14개는 활성 정의이고, `agents-src/` 13개는 빌드 소스 원본)

### Skill Auto-Loading
스킬 YAML frontmatter 기반으로 컨텍스트에 맞는 스킬이 자동 로드된다. 두 경로에 분산: `.claude/skills/` 70개 사용자 정의 + `.claude/.claude/skills/` 48개 MoAI 프레임워크. 키워드 트리거 방식으로 필요한 워크플로우 문서(16개)도 조건부 로드된다.

### Persistent Memory
세션 간 연속성은 다음 저장소로 유지된다:
- `intent/{project-hash}/` — 13개 프로젝트 해시별 의도 디렉토리
- `memory/MEMORY.md` + `memory/lessons.md` — 글로벌 기억 인덱스 (2개 파일)
- `cache/md-live/suggestion-outcomes.jsonl` — 라우팅 제안 채택률 실측 로그
- `telemetry/`, `transcripts/`, `plans/` — 세션 흔적 보존

### MCP Integration
8개 MCP 서버(context7, sequential-thinking, moai-lsp, codex-cli, local-rag, gitlab 외)가 외부 도구와 Claude Code를 연결한다. 로컬 RAG(local-rag)는 leonard.local:11434 Ollama 서버와 통합된다.

### Continuous Self-Tuning
`suggestion-outcomes.jsonl` 실측 데이터(16건 분석 기록 존재)로 라우팅 결정표가 지속적으로 정정된다. 최근 사례: P5 frontend 추천 채택률 0/15(0%) 확인 후 "불명확 시 현재 호출 유지"로 규칙 정정(2026-05-21). 이 하네스는 사용하면 할수록 더 정확해지는 자기 교정 시스템이다.

## 진화 방향

인터뷰 Round 1에서 명시된 네 가지 진화 방향:

| 방향 | 설명 |
|------|------|
| **autoresearch** | 하네스가 스스로 기술 조사를 수행하고 학습 결과를 내재화 |
| **R2-D2-absorbed MoAI** | MoAI 프레임워크를 하네스 내부로 흡수하여 단일 오케스트레이터 체계 완성 |
| **evaluator-active** | GAN Loop 방식의 자기 평가 루프 — 빌더와 평가자가 반복 협상하여 품질 수렴 |
| **self-research** | 하네스 자신의 동작 패턴을 관찰·분석하여 자기 최적화 제안 생성 |

현재 하네스는 이 방향으로 **점진적으로 이행 중**이며 완성 상태가 아니다.

## 사용 사례

| 사례 | 관련 컴포넌트 |
|------|-------------|
| 일상 코딩 세션 | SessionStart 훅, intent 로드, gemini-prescan-enforcer |
| 멀티 프로젝트 관리 | 16개 project hash dirs, session-env/, project-status 명령 |
| SSO / Identity Hub 디버깅 | workflows/sso.md, check-user, jwt-debug, sso-flow 명령 |
| 배포 검증 | safe-deploy, deploy-status 명령, 🔴 위험도 사람 승인 훅 |
| 백로그 운영 | backlog 명령, @dev backlog 태스크 관리, backlog-policy.md |
| 회고 / 학습 | /retro, /decisions 스킬, growth.md, decision-capture 훅 (`cache/md-live/` 결정 캐시 사용) |
| 보고서 생성 | receipt-report, receipt-pdf, write-daily-report 스킬 |

## Out of Scope

이 하네스가 의도적으로 지원하지 않는 항목:

- **타인 공유** — 이 시스템은 개인 관찰·자동화 도구이며 팀 배포 대상이 아니다
- **일반 배포** — 패키징, 설치 가이드, 버전 관리 릴리스 계획 없음
- **구조적 공유** — MoAI 형태로도 타인에게 제공하지 않음 (인터뷰 Round 2)
- **CI/CD 파이프라인** — 의도적 부재. hook 기반 self-validation으로 대체 (인터뷰 Round 2)
- **개인 환경 종속 구성요소의 이식** — `CHEATSHEET.md`, `identity-hub/`, `mcp-needs-auth-cache.json` 등

## 측정 지표

하네스는 자기 관찰 도구로서 다음 메트릭을 수집한다:

| 지표 | 수집 위치 | 용도 |
|------|----------|------|
| 라우팅 제안 채택률 | `cache/md-live/suggestion-outcomes.jsonl` | P5 규칙 자기 교정 |
| 훅 실행 결과 | `cache/md-live/hook-outcomes.jsonl` | 훅 노이즈 감지 및 제거 |
| 결정 이력 | `cache/md-live/` (decision-capture 산출물) | 회고(/retro) 및 패턴 분석 |
| 파이프라인 메트릭 | `telemetry/` | 에이전트 실행 시간 추적 |
| 세션 전사 | `transcripts/` | 컨텍스트 재구성 |
| 일일 학습 | `memory/lessons.md` | 도메인별 교훈 누적 |

이 지표들은 하네스를 개선하는 피드백 루프의 원천 데이터다.

---

Last updated: 2026-05-25
