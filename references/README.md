# references/ — 룰의 근거 & 디테일

CLAUDE.md 본문 다이어트(2026-06-08)로 분리. **룰 자체는 CLAUDE.md 에 유지**, 여기엔 "왜" 와 "긴 설명" 만 보관.

## 파일

| 파일 | 분리 항목 | 본문 룰 위치 |
|------|----------|--------------|
| [`known-bugs.md`](known-bugs.md) | malformed tool_use 진짜 원인, AskUserQuestion 한글 버그 근거 | CLAUDE.md "도구 호출 형식 [HARD]" / "AskUserQuestion 한글 버그 회피 [HARD]" |
| [`codex-models.md`](codex-models.md) | Codex gpt-5.5/5.4/5.3-codex/5.4-mini 가격·강점·실비용 | CLAUDE.md "자동 위임 트리거" 표 |
| [`delegation-metrics.md`](delegation-metrics.md) | 위임 효과 측정 방법론, 우회 조건, 시계열 근거 | CLAUDE.md "자동 위임 트리거" 표 |
| [`ssh-rules.md`](ssh-rules.md) | SSH 접속 (expect, MCP) | CLAUDE.md "SSH" (한 줄 링크) |
| [`doc-link-format.md`](doc-link-format.md) | Obsidian / Antigravity IDE 링크 표기 | CLAUDE.md "문서 작성" (한 줄 링크) |

## 분리 원칙

- 본문(CLAUDE.md/AGENTS.md/README.md) = **룰** (한 줄로 요약 가능)
- references/ = **근거** (장문, 시계열, 출처)
- 룰이 깨졌을 때 "왜 이 룰이 있나" 확인용
