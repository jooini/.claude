# export-claude-config.sh

Claude Code 설정을 안전하게 ZIP 아카이브로 내보내는 스크립트. 다른 머신/팀원과 공유할 때 API 키·세션·인증 정보가 새지 않도록 자동 마스킹·필터링·최종 감사를 수행한다.

> **개인 전용 파일 자동 제외**: 파일명/경로에 `gemma`, `gemini`, `codex` 가 포함된 항목은 모두 제외된다. 이들은 본인 환경(로컬 Ollama, Codex/Gemini CLI 보조)에 종속되어 공유 부적합.

---

## 빠른 시작

```bash
# 내보내기
~/.claude/scripts/export-claude-config.sh

# 어떤 파일이 포함되는지 미리 확인
~/.claude/scripts/export-claude-config.sh --dry-run

# 출력 경로 변경
~/.claude/scripts/export-claude-config.sh -o /tmp
```

결과물: `~/Desktop/claude-code-config-YYYYMMDD-HHMM.zip`

---

## 옵션

| 옵션 | 동작 |
|------|------|
| (없음) | `~/.claude` 패키징 → `~/Desktop` 으로 ZIP |
| `--dry-run` | 수집 대상 파일 목록만 출력, ZIP 생성 안 함 |
| `--force` | 최종 감사에서 의심 패턴 발견돼도 강제 진행 |
| `-o, --output DIR` | 출력 디렉토리 변경 (기본: `~/Desktop`) |
| `-h, --help` | 도움말 |

---

## 수집 대상 (`~/.claude`)

- 루트: `CLAUDE.md`, `AGENTS.md`, `README.md`, `settings.json`, `setup.sh`, `package.sh`, `statusline-agent.sh`
- `agents/*.md`
- `skills/*.md` + `skills/*/` 하위 `*.md` / `*.sh` / `*.json`
- `commands/*.md`
- `workflows/*.md`
- `debugging-guides/*.md`
- `docs/*.md`
- `scripts/*.sh`, `hooks/*.sh`
- `plugins/*.json` (캐시 제외, 설정만)
- `teams/**` (전체)
- `projects/*/CLAUDE.md`, `projects/*/settings.json`

---

## 자동 제외

### 1. 개인 전용 키워드 매칭

파일명/경로(소문자 변환)에 다음 중 하나라도 포함되면 즉시 제외:

```
gemma   gemini   codex
```

영향 받는 파일 예시:

| 위치 | 사례 |
|------|------|
| `scripts/` | `gemma-logger.sh`, `gemma-pr-preview.sh`, `gemma-cron-daily.sh`, `sync-codex.sh` |
| `hooks/` | `gemma-morning-brief.sh`, `gemma-commit-convention.sh`, `gemma-session-summarize.sh`, `gemma-error-summarize.sh`, `gemma-korean-translate-gate.sh`, `gemma-intent-capture.sh`, `gemma-intent-restore.sh` |
| `skills/` | `ask-gemma/`, `ask-gemini/`, `ask-codex/` 디렉토리 전체 |
| `workflows/` | `codex.md` |
| `teams/` | `*Gemini-delegation*.json` 같은 inbox |

### 2. 패턴 기반 디렉토리 차단 (`SENSITIVE_PATTERNS`)

처음부터 수집 대상에서 빠지는 항목:

```
*.backup*, .claude.json, settings.local.json,
security_warnings_state_*, mcp-needs-auth-cache.json,
stats-cache.json, antigravity-workspace.json,
statsig/, telemetry/, transcripts/, sessions/,
session-env/, cache/, paste-cache/, backups/,
debug/, todos/, tasks/, plans/, file-history/,
shell-snapshots/, lancedb/, ide/, workspace-root/,
.obsidian/, .idea/, plugins/cache/,
projects/*/memory/
```

---

## 보안: 다층 방어

### 텍스트 파일 스크러빙 (`scrub_sensitive`)

확장자가 `.json` / `.md` / `.sh` / `.yaml` / `.yml` / `.env` / `.toml` / `.conf` / `.ini` / `.txt`인 파일에 `sed -E` 적용:

**키-값 마스킹** (8자 이상 값만):
- `api_key`, `apikey`, `api-key`
- `access_token`, `refresh_token`, `auth_token`, `session_token`, `bearer`
- `client_secret`, `webhook_secret`, `signing_secret`, `encryption_key`, `private_key`, `access_key`
- `secret`, `token`, `password`, `passwd`, `passphrase`
- JSON: `"field": "value"` → `"field": "REDACTED"`
- ENV/Shell: `FIELD=value` 또는 `export FIELD=value` → `FIELD=REDACTED`

**고엔트로피 프리픽스 마스킹**:

| 프리픽스 | 출처 | 결과 |
|---------|------|------|
| `sk-`, `sk_` | OpenAI / Anthropic | `sk-REDACTED` |
| `ghp_`, `gho_`, `ghs_`, `ghu_`, `ghr_` | GitHub Personal/OAuth/Server/User/Refresh | `ghp_REDACTED` |
| `xox[baprs]-` | Slack Bot/App/User/Refresh/Service | `xoxREDACTED` |
| `AKIA` (16자 영숫자) | AWS Access Key | `AKIAREDACTED` |

### 최종 감사 (`audit_tmpdir`)

ZIP 생성 직전 `TMPDIR`을 다시 스캔. 다음 패턴 발견 시 **중단**:

- `(sk-|sk_|ghp_|gho_|ghs_)[A-Za-z0-9_-]{20,}`
- `xox[baprs]-[A-Za-z0-9-]{10,}`
- `AKIA[0-9A-Z]{16}`
- `-----BEGIN ... PRIVATE KEY-----`
- JWT 패턴: `eyJ...\....\....`
- 24자 이상 고엔트로피 값을 가진 `API_KEY/TOKEN/SECRET/PASSWORD` 필드
  - 단 `test`, `example`, `your_`, `changeme`, `xxx`, `dummy`, `fake`, `sample`, `placeholder` 제외

`REDACTED` 라인은 무시. 발견 시 상위 20건 표시 후 종료(exit 2). `--force`로 우회 가능.

---

## 출력 결과

```
claude-code-config-YYYYMMDD-HHMM.zip
├── MANIFEST.md           ← 적용 방법, 제외 항목, 마스킹 규칙
└── claude/
    ├── CLAUDE.md
    ├── settings.json     ← 키-값 REDACTED 적용됨
    ├── agents/*.md
    ├── skills/...
    ├── commands/*.md
    ├── workflows/*.md
    ├── scripts/*.sh
    ├── hooks/*.sh
    └── projects/{프로젝트}/CLAUDE.md
```

`MANIFEST.md`는 자동 생성되며 호스트명·시각·파일 수·import 명령어를 포함한다.

---

## 받는 쪽: 적용 방법

```bash
# 1. 압축 해제
unzip claude-code-config-*.zip -d ~/claude-config-import

# 2. 기존 설정 백업 (선택)
cp -r ~/.claude ~/.claude.bak-$(date +%Y%m%d)

# 3. 복사
cp -r ~/claude-config-import/claude/* ~/.claude/

# 4. 마스킹된 값 직접 입력
#    - settings.json 의 REDACTED 필드
#    - settings.local.json (포함 안 됨, 새로 생성)
```

---

## 동작 흐름

```
파싱 → 파일 수집(개인키워드/민감패턴 차단) → TMPDIR 복사하면서 scrub
       → 최종 감사 → MANIFEST 생성 → ZIP
                  ↓ (감사 실패)
             --force 없으면 exit 2
```

`set -eo pipefail` + `trap` 으로 중간 실패 시 `TMPDIR` 자동 정리.

---

## 주의사항

- `settings.local.json`은 **절대** 포함되지 않는다 (로컬 전용 설정 + 권한 ACL).
- `memory/` 는 사용자별 누적 메모리이므로 공유 부적합.
- 마스킹 후에도 자유 텍스트 필드(주석, 설명)에 키를 적어두면 감사를 통과할 수 있음 → CLAUDE.md/agents/skills 검토 필요.
- 감사가 통과해도 100% 안전을 보장하지 않는다. 공유 전 직접 ZIP을 풀어 `grep -i token` / `grep -i secret` 로 한 번 더 확인 권장.
- 개인 키워드(`gemma`/`gemini`/`codex`)가 정상 파일명에도 포함될 수 있다 (예: `gemini-delegation`이 들어간 팀원 이름). 의도치 않은 제외가 의심되면 `--dry-run`으로 사전 확인.

---

## 관련 작업

| 일시 | 작업 |
|------|------|
| 2026-04-16 13:31 | 최초 생성 (#7415) |
| 2026-04-16 13:35 | Gemini OAuth/Google account 제외 (#7416) |
| 2026-04-16 13:58 | Codex sqlite/session 제외 + rules/ 수집 (#7417) |
| 2026-04-16 13:58 | e2e 검증, 183 파일 / 568K (#7419) |
| 2026-04-17 12:00 | `--force` 플래그 추가 (#7608) |
| 2026-04-17 12:04 | `section` 미정의 함수 → `header` 수정 (#7613) |
| 2026-04-17 12:04 | ZIP 추출 후 NOTION_TOKEN REDACTED 검증 (#7614) |
| 2026-04-27 | Gemma/Gemini/Codex 보조 파일 자동 제외, `--with-gemini`/`--with-codex`/`--all` 옵션 제거 |
