# 공통 — 도구 역할 분담

> SSOT. CLAUDE.md, AGENTS.md, README.md, sync-external 생성본 모두 이 파일 참조.

| 도구 | 역할 | 호출 |
|------|------|------|
| **Claude Code** | 메인 두뇌 — 판단/채택/최종 구현/의사결정 | (현재 세션) |
| **Codex CLI/Plugin** | 검증/대안 — adversarial review, 세컨드 오피니언, 병렬 구현, rescue | `codex exec`, `codex:*`, `Skill(ask-codex)` |
| **Gemini / agy** | 스캐너 — 대규모 코드베이스 요약(1M 토큰), 테스트 생성, 3중 리뷰 | `Skill(ask-gemini)`, `agy` |
| **Antigravity** | 병렬 일손 — Manager Surface 멀티 에이전트 디스패치 | IDE 직접 |
| **Jules** | 백그라운드 워커 — 테스트/문서/의존성 PR 자동 생성 | GitHub 봇 |
| **Deep Research** | 조사관 — 기술 조사, 보안 분석, 마이그레이션 전략 | `Skill(deep-research)` |
| **Ollama (ini)** | 로컬 — 번역/요약/문법 (200자 이하), 프라이빗 질의 | `Skill(ask-ollama)` |

## LLM 공통 라우터

Claude 토큰 소진 / provider 장애 시 공통 진입점.

- 진입점: `~/.claude/scripts/llm-router.sh`
- 정책 정본: `~/.claude/registry/llm-routing.json`
- 실행: `~/.claude/scripts/llm-call.sh`
- 핸드오프: `~/.claude/cache/llm-handoff/current.json`
- 헬스체크: `llm-router.sh doctor` → `~/.claude/cache/llm-provider-health.json`

| task | fallback chain |
|------|----------------|
| `scan` | Gemini/agy → Codex → Gemma |
| `implement` | Codex → Gemini/agy |
| `review` | Codex + Gemini/agy + Gemma 병렬 best-effort |
| `private` | Gemma only |
| `rescue` | Codex → Gemini/agy → Gemma |
| `summarize` | Gemma → Codex → Gemini/agy |

상세: [`workflows/llm-routing.md`](../workflows/llm-routing.md)
