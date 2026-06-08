# 공통 — 커밋 규칙

> SSOT. CLAUDE.md, AGENTS.md, README.md, sync-external 생성본(~/.codex/AGENTS.md, ~/.gemini/GEMINI.md) 모두 이 파일 참조.

- **Co-Authored-By 절대 금지** (`hooks/commit-no-coauthor.sh` PreToolUse 차단)
- 커밋 메시지 한글 (`hooks/commit-korean-check.sh` 검증)
- `git commit --amend` 보다 새 커밋 선호
- `--no-verify` / `--no-gpg-sign` 사용자 명시 지시 없을 때 금지
- `git add -A` / `git add .` 지양 — 파일 명시 add (시크릿/대용량 우발 포함 방지)
