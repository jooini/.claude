# 공용 에이전트 규칙 (Codex / Gemini / Antigravity / 외부 LLM)

이 파일은 **Codex CLI, Gemini CLI, Antigravity 등 외부 LLM 도구**가 ~/.claude 와 같은 컨벤션을 따르도록 안내한다. Claude Code 전용 룰은 [`CLAUDE.md`](CLAUDE.md).

> ⚠️ **이 파일은 직접 수정하지 마라.** 실제로 외부 LLM 이 읽는 본은 sync 파이프라인이 생성한다:
> - `~/.codex/AGENTS.md` (Codex CLI 가 읽음)
> - `~/.gemini/GEMINI.md` (Gemini CLI 가 읽음)
> - 생성 스크립트: `~/.claude/scripts/sync-external.sh` (src: `~/.claude/CLAUDE.md` + `shared/`)
>
> 이 파일(`~/.claude/AGENTS.md`)은 그 sync 사양의 **요약 인덱스** + **표준 OpenAI/Anthropic `AGENTS.md` 컨벤션 호환용**이다.

---

## 공통 정책 (SSOT 링크)

| 항목 | 정본 |
|------|------|
| 커밋 규칙 | [`shared/commit-rules.md`](shared/commit-rules.md) |
| 코딩 컨벤션 | [`shared/coding-convention.md`](shared/coding-convention.md) |
| 응답 스타일 (위험도 분기/병렬/자율성) | [`shared/response-style.md`](shared/response-style.md) |
| 도구 역할 분담 + LLM 라우터 | [`shared/tool-roles.md`](shared/tool-roles.md) |
| 프로젝트 기본값 (스택/SSO/티켓/문서) | [`shared/project-defaults.md`](shared/project-defaults.md) |

위 5개 파일이 이 폴더에서 **유일한 정본**. 다른 곳(CLAUDE.md, README.md, ~/.codex/AGENTS.md, ~/.gemini/GEMINI.md) 은 모두 이 파일을 인용/포함만 한다.

## 외부 LLM 별 차이

| 도구 | 받는 파일 | sync 시점 | Claude 전용 룰 제외? |
|------|----------|-----------|---------------------|
| Codex CLI | `~/.codex/AGENTS.md` (~28KB, 34 sections) | `sync-external.sh` | ✅ 에이전트 파이프라인/MCP 룰 제외 |
| Gemini CLI / agy | `~/.gemini/GEMINI.md` (~22KB) | `sync-external.sh` | ✅ Claude 전용 hook 룰 제외 |
| Antigravity | 자체 워크스페이스 설정 + IDE 직접 | 수동 | ✅ |

상세 동작: `~/.claude/scripts/sync-external.sh` 의 필터 로직.

## 수정 방법

1. 정책 변경은 **반드시 `shared/` 의 해당 파일** 수정 (이 파일 직접 수정 X)
2. 그 후 `~/.claude/scripts/sync-external.sh` 실행
3. `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` 자동 갱신 확인

---

> 과거 이 파일에 있던 60줄짜리 본문 룰(2026-04-15 ~ 2026-06-08)은 `shared/` 로 이관됨. 이력은 git log 참조.
