# 문서 작성 규칙

> CLAUDE.md에서 `@~/.claude/workflows/docs-convention.md` 로 참조됨.

## Obsidian Vault 경로

Base: `~/Workspace/weaversbrain/weaversbrain/`

| 용도 | 경로 패턴 |
|------|----------|
| 일일 보고서 | `Daily/YYYY-MM/YYYY-MM-DD.md` |
| 세션 히스토리 | `Sessions/YYYY-MM/YYYY-MM-DD-{project}.md` |
| 프로젝트 문서 | `Projects/{project}/YYYY-MM/YYYY-MM-DD-HHMM-{파일명}.md` |
| 설계/계획 | `Plans/YYYY-MM/YYYY-MM-DD-HHMM-{파일명}.md` |
| 주간 보고서 | `Reports/YYYY-MM/YYYY-MM-DD-weekly.md` |

## 규칙

- YAML frontmatter 필수 (date, type, project 등)
- 파일명에 시분 포함: `YYYY-MM-DD-HHMM-{파일명}.md`
- Claude 컨텍스트 파일: `~/.claude/{프로젝트명}/`

## 세션 히스토리

- 현재: `Sessions/YYYY-MM/YYYY-MM-DD-{project}.md`
- 아카이브 (1/22~2/16): `Projects/misc/2026-02/2026-02-17-claude-md-session-archive.md`
- 레거시 docs (보존 중): `~/Workspace/docs/` (마이그레이션 완료, 아카이브 예정)
