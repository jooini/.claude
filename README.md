# Claude Code Configuration Package

나의 Claude Code 전체 설정 패키지. 에이전트 시스템, 훅, 스킬, 워크플로우를 포함한다.

> **받은 ZIP의 모드 확인**: `MANIFEST.md` 의 "모드 구성" 표를 먼저 확인.
> - 친구 공유 모드 (기본) — LLM 통합 (Gemini/Codex/Gemma/Qwen/Ollama/ini), `teams/`, `identity-hub/`, `debugging-guides/` 가 **모두 빠져 있음**. 본 README의 일부 섹션 (LLM 훅·스킬·워크플로우 설명)은 해당 파일이 ZIP 안에 없을 수 있음 — 무시하면 됨.
> - `--with-llm` / `--with-teams` / `--with-identity` / `--with-debugging` / `--backup` 모드면 해당 파일 포함됨.
> - `setup.sh` 의 `gemini`/`codex` 모듈 선택은 친구 공유 모드 ZIP 에서 무효 (대상 파일 없음).
> - 자세한 모드별 차이: `scripts/README.md` 참조.

## 빠른 시작 (받는 사람용)

### 사전 준비

| 필수 | 설치 방법 |
|------|-----------|
| Claude Code | `npm i -g @anthropic-ai/claude-code` |
| jq | `brew install jq` (설정 자동 조정에 필수) |
| node/npx | https://nodejs.org/ (MCP 서버용) |
| python3 | macOS 기본 포함 |

### 설치 (3단계)

```bash
# 1. 압축 풀기
mkdir -p ~/.claude
unzip claude-config-v*.zip -d ~/.claude/

# 2. 설치 스크립트 실행
cd ~/.claude && chmod +x setup.sh && ./setup.sh

# 3. Claude Code 재시작
```

setup.sh가 대화형으로 모듈 선택을 물어봅니다. 잘 모르겠으면 전부 `n`으로 (코어만 설치).

### 설치 후 반드시 할 것

1. **`~/.claude/CLAUDE.md` 수정** — `TODO`로 검색해서 자기 환경에 맞게 변경
   - 프로젝트 목록/경로
   - Obsidian Vault 경로 (obsidian 모듈 선택한 경우)
2. **플러그인 설치** — Claude Code에서 `/install-plugin`으로 아래 설치
   - 필수: `superpowers`, `claude-mem`, `pr-review-toolkit`, `claude-md-management`
   - 선택: `codex` (codex 모듈 선택 시), `gitlab` (gitlab 모듈 선택 시)
3. **Claude Code 재시작**

### 비대화형 설치 (CI/스크립트)

```bash
MODULES="gemini,codex" ./setup.sh    # 지정 모듈만
MODULES="all" ./setup.sh             # 전부
MODULES="none" ./setup.sh            # 코어만
```

### 모듈을 나중에 바꾸고 싶으면

```bash
cd ~/.claude && ./setup.sh --force
```

### 주의사항

- **zsh 필수** — setup.sh가 zsh 전용 문법 사용 (bash 불가)
- **macOS 아닌 경우** — `hooks/*.sh`에서 `say`/`afplay` 줄 주석 처리 필요 (알림음)
- **버전 확인** — `~/.claude/VERSION` 파일로 현재 버전 확인 가능

---

## 구조

```
.claude/
├── CLAUDE.md                  # 글로벌 설정 (파이프라인, 컨벤션, 프로젝트 규칙)
├── AGENTS.md                  # 공용 에이전트 규칙 (커밋, 응답, 코딩 컨벤션)
├── settings.json              # Claude Code 설정 (훅, MCP, 플러그인, autoApprove)
├── settings.local.json        # 로컬 전용 퍼미션 오버라이드
├── statusline-agent.sh        # 상태바 — 활성 에이전트 색상 표시
├── antigravity-workspace.json # Antigravity IDE 워크스페이스 설정
│
├── agents/                    # 커스텀 에이전트 시스템
│   ├── src/                   # 에이전트 소스 템플릿
│   ├── knowledge/             # 도메인 지식
│   ├── docs/common/           # 공통 빌드 블록 (DRY)
│   ├── builds/                # 언어별 빌드 결과 (root/python/kotlin/php/nodejs)
│   ├── build-agents.sh        # 빌드 스크립트
│   └── *.md → builds/         # 심볼릭 링크 (활성 빌드)
│
├── hooks/                     # 이벤트 훅 스크립트 (전체 100개 / 친구 공유 모드 ~60개 — LLM 통합 훅 ~40개 제외)
│   ├── bash-postproc-sync.sh      # PostToolUse(Bash) 동기 통합: branch 전환/cwd 변경/Gemini 자동 스캔/테스트 3회 실패 분석
│   ├── bash-postproc-async.sh     # PostToolUse(Bash) 비동기 통합: tool-trace JSONL + gemini/codex usage 로그
│   ├── agent-start-notify.sh      # 에이전트 시작 알림
│   ├── agent-complete-notify.sh   # 에이전트 완료 알림
│   ├── agent-context-inject.sh    # 에이전트 컨텍스트 자동 주입
│   ├── agent-knowledge-remind.sh  # Knowledge 로딩 리마인더
│   ├── agent-usage-log.sh         # 에이전트 사용 로깅
│   ├── ask-notify.sh              # 사용자 질문 알림
│   ├── code-edit-pipeline-remind.sh # 코드 수정 시 파이프라인 리마인더
│   ├── codex-prompt-notify.sh     # Codex 프롬프트 실행 알림
│   ├── codex-session-notify.sh    # Codex 세션 알림
│   ├── commit-korean-check.sh     # 커밋 메시지 한글 검증
│   ├── commit-no-coauthor.sh      # Co-Authored-By 제거
│   ├── dangerous-command-detect.sh # 위험 명령 감지
│   ├── dependency-change-detect.sh # 의존성 변경 감지 → Gemini 분석
│   ├── error-codex-remind.sh      # 에러 발생 시 Codex rescue 리마인더
│   ├── gemini-review-prescan.sh   # 리뷰 전 Gemini 사전 스캔
│   ├── knowledge-change-rebuild.sh # Knowledge 파일 변경 시 에이전트 리빌드
│   ├── lib-detect-language.sh     # 언어 감지 공통 라이브러리
│   ├── node-version-sync.sh       # Node.js 버전 동기화
│   ├── pr-create-codex-remind.sh  # PR 생성 시 Codex 요약 리마인더
│   ├── precompact-notify.sh       # 컨텍스트 압축 전 알림
│   ├── session-build-agents.sh    # 세션 시작 시 에이전트 빌드
│   ├── session-detect-language.sh # 세션 시작 시 언어 감지
│   ├── stop-notify.sh             # 작업 완료 알림 (사운드)
│   ├── stop-pipeline-check.sh     # 파이프라인 누락 검사
│   └── sounds/fanfare.wav         # 알림 사운드
│   # 2026-05-14 통합: branch-switch-detect / cwd-change-detect / gemini-auto-scan
│   #                  gemini-test-failure-analyze / tool-trace / tool-usage-log
│   #                  → bash-postproc-sync.sh + bash-postproc-async.sh
│
├── workflows/                 # 워크플로우 정의 (16개)
│   ├── pipeline.md            # 에이전트 파이프라인 (developer→reviewer→tester)
│   ├── docs-convention.md     # 문서 작성 규칙
│   ├── llm-routing.md         # LLM 공통 라우터 정책
│   ├── codex.md               # Codex 호출 패턴
│   ├── debugging.md           # 디버깅 7단계 절차
│   ├── automation.md          # 훅 자동화 정책
│   ├── standard-routines.md   # 7 TYPE(feature/bugfix/refactor/...) 루틴
│   ├── sso.md                 # SSO/BFF/Identity Hub
│   ├── projects.md            # 프로젝트 카탈로그
│   ├── self-modification-pattern.md  # CLAUDE.md/settings.json 수정 패턴
│   ├── coding-convention.md   # 코딩 컨벤션 상세
│   ├── growth.md              # 학습/회고/3중 LLM
│   ├── sdd-tdd.md             # SDD/TDD/컨텍스트 관리
│   ├── backlog-policy.md      # 백로그 등록/트랙
│   ├── search-priority.md     # 코드 검색 우선순위
│   └── team-templates.md      # @team / 멀티프로젝트 묶음
│
├── shared/                    # 공통 정책 SSOT (2026-06-08 신설)
│   ├── commit-rules.md        # 커밋 규칙 (Co-Authored-By 금지, 한글)
│   ├── coding-convention.md   # 공백/네이밍/FastAPI/Kotlin/DB
│   ├── response-style.md      # 위험도 분기, 병렬, 자율성
│   ├── tool-roles.md          # 도구 역할 분담 + LLM 라우터
│   └── project-defaults.md    # 백엔드 스택/SSO/티켓/문서
│   # → CLAUDE.md, AGENTS.md, sync-external 생성본 모두 여기 참조
│
├── references/                # 룰의 근거 & 디테일 (2026-06-08 신설)
│   ├── known-bugs.md          # malformed/AskUserQuestion 한글 버그 근거
│   ├── codex-models.md        # gpt-5.5/5.4/5.3-codex/5.4-mini 가격·실비용
│   ├── delegation-metrics.md  # 위임 효과 측정 + 우회 조건
│   ├── ssh-rules.md           # SSH 접속 (expect, MCP)
│   └── doc-link-format.md     # Obsidian / Antigravity IDE 링크 표기
│   # → CLAUDE.md 본문 다이어트로 분리. 룰은 CLAUDE.md, "왜" 만 여기
│
├── commands/                  # 슬래시 커맨드 (14개)
│   ├── check-env.md           # 환경 설정 일관성 검증
│   ├── check-server.md        # 서버 상태 확인
│   ├── check-user.md          # 사용자 조회 (T_Member + Keycloak)
│   ├── decode-sms.md          # SMS 인증번호 MD5 디코딩
│   ├── deploy-status.md       # 배포 상태 확인
│   ├── jwt-debug.md           # JWT 토큰 디버깅
│   ├── migration-status.md    # 마이그레이션 상태 확인
│   ├── project-status.md      # 다중 프로젝트 상태 확인
│   └── receipt-pdf.md         # 영수증 이미지 → A4 PDF
│
├── skills/                    # 커스텀 스킬 (전체 120개 / 친구 공유 모드 ~110개 — ask-gemini/ask-codex/ask-gemma/ask-ollama 등 LLM 위임 스킬 제외)
│   ├── ask-codex/             # Codex CLI 임시 질문/세컨드 오피니언
│   ├── ask-gemini/            # Gemini CLI 임시 질문/대규모 컨텍스트 탐색
│   ├── badge/                 # 배지 생성
│   ├── bisect/                # git bisect 자동화
│   ├── build-spi/             # Keycloak SPI 빌드+Docker 반영
│   ├── cc/                    # Claude Code 도우미
│   ├── check-sso-compat/      # B2C SSO 호환성 검증
│   ├── claude-docs-reader/    # Claude 설정 분석/요약
│   ├── co/                    # 체크아웃 헬퍼
│   ├── codex-impl/            # Codex 병렬 구현
│   ├── create-mr/             # MR 생성
│   ├── cross-check/           # SSO 멀티프로젝트 영향 분석
│   ├── debug/                 # 체계적 디버깅 (재현→수집→수정)
│   ├── deep-research/         # 심층 기술 조사
│   ├── docs-update/           # 문서 업데이트
│   ├── done/                  # 퇴근 마무리 루틴
│   ├── gemini-test/           # Gemini 테스트 생성
│   ├── get-api-docs.md        # API 문서 가져오기
│   ├── index-rag/             # RAG 인덱싱
│   ├── iterm-task/            # iTerm 태스크
│   ├── logs/                  # 서버 로그 수집/분석
│   ├── migrate-endpoint/      # 레거시 → SSO 엔드포인트 전환
│   ├── receipt-report/        # 영수증 OCR → 경비 정산 문서
│   ├── save-doc/              # 옵시디언 문서 저장
│   ├── save-history/          # 세션 히스토리 저장
│   ├── session-handoff/       # 세션 인수인계
│   ├── start/                 # 아침 작업 시작 루틴
│   ├── sync-antigravity/      # Antigravity 설정 동기화
│   ├── tech-doc/              # 기술 문서 작성
│   ├── today-tasks/           # 오늘 할 일 수집
│   ├── tool-status/           # 도구 상태 확인
│   ├── write-daily-report/    # 일일 보고서
│   └── write-weekly-report/   # 주간 보고서
│
└── scripts/                   # 유틸리티 스크립트
    ├── cache-cleanup.sh       # 캐시 정리
    ├── combine_receipts.py    # 영수증 합치기
    ├── scaffold-docs.sh       # 문서 스캐폴딩
    └── sync-antigravity.sh    # Antigravity 설정 동기화
```

## 핵심 기능

### 멀티 에이전트 파이프라인

코드 수정 시 자동으로 에이전트 파이프라인 실행:

```
Gemini 스캔(Phase 0) → developer → 병렬(code-reviewer + codex:review) → tester
```

- 한글 단축 호출: `백엔드`, `프론트`, `리뷰어`, `테스터` 등
- 파이프라인 단축: `코드만`, `리뷰 없이`, `테스트 없이`
- `@dev` — 프로젝트 전담 리드 (자체 라우팅)

### 훅 시스템

| 이벤트 | 훅 | 설명 |
|--------|-----|------|
| PreToolUse:Agent | agent-start-notify | 에이전트 시작 시 알림음 |
| PreToolUse:Agent | agent-context-inject | 에이전트 컨텍스트 자동 주입 |
| PreToolUse:Agent | agent-knowledge-remind | Knowledge 로딩 리마인더 |
| PreToolUse:Agent | gemini-review-prescan | 리뷰 전 Gemini 사전 스캔 |
| PreToolUse:Bash | commit-korean-check | 커밋 메시지 한글 검증 |
| PreToolUse:Bash | commit-no-coauthor | Co-Authored-By 자동 제거 |
| PreToolUse:Bash | pr-create-codex-remind | PR 생성 시 Codex 요약 리마인더 |
| PreToolUse:Edit\|Write | code-edit-pipeline-remind | 코드 수정 시 파이프라인 리마인더 |
| PreToolUse:Edit\|Write | dependency-change-detect | 의존성 변경 감지 |
| PostToolUse:Bash | dangerous-command-detect | 위험 명령 감지 |
| PostToolUse:Bash | error-codex-remind | 에러 시 Codex rescue 리마인더 |
| PostToolUse:Bash | bash-postproc-async | tool-trace JSONL + gemini/codex usage 로그 (통합본, 2026-05-14) |
| PostToolUse:Bash | bash-postproc-sync | branch 전환/cwd 변경/Gemini 자동 스캔/테스트 3회 실패 분석 (통합본, 2026-05-14) |
| PostToolUse:Agent | agent-usage-log | 에이전트 사용 로깅 |
| PostToolUse:Agent | agent-complete-notify | 에이전트 완료 알림음 |
| PostToolUse:Edit\|Write | knowledge-change-rebuild | Knowledge 변경 시 리빌드 |
| SessionStart | node-version-sync | Node.js 버전 동기화 |
| SessionStart | session-build-agents | 세션 시작 시 에이전트 빌드 |
| SessionStart | session-detect-language | 프로젝트 언어 감지 |
| Stop | stop-notify | 작업 완료 팡파르 |
| Stop | stop-pipeline-check | 파이프라인 실행 여부 검사 |
| PreCompact | precompact-notify | 컨텍스트 압축 전 알림 |
| Notification | ask-notify | 사용자 질문 알림 |

### 플러그인

| 플러그인 | 상태 | 설명 |
|----------|------|------|
| superpowers | 활성 | 워크플로우 스킬 (TDD, 디버깅, 브레인스토밍 등) |
| frontend-design | 활성 | 프론트엔드 디자인 생성 |
| code-review-graph | 활성 | 코드 리뷰 지식 그래프 |
| claude-mem | 활성 | 크로스 세션 메모리 |
| codex | 활성 | Codex CLI 연동 (rescue, 병렬 구현) |
| gitlab | 활성 | GitLab MCP 연동 |
| playwright | 활성 | 브라우저 자동화 |
| pr-review-toolkit | 활성 | PR 리뷰 도구 모음 |
| security-guidance | 활성 | 보안 가이드 |
| claude-md-management | 활성 | CLAUDE.md 관리 |

### MCP 서버

| 서버 | 설명 | 모듈 |
|------|------|------|
| gitlab | GitLab API 연동 | gitlab |
| local-rag | 로컬 RAG 검색 (multilingual-e5-small) | rag |

### 에이전트 상태바

`statusline-agent.sh` — 현재 활성 에이전트를 색상 코드로 터미널 상태바에 표시. 에이전트별 고유 색상 + 한글 라벨.

### 도구 역할 분담

| 도구 | 역할 |
|------|------|
| Claude Code | 메인 두뇌 — 구현, 추론, 리뷰, 의사결정 |
| Codex CLI | 검증/대안 — adversarial review, rescue, 병렬 구현 |
| Gemini CLI | 스캐너 — 대규모 코드베이스 요약 (1M 토큰), 테스트 생성 |
| Antigravity | 병렬 일손 — Manager Surface로 멀티 에이전트 동시 디스패치 |
| Jules | 백그라운드 워커 — 테스트/문서/의존성 PR 자동 생성 |
| Deep Research | 조사관 — 기술 조사, 보안 분석, 마이그레이션 전략 |

## 선택적 모듈

| 모듈 | 설명 | 필요 CLI |
|------|------|----------|
| agy (gemini) | Phase 0 스캔, 자동 리뷰 | https://antigravity.google/download (2026-06-18 이후 무료/Pro/Ultra `gemini` deprecated → `agy` 필수, 이미 시점 도래) |
| codex | 병렬 구현, rescue, 리뷰 | `npm i -g @openai/codex` |
| gitlab | GitLab MCP 서버 | `gitlab` 플러그인 |
| rag | 로컬 RAG 의미론적 검색 | `local-rag` MCP |
| playwright | 브라우저 자동화 | `playwright` 플러그인 |
| obsidian | 문서 관리 (Obsidian Vault 연동) | - |

## 갱신 이력

- **2026-06-08** — CLAUDE.md 다이어트 (234→144줄), `shared/` `references/` 신설로 공통 지식 분리. README 숫자 실측치 정정 (hooks 72→100, skills 53→120, commands 13→14, workflows 2→16)
- **2026-06-01** — Documentation drift correction (커밋 c28ad82)
- **2026-05-14** — bash-postproc-sync/async 훅 통합
