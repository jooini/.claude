---
title: "기술 스택 및 환경"
type: tech
version: "1.0"
created: "2026-05-25"
---

# 기술 스택 및 환경

## 주력 언어

이 하네스는 응용 프로그램 코드가 아니라 **자동화·설정·오케스트레이션** 도구다. 언어 선택도 그에 따른다.

| 언어 / 형식 | 용도 | 주요 위치 |
|------------|------|----------|
| **Bash (.sh)** | 훅 구현, 유틸리티 스크립트, 빌드 도구 | `hooks/`, `scripts/`, `agents-src/` |
| **Python (.py)** | 복잡한 훅 로직, 데이터 처리 | `hooks/` (일부), `scripts/` |
| **Markdown + YAML frontmatter** | 에이전트 정의, 스킬 정의, 워크플로우 문서 | `agents/`, `skills/`, `commands/`, `workflows/` |
| **JSON** | 설정 파일, 캐시, 텔레메트리 데이터 | `settings.json`, `.mcp.json`, `cache/`, `telemetry/` |
| **YAML** | MoAI 설정 섹션, 환경 변수, 프로젝트 설정 | `.moai/config/sections/` |

## 외부 CLI 의존성

| CLI 도구 | 역할 | 현황 |
|----------|------|------|
| `gh` | GitHub PR 생성, 이슈 조회, CI 상태 확인 | 활성 |
| `git` | 버전 관리, 프로젝트 식별(remote URL 기반) | 활성 |
| `ollama` | 로컬 LLM 서버 (leonard.local:11434) | 활성 |
| `agy` (Antigravity CLI) | 멀티 에이전트 디스패치, Gemini 모델 접근 | 활성 (f109710에서 `gemini` → `agy` 마이그레이션 완료) |
| `codex` | OpenAI Codex CLI (MCP 연동) | 활성 |
| `gemini` | Google Gemini CLI | 비활성화 (agy로 대체, deprecated) |
| `jules` | 백그라운드 작업 (테스트/문서/PR) | 활성 (Jules 에이전트) |

## MCP 서버

총 8개 MCP 서버가 운영된다. `.mcp.json`에 3종, `settings.json`에 별도 등록.

| 이름 | 등록 위치 | transport | scope | 주요 용도 |
|------|----------|-----------|-------|----------|
| `context7` | `.mcp.json` | stdio | 글로벌 | 공식 라이브러리 문서 접근 (JIT 문서 로드) |
| `sequential-thinking` | `.mcp.json` | stdio | 글로벌 | 복잡한 추론 체인 지원 |
| `moai-lsp` | `.mcp.json` | stdio | 글로벌 | 언어 서버 프로토콜 (16개 언어 지원, powernap v0.1.4 기반) |
| `codex-cli` | `settings.json` | stdio | 글로벌 | OpenAI Codex 병렬 구현·검증·리뷰 |
| `local-rag` | `settings.json` | stdio | 글로벌 | 로컬 RAG (Ollama 연동, leonard.local:11434) |
| `gitlab` | `settings.json` | stdio | 글로벌 | GitLab API 접근 |
| (plugin-managed) | 플러그인 자동 관리 | 다양 | 다양 | 플러그인별 MCP 제공 |

**moai-lsp 상세**: `github.com/charmbracelet/x/powernap v0.1.4` 기반. charmbracelet/crush 검증 완료. 16개 언어 서버 지원 (gopls, pyright, tsserver 등). 상세: `.claude/rules/moai/core/lsp-client.md`

## 활성 플러그인

| 플러그인 | 주요 기능 |
|----------|----------|
| `claude-mem` | 크로스 세션 퍼시스턴트 메모리 데이터베이스 |
| `codex` | Codex CLI MCP 연동 + rescue 서브에이전트 |
| `frontend-design` | 프론트엔드 디자인 특화 스킬 |
| `gitkraken-hooks` | GitKraken 통합 훅 |
| `gitlab` | GitLab API MCP 서버 |
| `playwright` | 브라우저 자동화 테스트 |
| `rust-analyzer-lsp` | Rust 언어 서버 (moai-lsp 연동) |
| `superpowers` | 서브에이전트 드리븐 개발, 병렬 에이전트 디스패치 |

### 플러그인 마켓플레이스 (8종)

`claude-code-plugins`, `claude-plugins-official`, `openai-codex`, `thedotmack`, `gitkraken`, `ouroboros`, `anthropic-agent-skills`, `superpowers-marketplace`

총 약 6107 파일 / 133MB (활성 8 플러그인 + cache/data/repos 누적) — 정리 정책 ad-hoc (알려진 리스크).

## 로컬 LLM 라우팅

Ollama 서버(`leonard.local:11434`)에서 다음 모델이 운영된다.

| 모델 | 라우팅 조건 | 접근 스킬 |
|------|------------|----------|
| `qwen2.5-coder:14b` | 코딩 관련 질의 | `ask-ollama` (코딩 키워드 감지) |
| `qwen3.5:9b` | 한국어 / 일반 질의 | `ask-ollama` (기본 라우팅) |
| `gemma4:e4b` | 빠른 단순 질의 | `ask-ollama` (속도 우선 키워드) |
| `gemma4:26b` | 깊은 추론 필요 | `ask-ollama` (추론 키워드), `ask-gemma` |

모델 자동 라우팅은 `ask-ollama` 스킬이 키워드 기반으로 처리한다. 사용자가 모델을 명시하면 명시된 모델 우선.

외부 LLM 라우팅:
- `agy` (Antigravity) — Phase 0 1M 토큰 스캔, 테스트 생성, 3중 리뷰 (`ask-gemini` 스킬)
- `codex` MCP — 병렬 구현 + 세컨드 오피니언 (`ask-codex` 스킬)

## 환경 변수

`settings.json` 및 훅 스크립트를 통해 관리되는 주요 환경 변수:

| 변수 | 값 / 설명 |
|------|----------|
| `GEMINI_CLI` | `agy` — Antigravity CLI를 Gemini 대체로 사용 |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` — 팀 에이전트 모드 활성화 |
| `CLAUDE_ENV_FILE` | 세션별 환경 변수 주입 파일 (v2.1.111+ 지원) |
| Ollama 서버 주소 | `leonard.local:11434` — ask-ollama 스킬 하드코딩 참조 |

## 보안 / 안전 훅

코드 변경·실행·배포 시 자동으로 개입하는 안전 계층:

| 훅 이름 | 이벤트 | 기능 |
|--------|--------|------|
| `commit-no-coauthor` | PreToolUse(Bash) — git commit | Co-Authored-By 태그 포함 커밋 자동 차단 |
| `dangerous-command-detect` | PostToolUse(Bash) | 위험 명령(rm -rf, force push 등) 실행 후 감지 및 경고 |
| `gemini-prescan-enforcer` | PreToolUse(Edit|Write) | 코드 수정 전 agy(Gemini) Phase 0 스캔 강제 실행 |
| `mcp-healthcheck` | SessionStart | MCP 서버 가용성 사전 점검 |
| `error-codex-remind` | PostToolUse(Bash) — 오류 시 | 3회 실패 시 codex:rescue 트리거 안내 |
| `dependency-change-detect` | PreToolUse(Edit|Write) | 의존성 파일 변경 감지 → 자동 스캔 요청 |

## 테스트 / CI 정책

**이 하네스에는 CI/CD 파이프라인이 의도적으로 부재한다** (인터뷰 Round 2 명시).

대신 다음으로 대체된다:

| 대체 메커니즘 | 설명 |
|-------------|------|
| **Hook 기반 self-validation** | 87개 최상위 훅이 실행 전·후 자동 검증 역할 수행 (108개 — _archive/_disabled/_lib 포함) |
| **suggestion-outcome 추적** | 라우팅 제안 채택률 실측으로 규칙 자기 교정 |
| **hook-outcomes 모니터링** | 훅 실행 결과 기록으로 훅 품질 관리 |
| **agy prescan** | 코드 수정 시 Gemini 기반 사전 스캔 |
| **codex rescue** | 3회 연속 실패 시 Codex 구조 요청 자동 트리거 |

단위 테스트, 통합 테스트, E2E 테스트 자동화는 현재 운영되지 않으며, 이는 의도적 결정이다.

## 데이터 저장 위치

| 저장소 | 경로 | 내용 |
|--------|------|------|
| RAG 임베딩 캐시 | `cache/` (795MB) | Ollama RAG 임베딩, 실측 데이터 |
| 프로젝트 의도 | `intent/` | 16개 project hash 기반 컨텍스트 |
| 글로벌 메모리 | `memory/` | MEMORY.md, lessons.md |
| 텔레메트리 | `telemetry/` | 파이프라인 실행 메트릭 |
| 세션 전사 | `transcripts/` | 전체 세션 대화 기록 |
| 자동 백업 | `backups/` | 설정 변경 전 스냅샷 |
| 파일 이력 | `file-history/` | 파일별 변경 이력 |
| 클립보드 캐시 | `paste-cache/` | 세션 내 붙여넣기 캐시 |
| 실측 데이터 | `cache/md-live/suggestion-outcomes.jsonl` | 라우팅 제안 채택률 |
| 실측 데이터 | `cache/md-live/hook-outcomes.jsonl` | 훅 실행 결과 |
| 결정 이력 | `cache/md-live/` (decision-capture 산출물) | /retro, /decisions 원천 데이터 |

## 알려진 기술적 리스크

| 리스크 | 상세 | 영향 |
|--------|------|------|
| **cache 정리 ad-hoc** | 795MB / 1291+ 항목, 자동 정리 정책 없음 | Stale RAG 임베딩 응답 오염 가능 |
| **plugins 누적** | 6107 파일 / 133MB, 비활성 플러그인 포함 가능 | 디스크 사용량 증가, 로드 시간 영향 |
| **RAG embedding stale** | local-rag 임베딩이 코드 변경 후 재색인 없이 stale 상태 유지 가능 | 코드 검색 정확도 저하 |
| **knowledge compression nuance loss** | agents-src → builds 압축 과정에서 프롬프트 뉘앙스 손실 가능 | 에이전트 동작 미묘한 편차 |
| **agy 외부 의존성** | Antigravity CLI가 외부 서비스에 의존 — 서비스 중단 시 Phase 0 스캔 불가 | prescan-enforcer 훅 실패 시 코드 수정 블로킹 가능 |
| **12개 병렬 Stop 훅** | 각 훅 독립 타임아웃(5s~90s) — 네트워크 지연 시 cascading timeout | 세션 종료 지연, 일부 학습 캡처 누락 가능 |

---

Last updated: 2026-05-25
