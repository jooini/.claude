# llm-configs — LLM CLI 순수 설정 백업

`~/.codex`, `~/.gemini` 의 **손으로 만든 비시크릿 설정**을 git으로 버전관리하는 곳.
`scripts/sync-llm-configs.sh` 가 관리한다.

## 무엇이 여기 있나 (화이트리스트)

| 저장 경로 | 원본 | 내용 |
|-----------|------|------|
| `codex/instructions.md` | `~/.codex/instructions.md` | Codex CLI 글로벌 지시(코드리뷰어 역할) |
| `codex/rules/default.rules` | `~/.codex/rules/default.rules` | Codex 기본 룰 |
| `gemini/settings.json` | `~/.gemini/settings.json` | Gemini/agy UI·동작 설정 |
| `gemini/scripts/sync-project-rules.sh` | `~/.gemini/scripts/sync-project-rules.sh` | 프로젝트 룰 동기화 스크립트 |

## 무엇이 여기 없나 (의도적 제외)

- **시크릿**: `auth.json`, `oauth_creds.json`, `google_accounts.json`, `config.toml`, `*-state.json`, `history.jsonl` — `.gitignore`로 이중 차단. 절대 커밋 금지.
- **sync-external.sh 생성물**: `AGENTS.md`, `GEMINI.md`, `hooks.json`, `workflows/`, `agents/`, skills 심링크 — 원본이 `~/.claude/`라 별도 관리 불필요.
- **머신 의존**: `config.toml`의 `[projects.*]`, `projects.json`, `trustedFolders.json` — 로컬 경로라 공유 부적합.
- **런타임/캐시**: `*.sqlite`, `sessions/`, `cache/`, `tmp/`.

## 사용법

```bash
# 원본 설정 바뀌면 백업 갱신 (그 후 git commit)
~/.claude/scripts/sync-llm-configs.sh backup

# 새 머신에서 설정 복원 (기존 파일은 .bak 백업됨)
~/.claude/scripts/sync-llm-configs.sh restore

# drift 확인 (어떤 게 바뀌었나)
~/.claude/scripts/sync-llm-configs.sh status
```

## 새 설정 파일 추가하려면

1. **먼저 시크릿 여부 확인** (`grep -iE 'key|token|secret|credential'`)
2. 시크릿 없으면 `scripts/sync-llm-configs.sh` 의 `MAPPING` 배열에 `"원본경로|저장경로"` 추가
3. `backup` 실행 후 `git add` 전 `git status`로 시크릿 안 들어왔는지 재확인
