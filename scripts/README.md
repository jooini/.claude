# export-claude-config.sh

Claude Code 설정을 ZIP 아카이브로 내보내는 스크립트. **모드 분리**로 친구 공유 / 사내 공유 / 본인 백업 용도를 구분한다. API 키·세션·인증 정보 자동 마스킹 + 절대경로 치환 + 최종 감사.

---

## 빠른 시작

```bash
# 친구 공유 (기본) — LLM 통합/teams/identity-hub 전부 제외
~/.claude/scripts/export-claude-config.sh

# 본인 백업 (전체 포함)
~/.claude/scripts/export-claude-config.sh --backup

# 미리보기
~/.claude/scripts/export-claude-config.sh --dry-run

# 출력 경로 변경
~/.claude/scripts/export-claude-config.sh -o /tmp
```

결과물: `~/Desktop/claude-code-config-YYYYMMDD-HHMM.zip`

---

## 모드 옵션

| 옵션 | 동작 | 용도 |
|------|------|------|
| (기본) | LLM 통합 + teams + identity-hub + debugging-guides **전부 제외** | 친구·외부 공유 |
| `--with-llm` | LLM 통합 포함 (Gemini/Codex/Gemma/Qwen/Ollama/ini) | 같은 LLM 환경 가진 동료 |
| `--with-teams` | teams/ 사내 협업 inbox 포함 | 사내 팀원 |
| `--with-identity` | identity-hub/ 사내 OAuth 정책 포함 | 사내 SSO 담당 |
| `--with-debugging` | debugging-guides/ 사내 이슈 디버깅 가이드 포함 | 같은 이슈 디버깅 동료 |
| `--backup` | 위 넷 모두 포함 | 본인 백업 |

### 부가 옵션

| 옵션 | 동작 |
|------|------|
| `--dry-run` | 수집 대상 파일 목록만 출력, ZIP 생성 안 함 |
| `--force` | 최종 감사에서 의심 패턴 발견돼도 강제 진행 |
| `-o, --output DIR` | 출력 디렉토리 변경 (기본: `~/Desktop`) |
| `-h, --help` | 도움말 |

---

## 모드별 파일 수 (현재 환경 기준)

| 모드 | 파일 수 |
|------|---------|
| 기본 (친구 공유) | 528 |
| `--with-llm` | 583 |
| `--with-teams` | 636 |
| `--with-identity` | 529 |
| `--with-debugging` | 532 |
| `--backup` | 684 |

---

## 수집 대상 (`~/.claude`)

- 루트: `CLAUDE.md`, `AGENTS.md`, `README.md`, `CHEATSHEET.md`, `VERSION`, `settings.json`, `setup.sh`, `package.sh`, `statusline-agent.sh`, `docs-config.yaml(.example)`
- `agents/` — 활성 빌드 심볼릭 링크 11개 + `src/` (11) + `builds/` (55, 5개 언어) + `knowledge/` (290 — 도메인 지식 전체) + `docs/common/` (3) + `README.md` + `MAINTENANCE.md` + `knowledge-catalog.md`
- `skills/` — `*.md` + `*/` 디렉토리 하위 `*.md` / `*.sh` / `*.json`
- `commands/*.md`
- `workflows/*.md`
- `debugging-guides/*.md` — **`--with-debugging` 시에만**
- `docs/` — `*.md` / `*.txt` / `*.yaml` / `*.json`
- `scripts/` — `*.sh` + `*.py`
- `hooks/*.sh`
- `plugins/*.json` (캐시 제외)
- `teams/**` — **`--with-teams` 시에만**
- `identity-hub/**` — **`--with-identity` 시에만**
- `projects/*/CLAUDE.md`, `projects/*/settings.json` — `memory/` 제외

---

## 자동 제외

### 1. LLM 키워드 매칭 (기본 모드 / `--with-llm` 시 비활성)

파일명/디렉토리명(소문자)에 다음 중 하나라도 포함되면 제외:

```
gemma   gemini   codex   qwen   ollama   ini
```

> `ini` 키워드는 `ini-`, `-ini`, `-ini-`, 단독 `ini` 형태로만 매칭 (예: `minify`, `definition` 같은 false positive 회피)

영향 받는 파일 예시:

| 위치 | 사례 |
|------|------|
| `hooks/` | `gemma-*.sh` (13개), `gemini-*.sh` (5개 — auto-scan/review-prescan/dependency-impact/large-diff-prescan/test-failure-analyze/prescan-enforcer 등), `qwen-*.sh` (7개), `simple-query-ollama-route.sh` |
| `skills/` | `ask-gemma/`, `ask-gemini/`, `ask-codex/`, `ask-ollama/`, `codex-impl/`, `gemini-test/`, `gemma-log/` |
| `workflows/` | `codex.md` |
| `docs/` | `codex-compat-usage.md` |

### 2. 항상 제외 (수집 화이트리스트 미포함)

- `settings.local.json`, `.claude.json`, `history.jsonl`
- `mcp-needs-auth-cache.json`, `policy-limits.json`, `antigravity-workspace.json`
- `memory/`, `projects/*/memory/`
- `transcripts/`, `sessions/`, `session-env/`
- `cache/`, `paste-cache/`, `backups/`, `lancedb/`
- `debug/`, `todos/`, `tasks/`, `plans/`, `file-history/`, `shell-snapshots/`
- `.obsidian/`, `.idea/`, `ide/`, `workspace-root/`
- `plugins/cache/`

> 참고: 스크립트 안의 `SENSITIVE_PATTERNS` 배열은 정의되어 있지만 수집이 화이트리스트 방식이라 실제로는 동작하지 않는 데드코드. 위 항목들은 처음부터 화이트리스트에 없어 자연스럽게 빠진다.

---

## 보안: 다층 방어

### 1. settings.json 친구 공유 모드 추가 처리

기본 모드(친구 공유)에서 `sanitize_settings_json` 적용:

- **env 필드 제거** → `{"_NOTE": "env vars removed for sharing"}`
- **절대경로 치환**:
  - `/Users/leonard/...` → `/Users/USER/...`
  - `$HOME` 경로 변수화
- **allowlist 필드만 추출**:
  ```
  cleanupPeriodDays, theme, model, alwaysThinkingEnabled,
  remoteControlAtStartup, skipAutoPermissionPrompt,
  permissions, hooks, autoApprove, enabledPlugins,
  extraKnownMarketplaces, mcpServers, skills
  ```

`--with-llm` / `--with-teams` / `--with-identity` / `--backup` 모드는 sanitize 미적용 (원본 유지).

### 2. 텍스트 파일 스크러빙 (`scrub_sensitive`)

확장자 `.json` / `.md` / `.sh` / `.yaml` / `.yml` / `.env` / `.toml` / `.conf` / `.ini` / `.txt` 에 `sed -E` 적용:

**키-값 마스킹** (8자 이상 값):
- `api_key`, `apikey`, `api-key`
- `access_token`, `refresh_token`, `auth_token`, `session_token`, `bearer`
- `client_secret`, `webhook_secret`, `signing_secret`, `encryption_key`, `private_key`, `access_key`
- `secret`, `token`, `password`, `passwd`, `passphrase`
- JSON: `"field": "value"` → `"field": "REDACTED"`
- ENV/Shell: `FIELD=value` → `FIELD=REDACTED`

**고엔트로피 프리픽스 마스킹**:

| 프리픽스 | 출처 | 결과 |
|---------|------|------|
| `sk-`, `sk_` | OpenAI / Anthropic | `sk-REDACTED` |
| `ghp_`, `gho_`, `ghs_`, `ghu_`, `ghr_` | GitHub | `ghp_REDACTED` |
| `xox[baprs]-` | Slack | `xoxREDACTED` |
| `AKIA` (16자) | AWS Access Key | `AKIAREDACTED` |

### 3. 최종 감사 (`audit_tmpdir`)

ZIP 생성 직전 `TMPDIR` 재스캔. 다음 패턴 발견 시 **중단** (exit 2):

- `(sk-|sk_|ghp_|gho_|ghs_)[A-Za-z0-9_-]{20,}`
- `xox[baprs]-[A-Za-z0-9-]{10,}`
- `AKIA[0-9A-Z]{16}`
- `-----BEGIN ... PRIVATE KEY-----`
- JWT: `eyJ...\....\....`
- 24자 이상 고엔트로피 값의 `API_KEY/TOKEN/SECRET/PASSWORD` 필드
  - 단 `test`, `example`, `your_`, `changeme`, `xxx`, `dummy`, `fake`, `sample`, `placeholder` 제외

`REDACTED` 라인은 무시. `--force` 로 우회 가능.

> **감사 한계**: sessionId UUID, agentId, cwd 절대경로, 사내 프로젝트명 같은 PII는 정규식 미커버. 친구 공유 모드의 `teams/`·`identity-hub/` 차단으로 차단해야 함.

---

## 출력 결과

```
claude-code-config-YYYYMMDD-HHMM.zip
├── MANIFEST.md             ← 모드/적용방법/제외항목/마스킹규칙
└── claude/
    ├── CLAUDE.md
    ├── settings.json       ← 친구 공유 모드: sanitize 적용
    ├── agents/
    │   ├── *.md            ← 활성 빌드 (심볼릭 링크가 평문 .md 로 변환되어 들어감)
    │   ├── src/*.md        ← 에이전트 소스 템플릿 11개
    │   ├── builds/{lang}/  ← 5개 언어별 빌드 결과 (root/python/kotlin/php/nodejs)
    │   ├── knowledge/      ← 도메인 지식 290개 (역할별 + 언어별)
    │   ├── docs/common/    ← BUILD:COMMON 공통 블록
    │   ├── README.md       ← 빌드 시스템 사용법
    │   ├── MAINTENANCE.md  ← knowledge 품질 기준
    │   └── build-agents.sh
    ├── skills/...
    ├── commands/*.md
    ├── workflows/*.md
    ├── scripts/*.sh
    ├── hooks/*.sh
    ├── teams/...           ← --with-teams 시
    ├── identity-hub/...    ← --with-identity 시
    ├── debugging-guides/   ← --with-debugging 시
    └── projects/{프로젝트}/CLAUDE.md
```

`MANIFEST.md` 는 모드별로 다르게 자동 생성 (LLM/teams/identity-hub/debugging-guides 포함 여부 표시).

> **knowledge 사용법은 `agents/README.md` 참조**. 받는 사람은 ZIP 풀고 `~/.claude/agents/build-agents.sh` 로 재빌드해야 활성 빌드 심볼릭 링크가 자기 환경에 맞게 다시 만들어진다.

---

## 받는 쪽: 적용 방법

```bash
# 1. 압축 해제
unzip claude-code-config-*.zip -d ~/claude-config-import

# 2. 기존 설정 백업
cp -r ~/.claude ~/.claude.bak-$(date +%Y%m%d)

# 3. 복사
cp -r ~/claude-config-import/claude/* ~/.claude/

# 4. 에이전트 재빌드 (knowledge 활성화)
~/.claude/agents/build-agents.sh
#    - 받은 ZIP에서 활성 빌드 .md 는 평문이지만,
#      build-agents.sh 가 자기 머신에서 심볼릭 링크 + knowledge 압축 삽입
#    - 자세한 빌드 옵션: agents/README.md

# 5. 친구 공유 모드인 경우 추가 작업
#    - settings.json 의 env 필드 직접 추가 (받은 파일은 _NOTE 만 있음)
#    - settings.local.json 새로 생성
#    - REDACTED 값 직접 입력
#    - LLM 통합(Gemini/Codex/Ollama 등)이 필요하면 별도로 받기
#    - 사내 디버깅 가이드 필요하면 --with-debugging 으로 다시 받기
```

---

## 동작 흐름

```
옵션 파싱 → 모드 결정 (LLM/teams/identity)
        ↓
파일 수집 (모드별 화이트리스트 + LLM 키워드 차단)
        ↓
TMPDIR 복사 (scrub_sensitive + settings.json sanitize)
        ↓
최종 감사 → MANIFEST 생성 → ZIP
        ↓ (감사 실패)
   --force 없으면 exit 2
```

`set -eo pipefail` + `trap` 으로 중간 실패 시 `TMPDIR` 자동 정리.

---

## 주의사항

- `settings.local.json` 은 **절대** 포함되지 않는다 (로컬 전용 + 권한 ACL).
- `memory/` 는 사용자별 누적 메모리 — 공유 부적합 (자동 제외).
- 자유 텍스트 필드(주석, 설명) 안에 키를 직접 적어두면 감사를 통과할 수 있음 → 공유 전 ZIP 풀어서 `grep -i token` / `grep -i secret` 권장.
- 친구 공유 모드의 `settings.json` 은 **모든 hooks/autoApprove/permissions 그대로 들어간다** (env만 제거). 본인의 `qwen-*` / `gemma-*` 훅 참조가 settings에 남아있어도 친구 환경에 해당 파일이 없으니 자연스럽게 무시됨. 단 권한 정책은 그대로 적용되니 **친구가 받은 후 검토 권장**.
- LLM 키워드의 false positive 가능성 → `--dry-run` 으로 사전 확인.

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
| 2026-04-27 | Gemma/Gemini/Codex 보조 파일 자동 제외 |
| 2026-05-06 | **모드 분리** — `--with-llm` / `--with-teams` / `--with-identity` / `--with-debugging` / `--backup` 추가, 키워드 확장 (qwen/ollama/ini), settings.json sanitize, teams/identity-hub/debugging-guides 기본 차단 |
