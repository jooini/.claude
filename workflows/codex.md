# Codex MCP 필수 활용 매핑

> CLAUDE.md에서 `@~/.claude/workflows/codex.md` 로 참조됨.

`mcp__codex-cli__codex`와 `mcp__codex-cli__review`를 아래 상황에서 **반드시** 사용.

| 상황 | Codex MCP 도구 | 실행 방식 |
|------|---------------|----------|
| 코드 구현/수정 | `mcp__codex-cli__codex` | developer 에이전트와 **병렬** 구현, 최선안 채택 |
| 코드 수정 후 리뷰 | `mcp__codex-cli__review` | code-reviewer 에이전트와 **병렬** |
| 구현 세컨드 오피니언 | `mcp__codex-cli__codex` | developer 에이전트와 **병렬** |
| 디버깅 3회 실패 | `mcp__codex-cli__codex` | foreground 에스컬레이션 |
| PR 생성 전 최종 검증 | `mcp__codex-cli__review` | 단독 실행 |
| 설계 판단 (3파일+) | `mcp__codex-cli__codex` | 세컨드 오피니언 |

## 우선순위

- Codex MCP가 기존 `codex:codex-rescue` 스킬(Bash 기반)보다 **우선**
- `ask-codex` 스킬은 파이프라인 밖 임시 질문용으로 유지
- Codex MCP 호출 시 `workingDirectory`에 프로젝트 경로 명시

## 규칙 요약

- 코드 수정 후 리뷰 → code-reviewer 에이전트 + codex:review **병렬 실행** (규모 무관)
- 보안/DB/인프라/API breaking change → `codex:adversarial-review` 로 격상
- developer→tester 3회 실패 → `codex:codex-rescue` **foreground** 에스컬레이션 (background 금지 — 결과 수집 불가)
- M/L 규모 → developer 구현과 `codex:parallel-impl` 대안 구현 병렬 실행, Claude Code가 최선안 채택
