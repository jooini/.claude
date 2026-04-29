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

에러/버그 발생 시 반드시 순서. 추측 금지.

1. 재현 — 에러 재현 최소 명령/시나리오
2. 수집 — 로그, 스택트레이스, 변수 상태, DB 데이터
3. 범위 축소 — 네트워크/DB/로직/설정 중 어디
4. 가설 — 사실 기반 1~2개 도출
5. 검증 — 로그 추가, 디버그 출력, 조건 변경
6. 수정 — 검증된 원인만
7. 확인 — 재현 안 되는지 검증

- "이거 아닐까?" 추측 수정 금지
- 2회 실패 시 접근 방식 재검토
- 3회 실패 시 `codex:codex-rescue` foreground

## SSH 접속 규칙

- `expect` 스크립트로 접속 (비밀번호 자동 입력). `ssh` 직접 실행 시 대화형 프롬프트에서 멈춤
- MCP SSH 도구(`mcp__ssh__runRemoteCommand`) 가능하면 우선 사용

## 커밋 규칙

- **Co-Authored-By 절대 금지** (PreToolUse 훅이 차단)
- 커밋 메시지 한글

## 코딩 컨벤션

- **들여쓰기**: 공백 4칸 (탭 문자 금지. Makefile/Go 제외)
- **파일 상단 수정이력 주석 금지** — 컨트롤러/함수 단위에서 작성
- FastAPI: `Depends()` 직접 사용 금지 → `Annotated` 앨리어스 사용
- 클래스 리네이밍 시 파일명도 함께 변경
- 약어/줄임 네이밍 금지 → 풀네임 사용

## 문서 작성 규칙

상세: `@~/.claude/workflows/docs-convention.md`

- Obsidian Vault: `~/Workspace/weaversbrain/weaversbrain/`
- 파일명에 시분 포함: `YYYY-MM-DD-HHMM-{파일명}.md`
- YAML frontmatter 필수
- 프로젝트 내부(docs/)에 만들지 말 것 → Obsidian Vault에 생성
- 경로 안내 시 `obsidian://open?vault=weaversbrain&file={경로(확장자 제외, URL 인코딩)}` URI 사용

## Gemini/Codex 자동 트리거

hooks가 자동 처리: 의존성 변경→Gemini 분석, 테스트 3회 실패→Codex rescue, PR 생성→Codex 요약, 프로젝트 전환→Gemini 스캔.

추가 자동 트리거: 코드 구조 질문→Gemini 스캔, 업그레이드→Gemini 영향 스캔, 버그→Codex 재현, 설계 판단(3파일+)→Codex 세컨드 오피니언.

## 워크플로우 자동화 (메트릭·규모·결정)

훅 자동 동작:

- **규모 자동 판별** (`auto-scale-detect.sh`): UserPromptSubmit에서 파이프라인 키워드 감지 시 git diff 파일 수로 S(1~2)/M(3~5)/L(6+) 자동 라벨. 아키텍처 키워드 포함 시 무조건 L. 사용자가 "L 규모로" 명시하면 우선
- **파이프라인 메트릭** (`pipeline-metrics-log.sh`): PostToolUse(Agent)에서 에이전트별 실행 시간·성공여부 자동 기록 → `~/.claude/cache/metrics/YYYY-MM-DD.tsv`
- **결정 자동 캡처** (`decision-capture.sh`): code-reviewer/Plan/qa/po/developer 등 출력에서 "결정:", "채택:", "기각:", "Decision:", "Selected:", "Rejected:" 패턴 추출 → Obsidian Vault `decisions/` 자동 저장

회고 스킬:

- `/retro [N일]` — 파이프라인 효과 측정 리포트 (호출 빈도·평균 시간·실패율)
- `/decisions [검색어]` — 자동 캡처된 과거 결정 검색

## SDD / TDD / 컨텍스트 관리

- **SDD (Spec-Driven Development)**: M/L 규모 태스크는 구현 전 스펙 파일 선행 필수. `active/{태스크}.md`에 WHAT/WHY/수용기준 → Plan Mode로 HOW 설계 → 태스크 분해 → 구현. S 규모는 스펙 생략 가능
- **TDD 순서 (신규 기능)**: feature 태스크 → qa(테스트 케이스 설계) → 사용자 확인 → developer(Green 구현) → reviewer + codex. 버그픽스/리팩터는 기존 순서 유지. `"TDD로"` 키워드로 명시 트리거
- **컨텍스트 관리**: 1 태스크 = 1 세션 원칙. 태스크 완료 후 같은 세션에서 다음 태스크 시작 금지 → `/session-handoff` 후 새 세션. Gemini Phase 0 결과는 파일 저장 후 요약만 메인에 전달 (전문 주입 금지)
- 리뷰 → 재수정 루프 최대 3회. 초과 시 사용자에게 판단 요청
- 수정 후 반드시 테스트 실행. 테스트 안 돌리고 완료 선언 금지

## 개발 성장 원칙

본인 개발 성장을 강제하는 자동화 룰. 매 작업에 적용:

### 학습 자동화
- **모르는 개념 발화 시** → `learning-queue-capture.sh` hook이 자동 큐 추가
- **세션 종료 시** → `daily-learning-capture.sh` hook이 학습 노트 자동 생성
- **매주 일요일 14시** → `/deep-learn queue` 자동 실행 권장
- **모든 큰 결정 전** → `Skill(deep-research)` 의무 (마이그레이션/아키텍처)

### 답변 시 학습 모드 (질문성 발화일 때)
사용자가 "X가 뭐야?", "어떻게 동작?", "왜?" 발화 시 단순 답 금지. 다음 형식:
1. **한 줄 요약**
2. **핵심 원리** (왜 그렇게 동작)
3. **유사 개념과의 차이**
4. **함정/주의점** (실전)
5. **공식 문서 링크** (가능하면)

### 3중 LLM 활용 (성장 + 검증 동시)
큰 결정/비교/마이그레이션 시 **항상**:
- Gemini (1M 컨텍스트, 광범위 분석)
- Codex (세컨드 오피니언, 다른 관점)
- Gemma (로컬 빠른 검증)

→ 결과 통합 = 본인 학습 + 의사결정 품질

### 회고 강제
- 매일: `/done` 으로 일일 보고서
- 매주 금요일 17시: `/retro 7` 자동 (학습 누적 분석)
- 매월: 학습 노트 메타 회고 (`Learning/concepts/` 검토)

### 결정 추적
- `decision-capture.sh` hook 자동 캡처
- `/decisions {검색어}` 로 과거 결정 검색
- 결정 시 **반드시 이유 명시** (자동 캡처용)

### 도메인 확장 권장
같은 스택 반복 = 정체. 매주 다른 영역 1시간:
- 시스템 (Rust/Go), AI/ML (임베딩), 알고리즘, 다른 언어
- 결과물 → `~/Workspace/weaversbrain/weaversbrain/Learning/portfolio/`

### 글쓰기 강제
배운 거 글로 정리. `~/Workspace/weaversbrain/weaversbrain/Posts/` 에 주 1회.
형식: 문제 → 시도 → 해결 → 일반화

