# 표준 작업 루틴

> CLAUDE.md에서 `@~/.claude/workflows/standard-routines.md` 로 참조됨.
> 작업 타입을 선언하면 해당 루틴을 그대로 적용한다. 자율성 매트릭스(🟢🟡🔴) 동일 적용.

## 일일 루틴

| 시점 | 명령 | 효과 |
|------|------|------|
| 출근 | `/start` | 오늘 할 일 수집 → 작업 선택 → 브랜치 생성 |
| 점심 전 | `/today` | 캘린더/PR/이슈/노트 리마인드 |
| 작업 중 막힘 | `/debug` | 재현→수집→가설→검증 자동 진행 |
| 작업 완료 | `/go` | E2E 테스트 + 단순화 검증 |
| 퇴근 | `/done` | 미커밋 정리 → 일일 보고서 → 세션 저장 |

추가:
- 주간(금요일): `/retro 7` — 파이프라인 효과 측정
- 월간: `/backlog --stale 30` — 방치된 백로그 정리

## 작업 타입별 표준 루틴

### TYPE-A: 신규 기능 (feature) — TDD 강제

트리거: "기능 추가", "feature", "새로 만들어"

```
1. /backlog 또는 active/{태스크}.md 작성 (WHAT/WHY/수용기준)
2. mem-search으로 과거 유사 솔루션 조회
3. Gemini Phase 0 스캔 (영향 범위)
4. qa → 테스트 케이스 설계
5. 사용자 확인 (테스트 케이스 OK?)
6. developer (backend/frontend) → Green 구현
7. 병렬 리뷰: code-reviewer + codex:review + Gemini 심층 (3중)
8. tester → lint/build/test
9. /go → E2E + 단순화
10. 결정 자동 캡처 확인 → /done
```

키워드: `"TDD로 기능 추가"` → 자동 적용

### TYPE-B: 버그 수정 (bugfix)

트리거: "버그", "에러", "fix", "안 돼"

```
1. /debug → 재현/수집/가설/검증 자동
2. 2회 실패 시 접근 재검토
3. 3회 실패 시 codex:codex-rescue foreground
4. 수정 후 회귀 테스트 추가
5. code-reviewer 단독 리뷰 (속도 우선)
6. tester
7. /go
```

### TYPE-C: 리팩터 (refactor) — 3파일+ 무조건 L

트리거: "리팩터", "정리", "구조 개선"

```
1. Gemini Phase 0 (의존성 그래프 + God Nodes 식별)
2. Plan agent → 단계별 분해 (worktree 추천)
3. 병렬 worktree 디스패치 (superpowers:dispatching-parallel-agents)
4. 각 worktree: developer → tester
5. 통합 시 Gemini 최종 통합 검증
6. 3중 리뷰
```

### TYPE-D: 디자인/UI (design)

트리거: "UI", "화면", "디자인", "스타일"

```
1. designer → 와이어프레임/스펙 (필요 시 frontend-design 스킬)
2. 사용자 확인
3. frontend-developer → 구현
4. Playwright MCP로 실제 브라우저 검증 (스크린샷)
5. designer → 디자인 일관성 리뷰
6. code-reviewer
```

### TYPE-E: 데이터/SQL/대시보드 (data)

트리거: "쿼리", "대시보드", "분석", "ClickHouse"

```
1. data-analyst → 쿼리 설계/최적화
2. Gemini → 실행 계획 영향 분석
3. 검증 환경에서 실행 (프로덕션 직접 금지)
4. data-analyst → 결과 해석
5. 대시보드면 designer 협업
```

### TYPE-F: 인프라/배포 (ops)

트리거: "배포", "인프라", "Docker", "Terraform", "Keycloak SPI"

```
1. 검증 필수 (추정 금지) — 현재 상태 확인
2. Plan agent → 배포 절차 분해
3. 사용자 승인 (🔴 사람 승인 필수)
4. 단계별 실행 + 각 단계 후 /check-server, /deploy-status
5. ops-lead → 결과 정리
```

### TYPE-G: 문서/스펙 (docs)

트리거: "문서", "PRD", "스펙", "정리"

```
1. po (PRD) 또는 prompt-engineer (프롬프트) 또는 ops-lead (운영문서)
2. Obsidian Vault에 작성 (~/Workspace/weaversbrain/weaversbrain/)
3. 파일명: YYYY-MM-DD-HHMM-{이름}.md + frontmatter
4. Gemini → 요약/리뷰
```

## 세컨드 오피니언 강제 트리거

다음 상황에서 **반드시** 세컨드 오피니언 호출:

| 상황 | 호출 |
|------|------|
| 아키텍처 결정 | Codex + Gemini + Gemma 3중 |
| 의존성 추가/업그레이드 | Gemini 영향 분석 |
| 보안/인증 변경 | codex:adversarial-review |
| 민감 데이터 포함 | Gemma (외부 차단) |
| 3파일+ 수정 | Gemini Phase 0 |
| 버그 2회 실패 | Codex rescue |
| 설계 망설임 | Gemma 빠른 의견 |

## 백로그 트랙 정책 (v4)

모든 백로그 항목은 **트랙(Track)** 을 가져야 한다. 트랙은 도메인/실행 컨텍스트 분류로, 메인 작업 흐름이 메타 작업(테스트/문서/CI)에 의해 끊기는 것을 방지한다.

### 7개 표준 트랙

| 트랙 | 영역 | 메인/메타 | 예시 |
|------|------|---------|------|
| `backend` | API/서버 로직 | 메인 | 라우트 추가, 비즈니스 로직, DB 쿼리 |
| `frontend` | UI/페이지 | 메인 | 컴포넌트, 라우트, 상태 관리 |
| `data` | SQL/분석/대시보드 | 메인 | ClickHouse 쿼리, 지표, View |
| `infra` | 배포/Docker/IaC | 메인 | Terraform, K8s, CI/CD 정상화 |
| `auth` | 인증/권한 | 메인 | JWT/JWKS, OAuth, RBAC, PII |
| `ops` | 운영/모니터링 | 메타 | 알림, 로그, 헬스체크, 대응 룰 |
| `meta` | 문서/테스트/리팩터 | 메타 | 테스트 커버리지, 리팩터, 문서 보강 |

### `@dev backlog` 진입 규칙

| 호출 형태 | 동작 |
|----------|------|
| `@dev backlog` | **메인 트랙만** 후보 (backend/frontend/data/infra/auth). 메타 트랙 자동 제외 |
| `@dev backlog {트랙}` | 해당 트랙만 필터 (예: `@dev backlog data`) |
| `@dev backlog meta` | 메타 트랙(ops/meta) 명시 진입. 메인 작업 일단락 시점에만 사용 권장 |
| `@dev backlog 전체` | 트랙 무시, 전 항목 순회 (분기별 점검용) |

### 트랙 분류 결정 규칙 (충돌 시)

1. **주 영향 파일 디렉토리**로 결정 (`lib/auth.ts` → `auth`)
2. 여러 영역 걸치면 → **가장 큰 변경 영역** (예: API 추가 + UI 호출 → `backend`)
3. 외부 의존 블로킹 항목 → 트랙 유지하되 상태를 `blocked(사유)` 로

### 메타 트랙 격리 강도

- **자동 격리**: `@dev backlog` 무지정 시 메타 절대 진입 금지
- **예외**: 메타이지만 P=H 인 항목은 backlog 최상단에 ⚠️ 표식 (사용자가 명시 호출 결정)
- **별도 파일 분리 안 함**: `backlog.md` 단일 유지, 섹션으로만 분리

## 백로그 등록 가드 (노이즈 방지)

새 항목 등록 전 5개 체크 다 통과해야 함:

| 체크 | 통과 기준 | 미달 시 |
|------|----------|---------|
| 30분 이상? | 작업량 ≥ 30분 | 즉시 처리 (등록 X) |
| WHY 명확? | 한 줄로 근거 작성 가능 | 등록 보류 |
| DONE 측정 가능? | 끝났는지 판단 기준 있음 | 측정 가능하게 다시 쓰기 |
| 트리거 있음? | 보안/장애/요구사항/일정 | "언젠가" 항목 → 등록 X |
| 트랙 명확? | 7개 트랙 중 하나로 분류 가능 | 분류 모호 시 작업 쪼개기 |

### 자동 거부 패턴 (등록 금지)

- "TODO 작성", "체크리스트 작성", "문서화" — **메타 백로그**
- "재사용", "튜닝", "최적화" (성능 트리거 없음) — **추측 최적화**
- "테스트 커버리지" (목표치 없음) — **측정 불가**
- "정리", "청소" (5분짜리) — **즉시 처리**

### 등록 트리거 (다음 6개 중 하나만 등록)

1. 🔒 보안 이슈 발견 (실제 취약점)
2. 🐛 버그 재현됨 (지금 못 고치는 경우)
3. ⚡ 성능 문제 측정됨 (수치로)
4. 🚀 기능 요구사항 (PO/사용자)
5. 📅 일정 있는 마이그레이션
6. 🔧 리팩터 (3파일+ 영향, 즉시 못 함)

### 백로그 만료 정책

- 등록 후 **90일 미처리** → 자동 강등 (H→M, M→L, L→삭제 후보)
- 등록 후 **180일 미처리** → 삭제 후보 알림
- 분기별 `/backlog --stale 90` 실행 강제

### 등록 시 필수 정보

```markdown
### {ID} — {제목}
- 트랙: backend|frontend|data|infra|auth|ops|meta (1개 필수)
- 위치: `path/to/code.py:123` 또는 `해당 모듈/엔드포인트`
- 트리거: 🔒/🐛/⚡/🚀/📅/🔧 중 하나 + 구체 사유
- DONE: 끝났는지 판단할 측정 기준 (예: "X엔드포인트가 Y 응답 반환", "테스트 N개 추가 후 통과")
- 추정: 30m / 1h / 2h / 1d / 2d
```

위 5개 필드 중 하나라도 못 채우면 등록 금지.

## 메모리/검색 우선순위 (작업 시작 전)

```
1. claude-mem:mem-search → "이전에 같은 문제 풀었나?"
2. local-rag:query_documents → 의미론적 코드 검색
3. Grep/Glob/Read → 정확 검색
```

검색 안 하고 바로 추정 → 같은 추정 두 번 금지 규칙 위반.

## Deep Research 의무화 케이스

다음 상황에서 **반드시** `deep-research` 스킬 또는 `mcp__codex-cli__websearch` 선행:

| 상황 | 이유 |
|------|------|
| 라이브러리/프레임워크 마이그레이션 (FastAPI 0.104 → 0.110 등) | breaking change 사전 파악 |
| 신규 라이브러리 도입 결정 | 대안 비교 + 보안 검증 |
| 아키텍처 변경 (모놀리식 → MS, REST → gRPC) | 업계 패턴/사례 분석 |
| CVE/보안 이슈 대응 | 패치 영향 + 우회 방법 |
| 성능 최적화 (수치 기반) | 벤치마크/유사 사례 |
| 신규 도메인 진입 (결제/인증/암호화) | 표준/규제 확인 |

### 절차

```
1. 의사결정 전 Deep Research (`${GEMINI_CLI:-agy} -p ...`) 실행
2. 결과를 ~/Workspace/weaversbrain/weaversbrain/Plans/YYYY-MM-DD-{주제}.md 저장
3. Codex/Gemma 세컨드 오피니언으로 결과 검증
4. 검증된 권고안 기반으로 구현
5. 결정은 자동 캡처 → Obsidian decisions/
```

### Deep Research 스킵 가능 케이스
- 5분 미만 작업
- 이미 Plans/에 같은 주제 조사 결과 30일 이내
- 사용자가 명시적으로 "조사 없이" 요청

## 팀 활용 (멀티프로젝트)

상세: `~/.claude/workflows/team-templates.md`

5개 표준 템플릿 보유:
1. **sso-core** — SSO 인증/인가 변경 (4개 프로젝트)
2. **b2c-fullstack** — B2C 풀스택 기능 (3개 프로젝트)
3. **platform-new** — Spring Boot 신규 (2개 프로젝트)
4. **infra** — Docker/Terraform (3개 프로젝트, 🔴 사람 승인)
5. **single-parallel** — 단일 프로젝트 6+ 파일 (worktree 격리)

호출: `/team {템플릿명} "{태스크}"`

### 팀 vs 단일 에이전트 선택

| 상황 | 선택 |
|------|------|
| 1 프로젝트, 3 파일 미만 | 단일 에이전트 |
| 1 프로젝트, 6+ 파일 | single-parallel |
| 2+ 프로젝트, 동일 변경 | 멀티프로젝트 팀 |

## 에이전트 다양성 체크리스트

월간 `/retro 30`에서 다음 확인:

- [ ] qa 호출 ≥ 5회 (테스트 케이스 설계)
- [ ] designer 호출 ≥ 3회 (UI 작업 시)
- [ ] po 호출 ≥ 2회 (PRD/우선순위)
- [ ] data-analyst 호출 (SQL 작업 시 100%)
- [ ] ai-engineer 호출 (RAG/임베딩 작업 시 100%)
- [ ] prompt-engineer 호출 (스킬/에이전트 수정 시 100%)

미달 항목 → 다음 달 의식적 활용.

## SDD (Spec-Driven Development) 의무 케이스

- 수정 파일 6+ (L 규모) → `active/{태스크}.md` 선행 필수
- API 계약 변경 → spec 선행 필수
- DB 스키마 변경 → spec + 마이그레이션 plan 필수

S 규모만 spec 생략 가능.

## 컨텍스트 관리 규칙

- **1 태스크 = 1 세션**: 완료 후 같은 세션에서 다음 태스크 금지
- 태스크 완료 → `/session-handoff` → 새 세션
- Gemini Phase 0 결과는 파일 저장 후 요약만 메인 컨텍스트에 (전문 주입 금지)
- L 규모 작업은 worktree 격리 권장

## 수단 한계

- 리뷰 → 재수정 루프 최대 3회. 초과 시 사용자 판단 요청
- 같은 추정 두 번 금지 — 추정 답 틀렸으면 즉시 검증 후 정정
- 테스트 안 돌리고 완료 선언 금지
