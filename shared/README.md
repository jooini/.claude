# shared/ — 공통 정책 SSOT

CLAUDE.md, AGENTS.md, README.md, sync-external 생성본(~/.codex/AGENTS.md, ~/.gemini/GEMINI.md) 이 공통으로 참조하는 정책 파일들.

## 파일

| 파일 | 내용 |
|------|------|
| [`commit-rules.md`](commit-rules.md) | 커밋 규칙 (Co-Authored-By 금지, 한글) |
| [`coding-convention.md`](coding-convention.md) | 코딩 컨벤션 (공백/네이밍/FastAPI/Kotlin/DB) |
| [`response-style.md`](response-style.md) | 응답 스타일 (위험도 분기, 병렬, 자율성) |
| [`tool-roles.md`](tool-roles.md) | 도구 역할 분담 + LLM 라우터 |
| [`project-defaults.md`](project-defaults.md) | 프로젝트 기본값 (스택/SSO/티켓/문서) |

## 수정 규칙

- 이 폴더 파일이 정본. 다른 곳에 동일 내용 재작성 금지
- 수정 후 `~/.claude/scripts/sync-external.sh` 실행 → Codex/Gemini 생성본 자동 갱신
- 새 공통 정책은 이 폴더에 신규 파일로 추가
