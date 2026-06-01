# Claude Code 글로벌 설정

## 핵심 원칙

### 위험도 기반 분기 (룰 우선순위 — 충돌 시 이것 우선)

| 도메인 | 모드 | 적용 |
|--------|------|------|
| 🔴 **인프라 / 시크릿 / 배포 / 외부 시스템 / 파괴적 명령** | 검증 우선 (추정 절대 금지) | Read/Grep/Bash 100% 사전 검증 후 답변 |
| 🟡 **사실 확인 질문** ("있어?", "되어있어?", "컨벤션이?") | 검증 우선 | 위와 동일 |
| 🟢 **로컬 / 가역 / 저위험 / 코드 수정** | 자율 진행 | 묻지 않고 끝까지. 합리적 가정 허용 |

### 공통 룰

- 코드 수정 시 파이프라인 실행. 혼자 수정하고 "완료" 선언 금지
- 병렬 가능한 단계 반드시 병렬 (순차 금지)
- "~하겠습니다" 식 확인 반복 금지. 결과 나오면 바로 다음 단계
- 🔴/🟡 도메인 추정 답이 틀렸으면 즉시 사과 + 검증 + 정정. **같은 추정 두 번 금지**
- 🟢 도메인도 검증 못 한 부분은 "추정" 또는 "검증 필요" 명시

### AskUserQuestion 한글 버그 회피 [HARD — constitution보다 우선]

> **근거 (검증 2026-05-31 포렌식 18 transcript / 2026-06-01 실측)**: `AskUserQuestion` 호출 시 한글 텍스트를 `\uXXXX` escape 직렬화하는 과정에서 버퍼 경계 버그로 hex 손상 → `questions` 배열이 string으로 폴백 → `InputValidationError: questions type expected array but provided string` → 멈춤. 실측 한 세션 114회 중 25회 실패 = **22%**. 한글은 영어 대비 escape **23배**(동일 질문 영어 0개 vs 한글 23개) → 한글 사용자가 23배 자주 겪음. GitHub #30955. **Claude Code 본체+서버 버그라 `.claude` 재설치·폰트 변경으로 해결 불가, Anthropic 패치 전까지 클라이언트단 회피만 가능.** 일반 한글 응답·설명은 안전(이 경로 안 탐) — **AskUserQuestion 도구 호출 + 한글** 조합만 트리거. 실시간 강제는 `hooks/askuserquestion-bug-guard.sh`(router P0)가 담당.

- [HARD] **저위험(🟢) 질문은 AskUserQuestion 쓰지 말 것** — 본문 마크다운으로 선택지 제시(`A) ... B) ... C) ...`). 깨지는 도구 경로 자체 회피
- [HARD] **고위험(🔴 삭제·배포·인프라·외부시스템·파괴적) 확인만 AskUserQuestion 허용** — 단 question·header·label·description을 **전부 영어(ASCII)로** 작성(escape 0개). 한글 부연은 본문 텍스트에, tool payload엔 ASCII만
- [HARD] **이 회피 룰이 MoAI constitution의 `[HARD] 모든 질문은 AskUserQuestion으로 / 한글 응답`보다 우선** — constitution.md는 FROZEN이라 본문 수정 불가 → 글로벌 회피룰로 무력화. `moai update` 무영향 안전지대
- 트레이드오프: A(영어 선택지)·C(본문 질문)는 성능/품질 영향 0. 위험 작업은 계속 확인하므로 자율성 과다 우려 없음

## 워크플로우 문서 (조건부 로드)

키워드 트리거 시 해당 파일 Read.

| 키워드 트리거 | 경로 |
|--------------|------|
| 파이프라인 / backend·frontend·fullstack | `workflows/pipeline.md` |
| Codex 호출 | `workflows/codex.md` |
| 프로젝트 목록 / 어디서 / 무슨 스택 | `workflows/projects.md` |
| SSO / BFF / Identity Hub | `workflows/sso.md` |
| Obsidian / 문서 작성 / vault | `workflows/docs-convention.md` |
| feature / bugfix / refactor / design / data / ops / docs | `workflows/standard-routines.md` |
| CLAUDE.md / settings.json 수정 | `workflows/self-modification-pattern.md` |
| Gemma / Gemini / Codex / Ollama 라우팅 | `workflows/llm-routing.md` |
| 에러 / 버그 / 디버깅 | `workflows/debugging.md` |
| 코드 작성 / 코딩 컨벤션 | `workflows/coding-convention.md` |
| 자동화 / 메트릭 / hook 동작 | `workflows/automation.md` |
| 학습 / 회고 / 큰 결정 / 3중 LLM | `workflows/growth.md` |
| SDD / TDD / 컨텍스트 관리 | `workflows/sdd-tdd.md` |
| 백로그 등록 / 트랙 | `workflows/backlog-policy.md` |
| 코드 검색 / RAG / Grep | `workflows/search-priority.md` |

## 에이전트 라우팅 결정표 (단일표 — 위에서 아래로 첫 매칭 적용)

> **충돌 시 우선순위**: P0(프로젝트) > P1(역할 호출) > P2(파이프라인) > P3(단축 호출) > P4(타입 키워드) > P5(1차 분류 휴리스틱) > P6(컨텍스트 유지)
> **실측 근거 (2026-06-01 갱신)**: `suggestion-outcomes.jsonl` 최종 43건 중 frontend 추천 39건, 채택률 7%(accepted 3, ignored 34)로 확정 → **2026-06-01 `agent-routing-suggest.sh` + `suggestion-outcome-track.sh` hook 제거**([[project_routing_suggest_hook_removed_2026_06_01]]). P5는 추측 휴리스틱이 아니라 **명시 신호 기반**(UI 키워드 등장 시만 frontend) + **불명확 시 현재 호출 유지**로 운영. 라우팅은 이 표가 단독 담당(추천 hook 없음).

| P | 입력 신호 | 결정 | 비고 |
|---|----------|------|------|
| **P0** | `@dev` 호출 | 프로젝트 `.claude/agents/dev.md` 라우팅. 글로벌 파이프라인 **비적용** | 이중 실행 방지 |
| **P0** | `@dev` + 프로젝트 `dev.md` 없음 | `dev-lead`로 폴백 | dev-lead는 @dev의 폴백, 대체 아님 |
| **P0** | `@team` 호출 | 크로스 프로젝트 팀 라우팅 | 영향 범위 기준 병렬 |
| **P1** | 한글 호출명 (복수 → 병렬) | `백엔드→backend-developer` / `프론트→frontend-developer` / `AI엔지니어→ai-engineer` / `리뷰어→code-reviewer` / `디자이너→designer` / `피오→po` / `데이터→data-analyst` / `옵스→ops-lead` / `프롬프트→prompt-engineer` | 명시 호출 최우선 |
| **P1** | `큐에이` | `qa` — **테스트 설계/케이스/시나리오 전담** | 명령 실행 안 함 |
| **P1** | `테스터` | `code-tester` — **lint/build/test 실행 전담** | 설계 안 함 |
| **P2** | `@dev` 없이 파이프라인 키워드 (`backend`/`frontend`/`fullstack`/`파이프라인`) | `workflows/pipeline.md` 적용 | 직접 작업 모드 |
| **P2** | `@dev` 없이 **코드 파일 수정 발생** (키워드 없어도) | Gemini 스캔 → developer → 병렬(reviewer + codex:review) → code-tester | 기본 파이프라인 |
| **P2** | 설정/프롬프트/문서만 수정 | 파이프라인 생략 | 코드 변경 0건일 때만 |
| **P3** | 단축 호출 충돌 시 우선순위 | `단독으로` > `코드만/구현만` > `TDD로` > `리뷰 없이` > `테스트 없이` > `스펙 없이` | 상위가 하위 덮어씀 |
| **P3** | `단독으로` | 지정 에이전트만 | 파이프라인 단계 축소 |
| **P3** | `코드만`/`구현만` | developer만 | 리뷰/테스트 생략 |
| **P3** | `TDD로` | qa 설계 → 사용자 확인 → developer Green → code-tester 실행 | qa/code-tester 분리 강제 |
| **P3** | `리뷰 없이` | 리뷰 단계 생략 | 구현/테스트 유지 |
| **P3** | `테스트 없이` | 테스트 단계 생략 | 구현/리뷰 유지 |
| **P3** | `스펙 없이` | SDD 스펙 생략 | 나머지 유지 |
| **P4** | `"기능 추가"`, `"feature"` | TYPE A: feature — TDD + 3중 리뷰 | `standard-routines.md` |
| **P4** | `"버그"`, `"fix"`, `"안 돼"` | TYPE B: bugfix — `/debug` → 회귀 | |
| **P4** | `"리팩터"`, `"정리"` (3파일+) | TYPE C: refactor — Gemini Phase 0 + worktree | |
| **P4** | `"UI"`, `"디자인"`, `"스타일"` | TYPE D: design — designer + Playwright | |
| **P4** | `"쿼리"`, `"대시보드"`, `"ClickHouse"` | TYPE E: data — data-analyst 필수 | |
| **P4** | `"배포"`, `"Docker"`, `"Terraform"`, `"SPI"` | TYPE F: ops — 🔴 사람 승인 + 단계별 검증 | |
| **P4** | `"문서"`, `"PRD"`, `"스펙"` | TYPE G: docs — po/prompt-engineer + Obsidian | |
| **P5** | UI 신호 감지 (`component`, `page`, `style`, `css`, `tsx`, `jsx`, `Tailwind`, `shadcn`, `버튼`, `화면`, `레이아웃`) | 1차 라우팅을 **frontend-developer 우선** | 재지정 21건 완화 |
| **P5** | 백엔드 신호 명시 (`API`, `endpoint`, `DB`, `migration`, `auth`, `JWT`, `FastAPI`, `Spring`) | backend-developer | UI 신호 없을 때만 |
| **P5** | 풀스택 혼합 신호 | **2트랙 병렬**: frontend-developer(UI) + backend-developer(API), 통합은 dev-lead | 재지정/왕복 감소 |
| **P5** | 신호 불명확 | **현재 호출/직전 에이전트 유지** (추천 hook 제거됨 2026-06-01, 채택률 7%였음) | 추측 라우팅 금지 |
| **P6** | 운영성 명령 (`재시작`, `재설치`, `서비스`, `로그 봐`, `상태 확인`, `restart`, `재배포`) | 현재 작업 컨텍스트 유지 (직전 에이전트 재사용) — 없으면 ops-lead | 세션 35cdacf2 실측: "서비스 재시작해줘" 등이 ops로 빗나갔다가 frontend로 재지정 3회. **운영 명령은 메인 작업 흐름 끊지 말 것** |
| **P6** | 세션 내 직전 에이전트 동일 도메인 (UI/API/ops) 3턴 이상 지속 시 | **sticky routing** — 동일 에이전트 재사용. 짧은 운영 명령에 재분류 금지 | 같은 세션 1차 분류 반복 빗나감 방지 |
| **P6** | `codex:codex-rescue` 종료 후 다음 발화 | rescue 직전 작업 컨텍스트 유지 (frontend/backend 분류 그대로) | rescue 후 frontend로 빗나간 2회 패턴 차단 |

### @dev 태스크 관리 (P0 보조)

- `@dev backlog` — backlog.md 최상위 1개 → active/ 생성 → 실행
- `@dev backlog 전체` — backlog 순차 처리
- `@dev active` — active/ 미완료 순차 처리
- `@dev active {파일명}` — 특정 active 파일만
- `@dev {직접 지시}` — 즉시 라우팅

## 도구 역할 분담

- **Claude Code**: 판단/채택/최종 구현/의사결정
- **Codex MCP**: 병렬 구현+검증+리뷰+세컨드 오피니언
- **Gemini**: Phase 0 스캔(1M토큰)+테스트 생성+3중 리뷰+최종 통합 검증
- **Antigravity**: 멀티 에이전트 디스패치
- **Jules**: 백그라운드(테스트/문서/PR)
- **Deep Research**: 기술 조사/전략

## 자동 위임 트리거 (룰 — 명시 지시 없을 때 적용)

> **실측 근거 (2026-05-25)**: 14일 사용량 Claude 99.5% / Codex 0.7% / Gemini 0.05%. 위임 hook이 권유만 하던 시기의 결과. **50줄+ Edit/Write는 hook이 차단형(exit 2)으로 동작 — 우회 키워드는 "직접 구현해"/"직접 작성해"**.

| 조건 (조기 매칭 우선) | 1순위 위임 | 모델 | 비고 |
|----------------------|------------|------|------|
| **50줄+ 코드 작성/Edit (장문/복잡)** | **Codex MCP** (`mcp__codex-cli__codex`) | **gpt-5.5** | hook이 차단. 장문 컨텍스트 +37pp 우수 |
| **50줄+ 단순 반복 보일러플레이트** | **Codex MCP** | **gpt-5.4** | 단가 1/2, 단순 패턴엔 충분 |
| **신규 파일 100줄+** | **Codex MCP** | **gpt-5.5** | 토큰 효율 + 장문 일관성 |
| **코드베이스 영향도 조사 (3파일+ 스캔/분석)** | **Skill(ask-gemini)** — Gemini 1M 컨텍스트 | gemini-3-flash | Claude는 합성만, 토큰 절약 |
| **리팩터링 사전 스캔 (TYPE C)** | **Gemini** Phase 0 (자동) | gemini-3-pro | `workflows/standard-routines.md` |
| **단순 번역/요약/문법 (200자 이하)** | **Skill(ask-ollama)** | qwen3.5:9b | 로컬, 무료, 빠름 |
| **세컨드 오피니언 / 패치 검토** | **Codex + Gemini 병렬** | gpt-5.5 + gemini-3-pro | 편향 방지, 단일 메시지 병렬 |
| **빠른 질의 / 리뷰 코멘트 / 짧은 분석** | **Codex** | **gpt-5.5** (default) | 실측: 세션당 252K 토큰 가벼움 |
| **디버깅 2회 실패** | 접근 재검토 | — | `workflows/debugging.md` |
| **디버깅 3회 실패** | **codex:codex-rescue** | gpt-5.5 | hook 자동 트리거 |
| **테스트 3회 실패 / PR 생성 / 프로젝트 전환** | 각 hook이 자동 발동 | Codex/Gemini | `workflows/automation.md` |
| **사용자 "직접 구현해" / "직접 작성해" 명시** | Claude 직접 (위임 우회) | — | hook 통과 |

### Codex 모델 선택 가이드 (실측 + 벤치 근거)

| 모델 | 단가(입/출, /1M) | 강점 | 사용처 |
|------|------------------|------|--------|
| **gpt-5.5** | $5 / $30 (2×) | 장문 컨텍스트 512K~1M 74% (vs 5.4 36.6%), Terminal-Bench 82.7%, ARC-AGI-2 +11.7pp, 동일 작업 시 토큰 적게 씀 | **기본값** — 코드 생성, 리뷰, 장문 분석, 복잡한 추론 |
| **gpt-5.4** | $2.50 / $15 (1×) | 단순 반복 패턴엔 5.5와 차이 미미, 단가 1/2 | 단순 보일러플레이트, 단발성 짧은 작업 |
| **gpt-5.3-codex** | — | Codex 전용 튜닝 | codex-rescue, 디버깅 |
| **gpt-5.4-mini** | 최저 | 빠른 응답 | 분류/라우팅 |

**기본 규칙**: 모델 명시 안 했을 때 Codex 호출은 **gpt-5.5 default**. 단순 반복 패턴이 명확하면 gpt-5.4로 비용 절감.

**근거**: GPT-5.5는 단가 2배지만 동일 작업 토큰 효율 좋아 실비용 차이 작음. 14일 실측: 5.5 세션당 $1.68 (252K토큰) / 5.4 세션당 $16.30 (2.86M토큰).

Sources:
- [LLM Stats — GPT-5.5 vs 5.4](https://llm-stats.com/blog/research/gpt-5-5-vs-gpt-5-4)
- [OpenAI — Introducing GPT-5.5](https://openai.com/index/introducing-gpt-5-5/)

### 위임 우회 조건 (정당한 직접 작성)

다음 경우만 50줄+ 직접 작성 허용 (위임 hook 우회 시 사용자 확인 받을 것):
- 사용자가 명시적으로 "직접" 키워드 사용
- 긴급 hotfix (5분 내 운영 복구 필요)
- 1줄짜리 반복 패턴 (예: import 50개 일괄 정리 — 이건 codemod가 더 빠름)
- Claude의 판단/통합/최종 정리 단계 (Codex 결과물 머지)

### 위임 효과 측정 (2026-06-01 지표 재설계)

- **주지표 = 조건 충족률** (비율 아님): "위임 트리거 조건(50줄+ 구현 / 신규파일 100줄+ / 3파일+ 조사 / 세컨드오피니언·리뷰)이 발생했을 때 실제로 위임됐는가"의 충족률. 단순 질의·짧은 패치까지 위임 강요하지 않으므로 전체 Claude 비율 99%대는 정상일 수 있음.
- 참고지표: 주간 `/usage` 로 Codex/Gemini 누적 토큰·호출 추세 (절대 비율 목표 아님). 실측 14일: Codex 104회 / Gemini~agy 30회 — 위임 인프라 작동 중.
- 폐기: "Claude 70%" 절대 비율 목표 (측정 지표로 부적절, 14일 미동 확인 2026-06-01).

## 디버깅 규칙

추측 금지. 7단계 절차(재현→수집→범위축소→가설→검증→수정→확인). 2회 실패 시 접근 재검토, 3회 실패 시 `codex:codex-rescue`. 상세: `workflows/debugging.md`

## SSH 접속 규칙

- `expect` 스크립트로 접속 (비밀번호 자동 입력). `ssh` 직접 실행 시 대화형에서 멈춤
- MCP SSH 도구(`mcp__ssh__runRemoteCommand`) 가능하면 우선 사용

## 커밋 규칙

- **Co-Authored-By 절대 금지** (PreToolUse 훅이 차단)
- 커밋 메시지 한글

## 코딩 컨벤션

공백 4칸(Makefile/Go 제외). 파일 상단 수정이력 주석 금지. FastAPI 는 `Annotated` 앨리어스. 약어/줄임 네이밍 금지. 상세: `workflows/coding-convention.md`

## 문서 작성 규칙

상세: `@~/.claude/workflows/docs-convention.md`

- Obsidian Vault: `~/Workspace/weaversbrain/weaversbrain/`
- 파일명에 시분: `YYYY-MM-DD-HHMM-{파일명}.md`
- YAML frontmatter 필수
- 프로젝트 내부(docs/) 금지 → Obsidian Vault

### 문서 링크 표기 규칙 (필수)

| 위치 | 표기 |
|------|------|
| **Obsidian Vault 내부** (`~/Workspace/weaversbrain/weaversbrain/` 하위) | **두 링크 모두 병기** — ① `obsidian://open?vault=weaversbrain&file={vault_root_기준_경로(확장자 제외, URL 인코딩)}` ② `antigravity-ide://file/{절대경로}` (또는 `open -a "Antigravity IDE" {절대경로}`) |
| **Vault 외부 일반 파일** (코드/프로젝트/.claude/ 등) | **Antigravity IDE 링크만** — `antigravity-ide://file/{절대경로}` (URL 미지원 환경이면 `open -a "Antigravity IDE" {절대경로}`) |

- Obsidian 링크는 vault 외부 파일에는 동작하지 않음 → 외부 파일에 obsidian:// 절대 쓰지 말 것
- Antigravity IDE URL 스킴: `antigravity-ide://` (앱 번들 `com.google.antigravity-ide`, `/Applications/Antigravity IDE.app`). 구버전 `Antigravity.app` (`com.google.antigravity`)이 등록한 `antigravity://` 와 다름 — 사용자 환경의 IDE 본체는 `antigravity-ide://` 이다. 환경별로 동작 다를 수 있어 `open -a "Antigravity IDE"` 폴백 함께 안내
- 검증 명령: `/usr/bin/plutil -p "/Applications/Antigravity IDE.app/Contents/Info.plist" | grep -A 5 CFBundleURLSchemes` 로 실측 가능

## 워크플로우 자동화

hooks 가 자동 처리: 의존성 변경→Gemini, 테스트 3회 실패→Codex rescue, PR 생성→Codex 요약, 프로젝트 전환→Gemini 스캔. 규모 자동 판별(S/M/L), 파이프라인 메트릭, 결정 자동 캡처도 훅으로. 회고: `/retro [N일]`, `/decisions [검색어]`. 상세: `workflows/automation.md`

## MoAI 출력 스타일 활성 시 보강 룰 [HARD]

`outputStyle: "MoAI"` 활성 시(프로젝트 `~/.claude/.claude/settings.json`) 다음 보강 룰이 MoAI 본문보다 우선한다. MoAI 본문은 `expert-*/manager-*` 22개만 §4 Forced Delegation Table에 등재하지만, 글로벌 `~/.claude/agents/` 19개 + 프로젝트 `dev.md` 까지 합쳐 총 41+개 에이전트가 존재한다. MoAI는 이를 모르므로 보강 필요.

### 라우팅 우선순위 (MoAI §4보다 위)

1. **P0/P1 한글 호출 우선** — `백엔드/프론트/리뷰어/디자이너/큐에이/테스터/피오/데이터/옵스/프롬프트/AI엔지니어` 명시 호출 시 글로벌 `~/.claude/agents/` 우선. MoAI Stage 2 Delegation 단계에서도 이 표가 §4를 덮어쓴다.
2. **`@dev` P0 우선** — 프로젝트 `dev.md` 있으면 그쪽, 없으면 글로벌 `dev-lead`. MoAI §4의 `manager-*` 우회.
3. **MoAI §4 표는 한글 호출/`@dev`/`@team` 미매칭일 때만 적용** — 영문 작업 키워드(security, performance, refactoring 등)는 그대로 expert-*/manager-* 라우팅.
3-bis. **중복 8개 도메인은 MoAI 자율 위임 시에도 글로벌 두꺼운 agent 우선** [HARD] — 명시 호출 없이 MoAI가 Stage 2에서 자율 위임할 때, 아래 도메인은 MoAI 본문 §4의 expert-*/manager-* 대신 **글로벌 `~/.claude/agents/` 우선 선택**. 근거: 글로벌 agent가 7배 두껍고(현장 패턴 다수) opus 고정이라 단발 구현·리뷰 품질 우위. 단 MoAI 워크플로(`/moai run`의 GAN 루프/Stage 게이트) **명시 진입 시에는 MoAI 본문 계약 우선**(constitution.md FROZEN 존중) — 워크플로 밖 일반 작업에서만 글로벌 우선.

| 도메인 | 글로벌 우선 (워크플로 밖) | MoAI 대응 (워크플로 안/명시 키워드) |
|--------|--------------------------|--------------------------------------|
| 백엔드/API/DB | `backend-developer` | expert-backend |
| 프론트/UI | `frontend-developer` | expert-frontend |
| 테스트 설계 | `qa` / 실행 `code-tester` | expert-testing |
| 코드 리뷰 | `code-reviewer` | manager-quality |
| 데이터/SQL/대시보드 | `data-analyst` | (MoAI 없음 → 글로벌 전담) |
| DevOps/배포/인프라 | `ops-lead` | expert-devops |
| 문서화 | `codebase-documenter` | manager-docs |
| AI/ML/RAG | `ai-engineer` | (MoAI 없음 → 글로벌 전담) |
| 프롬프트/PRD | `prompt-engineer` / `po` | (MoAI 없음 → 글로벌 전담) |
| 디버깅/근본원인 | `debug-master`(7단계) | expert-debug → `codex:rescue`(3회실패) |
| 멀티에이전트 리드 | `dev-lead` (또는 `@dev`) | (MoAI 오케스트레이터 본체가 담당) |

3-ter. **MoAI 전담 (글로벌 대응 없음 → 항상 MoAI)** — 다음은 글로벌에 없으므로 MoAI 본문 agent를 그대로 사용: `manager-spec`(EARS SPEC), `manager-tdd`/`manager-ddd`(TDD/DDD 사이클), `manager-git`, `expert-security`, `expert-performance`, `expert-refactoring`, `expert-debug`, `evaluator-active`(독립 평가), `plan-auditor`(SPEC 감사), `builder-agent`/`builder-skill`/`builder-plugin`(메타 생성), `manager-strategy`, `researcher`. 디버깅은 글로벌 `debug-master`(존재) 또는 MoAI `expert-debug`/`codex:rescue` — 7단계 절차는 `debug-master` 우선, 3회 실패 시 `codex:rescue`.

### 위임 강도 조정

4. **위임 트리거는 글로벌 자동 위임 트리거 표(50줄+ Codex, 영향도 Gemini, 단순 Ollama) 유지** — MoAI §2 `[HARD] No direct implementation of complex tasks`는 **50줄+ 또는 5+파일** 기준에서만 FORBIDDEN 강제. 그 미만 단순 작업(설정 한 줄, 짧은 스크립트 패치 등)은 Claude 직접 실행 허용. hook과 정합.
5. **단순 질의는 Stage 1 Clarify 생략 허용** — MoAI Stage 1 트리거 조건(모호한 대명사 등) 미충족 시 바로 응답. 예: "X 파일 어디 있어?" 같은 단답 질의.

### 외부 LLM 극대화 (agy/codex 통합) [HARD]

MoAI 본문 §4 Forced Delegation Table은 Claude 내부 에이전트(expert-*/manager-*)만 안다. 외부 LLM(codex/agy)은 모른다. 다음으로 보강 — **MoAI 오케스트레이터(메인 Claude)가 Stage 2에서 작업 성격에 따라 내부 에이전트와 외부 LLM을 골라/병렬로 위임**한다. MoAI 서브에이전트가 codex를 직접 부르게 하지 않는다(격리 컨텍스트 결과수집 불가).

7. **Stage 2 Delegation 확장 — 외부 LLM도 위임 후보** [HARD]
   - **대량 신규 구현(100줄+/신규파일)** → `codex exec --write` 위임 (expert-* 대신 또는 병렬, Claude 토큰 절약). 결과를 Claude가 검증·통합
   - **세컨드 오피니언/대안 구현(M/L 규모)** → expert-* 구현과 `Skill(ask-codex)` 또는 `codex exec` **병렬**, 최선안 채택
   - **코드베이스 영향도/대량 스캔(3파일+)** → `Skill(ask-gemini)` (agy 1M 컨텍스트). manager-strategy/researcher 대신 또는 선행
   - **디버깅 3회 실패** → `codex:rescue` (foreground). expert-debug 에스컬레이션
   - 호출 경로는 `workflows/codex.md`(codex), `skills/ask-gemini`(agy) 규약 준수. codex는 `codex exec`(codex -a 금지), agy는 `${GEMINI_CLI:-agy}` 또는 wrapper

8. **Stage 4 품질게이트 — codex 교차검증 병렬** [HARD]
   - **evaluator-active 검증 / >200 LOC 변경 / 보안·DB·API breaking** → `codex:review`(일반) 또는 `codex:adversarial-review`(고위험)를 **병렬** 실행, Claude 평가와 교차검증으로 편향 감소
   - MoAI GAN Loop(builder-evaluator)의 evaluator 단계에 codex 의견 추가 가능 — 단 MoAI 본문 GAN 계약(constitution.md FROZEN)은 변경 금지, 병렬 참고만
   - PR 생성 전 → `codex:review` 단독 + manager-git 병행

### MoAI 강점 유지

6. **다음은 MoAI 본문 그대로 따른다** — Stage 1~4 게이트, Progress Board, Persistence-Aware (auto-compaction 대응), Temp File Hygiene, Dark-Flow Warning, Fresh-Context Reviewer.

근거 (검증 일자 2026-05-30 갱신):
- 글로벌 `~/.claude/CLAUDE.md`, `~/.claude/agents/`, `~/.claude/skills/`, `~/.claude/workflows/`, `~/.claude/hooks/` 는 moai manifest(492개 파일, 기준 루트 `~/.claude/.claude/`) 등재 밖 → `moai update` 시 영향 없음 (safe zone). 실측 확인
- MoAI 본문(`~/.claude/.claude/agents/moai/*`, `output-styles/moai/moai.md`, `skills/moai-*`)은 manifest 관리 → update 시 덮어쓰기. 절대 보강 두지 말 것
- MoAI 출력 스타일 본문 fork는 유지보수 부담 큼 → 보강 룰을 글로벌에 두는 게 안전
- agy/codex 통합(룰 7·8)도 전부 글로벌 영역 → update 무영향. codex는 MCP 아닌 CLI/플러그인 경로(`codex exec`/`codex:`), agy는 6/18 gemini 종료로 기본 CLI. 상세: 메모리 [[codex-cli-not-mcp]], [[gemini-agy-migration]]
