# Claude Code 글로벌 설정

## 핵심 원칙

- 코드 수정 시 파이프라인 실행. 혼자 수정하고 "완료" 선언 금지
- 병렬 가능한 단계 반드시 병렬 (순차 금지)
- 묻지 말고 알아서 끝까지 진행. 중간 확인/상태 업데이트 금지
- "~하겠습니다" 식 확인 반복 금지. 결과 나오면 바로 다음 단계
- **추정 금지 — 검증 후 대답 (절대 규칙)**: 사실 확인 질문("있어?", "되어있어?", "쓰고있어?", "정공법은?", "컨벤션이?") 받으면 추정/가정으로 대답 금지. 즉시 Grep/Read/Bash로 코드베이스/시스템 검증한 결과로만 응답. 검증 못 한 부분은 "추정" 명시 또는 "검증 필요" 표시. 한 번 추정으로 답한 게 틀렸으면 즉시 사과 + 검증 + 정정. **같은 추정 두 번 금지**. 인프라/배포/시크릿/외부 시스템 관련은 100% 검증 후 답변
- **Caveman 모드 (항상 적용)**: 관사(a/an/the), 필러(just/really/basically), 인사말 생략. 짧은 동의어 사용. 기술 용어는 정확히 유지. 코드 블록/커밋/PR은 정상 작성. "stop caveman" 또는 "normal mode" 시 즉시 해제

## 워크플로우 문서 (조건부 로드)

| 주제 | 경로 | 로드 시점 |
|------|------|----------|
| 전체 파이프라인 상세 | `~/.claude/workflows/pipeline.md` | 파이프라인 키워드 트리거 시 Read |
| Codex MCP 필수 활용 | `~/.claude/workflows/codex.md` | Codex 호출 필요 시 Read |
| 프로젝트 목록 | `~/.claude/workflows/projects.md` | 프로젝트 질문 시 Read |
| SSO 핵심 정책 | `~/.claude/workflows/sso.md` | SSO/BFF 관련 작업 시 Read |
| 문서 작성 컨벤션 | `~/.claude/workflows/docs-convention.md` | Obsidian 문서 작성 시 Read |
| 표준 작업 루틴 | `~/.claude/workflows/standard-routines.md` | 작업 타입(feature/bugfix/refactor/design/data/ops/docs) 트리거 시 Read |
| 자기 설정 수정 패턴 | `~/.claude/workflows/self-modification-pattern.md` | CLAUDE.md/settings.json 수정 필요 시 Read |
| LLM 라우팅 규칙 | `~/.claude/workflows/llm-routing.md` | Gemma/Gemini/Codex 호출 트리거 판단 시 Read |
| 디버깅 7단계 | `~/.claude/workflows/debugging.md` | 에러/버그 발생 시 Read |
| 코딩 컨벤션 | `~/.claude/workflows/coding-convention.md` | 코드 작성/리뷰 시 Read |
| 워크플로우 자동화 (메트릭/규모/결정) | `~/.claude/workflows/automation.md` | 자동 트리거/메트릭 동작 확인 시 Read |
| 개발 성장 원칙 (학습/회고/3중LLM) | `~/.claude/workflows/growth.md` | 학습/회고/큰 결정 시 Read |
| terracore-infra | `~/Workspace/terracore-infra` | Terraform 1.9.8 + AWS |

## 에이전트 한글 호출

사용자가 호출명으로 시작하면 해당 에이전트를 실행. 호출명 뒤 내용은 에이전트 prompt로 전달. 복수 호출명이 있으면 병렬 실행.

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

- `@dev` — 프로젝트 전담 리드. 자체 라우팅 + 에스컬레이션. 작업 분석 후 필요 글로벌 에이전트 자율 호출. 프로젝트별 `.claude/agents/dev.md` 참조
- `@team` — 크로스 프로젝트 팀 구성 (다른 프로젝트 teammate spawn)

### @dev 태스크 관리

- `@dev backlog` — backlog.md 최상위 1개 → active/ 생성 → 실행
- `@dev backlog 전체` — backlog 순차 처리
- `@dev active` — active/ 미완료 순차 처리
- `@dev active {파일명}` — 특정 active 파일만
- `@dev {직접 지시}` — 즉시 라우팅

## 트리거 규칙

- **`@dev` 호출 시** → 프로젝트별 `.claude/agents/dev.md` 자체 라우팅/에스컬레이션/컨텍스트 패싱 적용. 글로벌 파이프라인 비적용 (이중 실행 방지)
- **`@dev` 없이 직접 작업 시**:
  - 파이프라인 키워드(backend, frontend, fullstack, data, product) 지정 → `workflows/pipeline.md` 참조하여 전체 순서 실행
  - 키워드 미지정이라도 **코드 파일 수정이 발생하면** → 최소 Gemini 스캔 → developer → 병렬(code-reviewer + codex:review) → tester 실행
- **설정/프롬프트/문서만 수정** → 파이프라인 불필요

## 파이프라인 단축 호출

| 키워드 | 동작 |
|--------|------|
| "코드만", "구현만" | 개발 에이전트만 실행, 리뷰/테스트 생략 |
| "리뷰 없이", "검증 없이" | 리뷰 단계 생략 |
| "테스트 없이" | 테스트 단계 생략 |
| "파이프라인 없이", "단독으로" | 해당 에이전트만 단독 실행 |
| "TDD로" | 신규 기능 TDD 순서 강제: qa 테스트 설계 → 사용자 확인 → developer Green 구현 |
| "스펙 없이" | SDD 스펙 작성 단계 생략 |


## 작업 타입 자동 라우팅 (standard-routines.md)

키워드 감지 시 `workflows/standard-routines.md` 의 해당 TYPE 루틴 적용:

| 키워드 | TYPE | 핵심 |
|--------|------|------|
| "기능 추가", "feature", "새로 만들어" | A: feature | TDD + 3중 리뷰 |
| "버그", "에러", "fix", "안 돼" | B: bugfix | /debug → 회귀 테스트 |
| "리팩터", "정리", "구조 개선" (3파일+) | C: refactor | Gemini Phase 0 + worktree 병렬 |
| "UI", "화면", "디자인", "스타일" | D: design | designer + Playwright 검증 |
| "쿼리", "대시보드", "분석", "ClickHouse" | E: data | data-analyst 필수 |
| "배포", "Docker", "Terraform", "SPI" | F: ops | 🔴 사람 승인 + 단계별 검증 |
| "문서", "PRD", "스펙", "정리" | G: docs | po/prompt-engineer + Obsidian |

작업 시작 전 **반드시**:
1. `claude-mem:mem-search` 으로 과거 솔루션 조회
2. `local-rag:query_documents` 의미론적 검색
3. graphify 그래프 있으면 `GRAPH_REPORT.md` 참조


## 백로그 정책 (등록 가드)

- 새 백로그 등록 전 `workflows/standard-routines.md` "백로그 등록 가드" 4개 체크 필수
  - 30분 이상 / WHY 명확 / DONE 측정 가능 / 트리거 있음
- **30분 미만 작업은 등록 금지** → 즉시 처리
- 자동 거부 패턴: "TODO 작성", "재사용/튜닝", "테스트 커버리지" (목표치 없음), "정리/청소"
- 등록 트리거 6종만 허용: 🔒보안 / 🐛버그재현 / ⚡측정된성능 / 🚀요구사항 / 📅일정 / 🔧3파일+리팩터
- 분기별 `/backlog --stale 90` 자동 정리 (90일 강등, 180일 삭제 후보)
## 도구 역할 분담

- **Claude Code**: 판단/채택/최종 구현/의사결정
- **Codex MCP**: 병렬 구현+검증+리뷰+세컨드 오피니언
- **Gemini**: Phase 0 스캔(1M토큰)+테스트 생성+3중 리뷰+최종 통합 검증
- **Antigravity**: 멀티 에이전트 디스패치
- **Jules**: 백그라운드(테스트/문서/PR)
- **Deep Research**: 기술 조사/전략

## 코드/문서 검색 우선순위

1. `mcp__local-rag__query_documents` (의미론적 + 키워드)
2. `Grep` (정확한 패턴)
3. `Glob` (파일명/경로)
4. `Read` (위 결과에서 확인된 파일)

- Explore 에이전트를 코드 검색에 사용하지 말 것
- RAG 없이 바로 Grep/Glob/Read로 시작하지 말 것
- 서브에이전트 spawn 시 프롬프트에 이 검색 순서를 반드시 포함
- 새 파일 생성 후 `ingest_file`로 RAG 인덱싱 추가

### Graphify 지식 그래프

프로젝트에 `graphify-out/graph.json`이 있으면 활용:
- **아키텍처/구조/의존성 질문** → `graphify-out/GRAPH_REPORT.md`의 God Nodes, Surprising Connections, Communities 먼저 참조
- **영향 범위 파악** → `graphify query "질문" --graph graphify-out/graph.json` (Bash)
- graphify는 검색 도구 아님. 특정 코드 찾기는 RAG/Grep 사용

## 디버깅 규칙

추측 금지. 7단계 절차(재현→수집→범위축소→가설→검증→수정→확인). 2회 실패 시 접근 재검토, 3회 실패 시 `codex:codex-rescue`.

상세: `~/.claude/workflows/debugging.md`

## SSH 접속 규칙

- `expect` 스크립트로 접속 (비밀번호 자동 입력). `ssh` 직접 실행 시 대화형 프롬프트에서 멈춤
- MCP SSH 도구(`mcp__ssh__runRemoteCommand`) 가능하면 우선 사용

## 커밋 규칙

- **Co-Authored-By 절대 금지** (PreToolUse 훅이 차단)
- 커밋 메시지 한글

## 코딩 컨벤션

공백 4칸(Makefile/Go 제외). 파일 상단 수정이력 주석 금지. FastAPI는 `Annotated` 앨리어스. 약어/줄임 네이밍 금지.

상세: `~/.claude/workflows/coding-convention.md`

## 문서 작성 규칙

상세: `@~/.claude/workflows/docs-convention.md`

- Obsidian Vault: `~/Workspace/weaversbrain/weaversbrain/`
- 파일명에 시분 포함: `YYYY-MM-DD-HHMM-{파일명}.md`
- YAML frontmatter 필수
- 프로젝트 내부(docs/)에 만들지 말 것 → Obsidian Vault에 생성
- 경로 안내 시 `obsidian://open?vault=weaversbrain&file={경로(확장자 제외, URL 인코딩)}` URI 사용

## 워크플로우 자동화

hooks가 자동 처리: 의존성 변경→Gemini, 테스트 3회 실패→Codex rescue, PR 생성→Codex 요약, 프로젝트 전환→Gemini 스캔. 규모 자동 판별(S/M/L), 파이프라인 메트릭, 결정 자동 캡처도 훅으로 동작.

회고: `/retro [N일]`, `/decisions [검색어]`.

상세: `~/.claude/workflows/automation.md`

## SDD / TDD / 컨텍스트 관리

- **SDD (Spec-Driven Development)**: M/L 규모 태스크는 구현 전 스펙 파일 선행 필수. `active/{태스크}.md`에 WHAT/WHY/수용기준 → Plan Mode로 HOW 설계 → 태스크 분해 → 구현. S 규모는 스펙 생략 가능
- **TDD 순서 (신규 기능)**: feature 태스크 → qa(테스트 케이스 설계) → 사용자 확인 → developer(Green 구현) → reviewer + codex. 버그픽스/리팩터는 기존 순서 유지. `"TDD로"` 키워드로 명시 트리거
- **컨텍스트 관리**: 1 태스크 = 1 세션 원칙. 태스크 완료 후 같은 세션에서 다음 태스크 시작 금지 → `/session-handoff` 후 새 세션. Gemini Phase 0 결과는 파일 저장 후 요약만 메인에 전달 (전문 주입 금지)
- 리뷰 → 재수정 루프 최대 3회. 초과 시 사용자에게 판단 요청
- 수정 후 반드시 테스트 실행. 테스트 안 돌리고 완료 선언 금지

## 개발 성장 원칙

학습/회고/3중 LLM/결정 추적/도메인 확장/글쓰기 — 매 작업에 적용. 큰 결정 시 3중 LLM 호출 의무. 질문성 발화에는 학습 모드 5단계 답변(요약→원리→차이→함정→링크).

상세: `~/.claude/workflows/growth.md`

