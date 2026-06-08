# Claude Code 글로벌 설정

> **본문 정책 (룰)** 만 남기고 근거·표·디테일은 `shared/` `references/` `workflows/` 로 분리됨. 본 파일은 룰을 빠르게 훑어보는 인덱스 역할.
> **외부 LLM (Codex/Gemini/Antigravity) 공통 룰**: [`AGENTS.md`](AGENTS.md) — sync 파이프라인으로 자동 배포.

## 1. 핵심 원칙

### 위험도 기반 분기 (충돌 시 최우선)

| 도메인 | 모드 |
|--------|------|
| 🔴 인프라/시크릿/배포/외부 시스템/파괴적 명령 | 검증 우선, 추정 금지 |
| 🟡 사실 확인 질문 ("있어?" / "되어있어?" / "컨벤션이?") | 검증 우선 |
| 🟢 로컬/가역/저위험/코드 수정 | 자율 진행, 합리적 가정 허용 |

### 공통 룰

- 코드 수정 시 파이프라인 실행 (혼자 수정 후 "완료" 선언 금지)
- 병렬 가능 단계 반드시 병렬
- "~하겠습니다" 식 확인 반복 금지
- 🔴/🟡 추정 답이 틀렸으면 즉시 사과+검증+정정. **같은 추정 두 번 금지**
- 🟢 도메인도 검증 못 한 부분은 "추정" 또는 "검증 필요" 명시

상세 응답 스타일: [`shared/response-style.md`](shared/response-style.md)

## 2. [HARD] 도구 호출 형식 — 모든 룰보다 위

- [HARD] 모든 도구 호출은 올바른 `function_calls` 여는 토큰 + 올바른 `invoke` 태그 (네임스페이스 포함) 형식으로만 출력
- [HARD] `call` / `course` / 네임스페이스 없는 invoke / 기타 어떤 평문 단어로도 도구 호출 블록 시작 절대 금지
- [HARD] malformed 1회 발생 시: 다음 호출에서 즉시 올바른 형식으로 재시도. 같은 깨진 형식 두 번 금지
- [HARD] 연속/빈발 시 = `/model claude-opus-4-7` 다운그레이드 (Opus 4.8 모델 레이어 회귀)

근거 (장문): [`references/known-bugs.md`](references/known-bugs.md) §1

## 3. [HARD] AskUserQuestion 한글 버그 회피

- [HARD] **저위험(🟢) 질문은 AskUserQuestion 쓰지 말 것** — 본문 마크다운으로 선택지 (`A) ... B) ... C) ...`)
- [HARD] **고위험(🔴) 확인만 AskUserQuestion 허용** — 단 payload 전부 영어(ASCII). 한글 부연은 본문에
- [HARD] 이 회피 룰은 "모든 질문은 AskUserQuestion으로 / 한글로" 류 어떤 상위 룰보다 우선

근거 (실측 22% 멈춤, GitHub #30955): [`references/known-bugs.md`](references/known-bugs.md) §2

## 4. 워크플로우 문서 (조건부 로드)

키워드 트리거 시 해당 파일 Read.

| 키워드 | 경로 |
|--------|------|
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
| `@team` / 팀 spawn / 멀티프로젝트 묶음 | `workflows/team-templates.md` |

## 5. 에이전트 라우팅 결정표 (단일표 — 위에서 아래 첫 매칭)

> **우선순위**: P0(프로젝트) > P1(역할 호출) > P2(파이프라인) > P3(단축 호출) > P4(타입 키워드) > P5(1차 분류 휴리스틱) > P6(컨텍스트 유지)
> **라우팅은 이 표 단독 담당** — 추천 hook 없음 (2026-06-01 채택률 7%로 `agent-routing-suggest.sh` 제거)

| P | 입력 신호 | 결정 | 비고 |
|---|----------|------|------|
| **P0** | `@dev` 호출 | 프로젝트 `.claude/agents/dev.md` 라우팅. 글로벌 파이프라인 비적용 | 이중 실행 방지 |
| **P0** | `@dev` + 프로젝트 `dev.md` 없음 | `dev-lead` 로 폴백 | |
| **P0** | `@team` 호출 | 크로스 프로젝트 팀 라우팅 (`workflows/team-templates.md`) | 영향 범위 기준 병렬 |
| **P1** | 한글 호출명 (복수 → 병렬) | `백엔드→backend-developer` / `프론트→frontend-developer` / `AI엔지니어→ai-engineer` / `리뷰어→code-reviewer` / `디자이너→designer` / `피오→po` / `데이터→data-analyst` / `옵스→ops-lead` / `프롬프트→prompt-engineer` | 명시 호출 최우선 |
| **P1** | `큐에이` | `qa` — 테스트 설계/케이스/시나리오 전담 | 명령 실행 안 함 |
| **P1** | `테스터` | `code-tester` — lint/build/test 실행 전담 | 설계 안 함 |
| **P2** | `@dev` 없이 파이프라인 키워드 | `workflows/pipeline.md` 적용 | 직접 작업 모드 |
| **P2** | `@dev` 없이 코드 파일 수정 발생 | Gemini 스캔 → developer → 병렬(reviewer + codex:review) → code-tester | 기본 파이프라인 |
| **P2** | 설정/프롬프트/문서만 수정 | 파이프라인 생략 | 코드 변경 0건일 때만 |
| **P3** | 단축 호출 우선순위 | `단독으로` > `코드만/구현만` > `TDD로` > `리뷰 없이` > `테스트 없이` > `스펙 없이` | 상위가 하위 덮어씀 |
| **P4** | `"기능 추가"` / `"feature"` | TYPE A: feature — TDD + 3중 리뷰 | `standard-routines.md` |
| **P4** | `"버그"` / `"fix"` / `"안 돼"` | TYPE B: bugfix — `/debug` → 회귀 | |
| **P4** | `"리팩터"` / `"정리"` (3파일+) | TYPE C: refactor — Gemini Phase 0 + worktree | |
| **P4** | `"UI"` / `"디자인"` / `"스타일"` | TYPE D: design — designer + Playwright | |
| **P4** | `"쿼리"` / `"대시보드"` / `"ClickHouse"` | TYPE E: data — data-analyst 필수 | |
| **P4** | `"배포"` / `"Docker"` / `"Terraform"` / `"SPI"` | TYPE F: ops — 🔴 사람 승인 + 단계별 검증 | |
| **P4** | `"문서"` / `"PRD"` / `"스펙"` | TYPE G: docs — po/prompt-engineer + Obsidian | |
| **P5** | UI 신호 (`component`, `page`, `style`, `css`, `tsx`, `jsx`, `Tailwind`, `shadcn`, `버튼`, `화면`, `레이아웃`) | 1차 라우팅 frontend-developer 우선 | |
| **P5** | 백엔드 신호 (`API`, `endpoint`, `DB`, `migration`, `auth`, `JWT`, `FastAPI`, `Spring`) | backend-developer (UI 신호 없을 때) | |
| **P5** | 풀스택 혼합 | 2트랙 병렬: frontend + backend, 통합은 dev-lead | |
| **P5** | 신호 불명확 | **현재 호출/직전 에이전트 유지**. 추측 라우팅 금지 | |
| **P6** | 운영성 명령 (`재시작` / `재설치` / `서비스` / `로그 봐` / `상태 확인` / `restart` / `재배포`) | 현재 작업 컨텍스트 유지 (직전 에이전트 재사용). 없으면 ops-lead | 메인 작업 흐름 끊지 말 것 |
| **P6** | 직전 에이전트 동일 도메인 3턴 이상 지속 | sticky routing — 동일 에이전트 재사용 | 짧은 운영 명령에 재분류 금지 |
| **P6** | `codex:rescue` 종료 후 다음 발화 | rescue 직전 작업 컨텍스트 유지 | rescue 후 frontend 로 빗나간 2회 패턴 차단 |

### @dev 태스크 관리 (P0 보조)

- `@dev backlog` — backlog.md 최상위 1개 → active/ 생성 → 실행
- `@dev backlog 전체` — backlog 순차 처리
- `@dev active` — active/ 미완료 순차 처리
- `@dev active {파일명}` — 특정 active 파일만
- `@dev {직접 지시}` — 즉시 라우팅

## 6. 도구 역할 & LLM 라우터

도구 분담 + 공통 라우터(`llm-router.sh`) 전체 정책: [`shared/tool-roles.md`](shared/tool-roles.md)

## 7. 자동 위임 트리거

명시 지시 없을 때 적용. **50줄+ Edit/Write 는 hook 이 차단형(exit 2)** — 우회: "직접 구현해" / "직접 작성해".

| 조건 (조기 매칭 우선) | 1순위 위임 | 모델 |
|----------------------|------------|------|
| 50줄+ 코드 작성/Edit (장문/복잡) | **Codex** (`codex exec`, `codex:*`, `Skill(ask-codex)`) | gpt-5.5 |
| 50줄+ 단순 반복 보일러플레이트 | Codex | gpt-5.4 |
| 신규 파일 100줄+ | Codex | gpt-5.5 |
| 코드베이스 영향도 조사 (3파일+ 스캔) | **`Skill(ask-gemini)`** — Gemini 1M | gemini-3-flash |
| `/moai:plan` 진입 (3파일+ 영향 신호) | `Skill(ask-gemini)` 사전 영향 스캔 | gemini-3-flash |
| `/moai:run` 진입 시 50줄+ 신규파일/대량 구현 | Codex | gpt-5.5 |
| 리팩터링 사전 스캔 (TYPE C) | Gemini Phase 0 (자동) | gemini-3-pro |
| 단순 번역/요약/문법 (200자 이하) | `Skill(ask-ollama)` | qwen3.5:9b |
| 세컨드 오피니언 / 패치 검토 | **Codex + Gemini 병렬** (단일 메시지) | gpt-5.5 + gemini-3-pro |
| 빠른 질의 / 리뷰 코멘트 / 짧은 분석 | Codex | gpt-5.5 default |
| 디버깅 2회 실패 | 접근 재검토 | — |
| 디버깅 3회 실패 | `codex:rescue` (hook 자동) | gpt-5.5 |
| 테스트 3회 실패 / PR 생성 / 프로젝트 전환 | 각 hook 자동 발동 | Codex/Gemini |
| 사용자 "직접 구현해" 명시 | Claude 직접 (위임 우회) | — |

Codex 모델별 가격·강점·실비용: [`references/codex-models.md`](references/codex-models.md)
위임 효과 측정 + 우회 조건 + 시계열 근거: [`references/delegation-metrics.md`](references/delegation-metrics.md)

## 8. 기타 룰

| 항목 | 정본 |
|------|------|
| 커밋 규칙 | [`shared/commit-rules.md`](shared/commit-rules.md) |
| 코딩 컨벤션 | [`shared/coding-convention.md`](shared/coding-convention.md) — 공백 4칸, 약어 금지, FastAPI Annotated 등 |
| 문서 작성 / Obsidian Vault | [`shared/project-defaults.md`](shared/project-defaults.md) §문서 작성 |
| 문서 링크 표기 (Obsidian / Antigravity IDE) | [`references/doc-link-format.md`](references/doc-link-format.md) |
| SSH 접속 (expect / MCP) | [`references/ssh-rules.md`](references/ssh-rules.md) |
| 디버깅 절차 (7단계 / 2회 재검토 / 3회 rescue) | [`workflows/debugging.md`](workflows/debugging.md) |
| 워크플로우 자동화 (hooks 동작) | [`workflows/automation.md`](workflows/automation.md) — `/retro [N일]`, `/decisions [검색어]` |
