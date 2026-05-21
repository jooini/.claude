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
> **실측 근거 (2026-05-21 정정)**: `~/.claude/cache/md-live/suggestion-outcomes.jsonl` 16건 분석 — suggest hook의 frontend 추천 15건 중 **채택 0건(0%)**, 81%가 ignored. **현재 호출 에이전트가 옳고 hook 추천이 틀림**. P5는 추측 휴리스틱이 아니라 **명시 신호 기반**(UI 키워드 등장 시만 frontend) + **불명확 시 현재 호출 유지**로 운영. 기존 routing-memo의 "21/24 frontend" 통계는 hook 추천 흔적이지 사용자 채택률이 아님.

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
| **P5** | 신호 불명확 | **현재 호출/직전 에이전트 유지** (frontend 추천 채택률 0/15 = 0%, 사용자는 추천 무시 81%) | 추측 라우팅 금지 |
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
- 경로 안내 시 `obsidian://open?vault=weaversbrain&file={경로(확장자 제외, URL 인코딩)}` URI

## 워크플로우 자동화

hooks 가 자동 처리: 의존성 변경→Gemini, 테스트 3회 실패→Codex rescue, PR 생성→Codex 요약, 프로젝트 전환→Gemini 스캔. 규모 자동 판별(S/M/L), 파이프라인 메트릭, 결정 자동 캡처도 훅으로. 회고: `/retro [N일]`, `/decisions [검색어]`. 상세: `workflows/automation.md`
