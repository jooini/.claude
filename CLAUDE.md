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

## 에이전트 한글 호출

사용자가 호출명으로 시작하면 해당 에이전트 실행. 복수 호출명 → 병렬 실행.

| 호출명 | 에이전트 |
|--------|---------|
| 백엔드 | backend-developer |
| 프론트 | frontend-developer |
| AI엔지니어 | ai-engineer |
| 테스터 | code-tester |
| 리뷰어 | code-reviewer |
| 큐에이 | qa |
| 디자이너 | designer |
| 피오 | po |
| 데이터 | data-analyst |
| 옵스 | ops-lead |
| 프롬프트 | prompt-engineer |

### 프로젝트 에이전트

- `@dev` — 프로젝트 전담 리드. 프로젝트별 `.claude/agents/dev.md` 자체 라우팅. 글로벌 파이프라인 비적용 (이중 실행 방지)
- `@team` — 크로스 프로젝트 팀 구성

### @dev 태스크 관리

- `@dev backlog` — backlog.md 최상위 1개 → active/ 생성 → 실행
- `@dev backlog 전체` — backlog 순차 처리
- `@dev active` — active/ 미완료 순차 처리
- `@dev active {파일명}` — 특정 active 파일만
- `@dev {직접 지시}` — 즉시 라우팅

## 트리거 규칙

- **`@dev` 호출 시** → 프로젝트 dev.md 자체 라우팅. 글로벌 파이프라인 비적용
- **`@dev` 없이 직접 작업 시**:
  - 파이프라인 키워드 지정 → `workflows/pipeline.md` 참조
  - 키워드 없어도 **코드 파일 수정 발생** → Gemini 스캔 → developer → 병렬(reviewer + codex:review) → tester
- **설정/프롬프트/문서만 수정** → 파이프라인 불필요

## 파이프라인 단축 호출

| 키워드 | 동작 |
|--------|------|
| "코드만", "구현만" | developer 만, 리뷰/테스트 생략 |
| "리뷰 없이" | 리뷰 단계 생략 |
| "테스트 없이" | 테스트 단계 생략 |
| "단독으로" | 해당 에이전트만 |
| "TDD로" | qa 테스트 설계 → 사용자 확인 → developer Green |
| "스펙 없이" | SDD 스펙 작성 생략 |

## 작업 타입 자동 라우팅

키워드 감지 시 `workflows/standard-routines.md` 의 TYPE 루틴 적용:

| 키워드 | TYPE | 핵심 |
|--------|------|------|
| "기능 추가", "feature" | A: feature | TDD + 3중 리뷰 |
| "버그", "fix", "안 돼" | B: bugfix | /debug → 회귀 |
| "리팩터", "정리" (3파일+) | C: refactor | Gemini Phase 0 + worktree |
| "UI", "디자인", "스타일" | D: design | designer + Playwright |
| "쿼리", "대시보드", "ClickHouse" | E: data | data-analyst 필수 |
| "배포", "Docker", "Terraform", "SPI" | F: ops | 🔴 사람 승인 + 단계별 검증 |
| "문서", "PRD", "스펙" | G: docs | po/prompt-engineer + Obsidian |

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
