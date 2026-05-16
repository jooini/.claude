# Claude Code 치트시트

> 매일 첫 세션 자동 표시. 상황 떠오르면 명령어/패턴 즉시 사용.

## 🌅 일과 흐름

| 시점 | 명령 | 효과 |
|------|------|------|
| 출근 | `/morning` | 백로그+캘린더+서버+프로젝트 종합 |
| 작업 시작 | `/start` | 브랜치 + active 파일 + 작업 픽업 |
| 작업 완료 | `/go` | E2E 테스트 + 단순화 검증 |
| 막힘 | `/debug` | 자동 진단 (재현→로그→가설→수정) |
| 점심 | `/today` | 오늘 일정 리마인드 |
| 퇴근 | `/done` | 커밋 + 일일 보고 + 세션 저장 |
| 금요일 | (자동 17시) `/retro 7` | 주간 회고 |

## 🚀 작업 타입별 (CLAUDE.md 자동 라우팅)

키워드 말하면 자동 발동:

| 말 | TYPE | 자동 발동 |
|------|------|----------|
| "기능 추가", "새로 만들어" | A | TDD + 3중 리뷰 |
| "버그", "에러", "안 돼" | B | /debug |
| "리팩터", "정리" (3파일+) | C | Gemini Phase 0 + worktree |
| "UI", "디자인" | D | designer + Playwright |
| "쿼리", "대시보드" | E | data-analyst |
| "배포", "Docker" | F | 🔴 사람 승인 |
| "문서", "PRD" | G | po/prompt-engineer + Obsidian |

## ⚡ 통합 명령

| 명령 | 묶음 |
|------|------|
| `/morning` | today + backlog + check-server + project-status |
| `/safe-deploy` | check-server + check-env + migration-status + deploy-status |
| `/sso-flow` | 4프로젝트 + check-sso-compat + cross-check |

## 🤖 에이전트 한글 호출

호출명만 말하면 그 에이전트 발동:

| 말 | 에이전트 |
|------|---------|
| "백엔드 X 해줘" | backend-developer |
| "프론트 X 해줘" | frontend-developer |
| "리뷰어 X 봐줘" | code-reviewer |
| "테스터 X 검증" | code-tester |
| "큐에이 테스트 케이스" | qa |
| "디자이너 X" | designer |
| "피오 PRD" | po |
| "데이터 SQL 분석" | data-analyst |
| "옵스 배포" | ops-lead |
| "프롬프트 X 개선" | prompt-engineer |

복수 호출명 → 병렬 실행됨.

## 🔍 검색/탐색 (작업 시작 전 의무)

자동 hook이 권유함. 직접 하려면:

```
"이전에 X 한 적 있나?" — claude-mem 자동 검색
"X 코드 어디?" — local-rag 의미 검색
```

## 🌐 외부 도구 활용

| 상황 | 도구 |
|------|------|
| 1M 토큰 큰 분석 | `Skill(ask-gemini)` |
| 세컨드 오피니언 | `Skill(ask-codex)` |
| 민감 데이터 / 브레인스토밍 | `Skill(ask-gemma)` (로컬) |
| 큰 결정 (마이그레이션 등) | `Skill(deep-research)` |

## 👥 팀 spawn (멀티프로젝트)

| 명령 | 용도 |
|------|------|
| `/team sso-core "X"` | SSO 4프로젝트 동시 (identity-hub + keycloak + b2c + admin) |
| `/team b2c-fullstack "X"` | B2C 풀스택 |
| `/team infra "X"` | Docker/Terraform 🔴 |
| `/team single-parallel "X"` | 단일 프로젝트 6+ 파일 worktree 병렬 |

## 📋 백로그/태스크

| 명령 | 효과 |
|------|------|
| `/backlog` | 12 프로젝트 대시보드 |
| `/backlog identity-hub` | 특정 프로젝트 상세 |
| `/backlog --stale 14` | 14일+ 방치 표시 |
| `@dev backlog` | 최상위 1개 자동 처리 |
| `@dev backlog 전체` | 모두 순차 처리 |
| `/orchestrator` | 12 프로젝트 자동 순회 |

## 💪 배수 효과 패턴 (활용 잘 하는 법)

### 시간 압축: 백그라운드 병렬
```
"X 백그라운드로 9개 동시 처리해"
```
→ 9시간 → 9분 (이번 세션 dev.md 표준화 사례)

### 위임 패턴: 자동 보고
```
"X 해줘 — 결과만 알려줘, 자동으로 돌려"
```
→ 직접 작업 안 하고 결과만 받음

### 3중 리뷰: 동시 검증
```
"X 리뷰 — code-reviewer + codex + gemini 3중 병렬"
```
→ 3명 의견 한 번에

### 모니터링: /loop
```
/loop 5m /check-server   # 5분마다 서버 체크
/loop 10m /deploy-status # 배포 진행 추적
```

### 큰 결정: Deep Research 선행
```
"마이그레이션 결정 — Deep Research 먼저"
```
→ 조사 후 codex/gemini 검증 → 결정

## 🎯 활용 잘 하는 3대 원칙

1. **외우지 말고 보고 써** — 이 치트시트가 매일 자동 표시됨
2. **혼자 하지 말고 위임해** — 백그라운드 + 병렬 + 에이전트 활용
3. **자동화 트리거 활용** — hook이 알려줄 때 무시하지 말 것

## ⚙️ 자동 동작 인프라 (의식 안 해도 됨)

매일 자동:
- 14시: Gemma cron (PR 리뷰/주간 학습)
- 매주 월 03시: 백업 정리 (30일 만료)
- 매주 금 17시: `/retro 7` 자동 → Obsidian
- 매일 첫 세션: 이 치트시트 + 백로그 알림
- 매 프롬프트: 메모리 검색 권유 + 규모 판별 + 50/100/150턴 알림
- 모든 코드 변경: code-reviewer + codex 자동

## 📚 더 알고 싶으면

- `~/.claude/CLAUDE.md` — 글로벌 룰
- `~/.claude/workflows/standard-routines.md` — 작업 타입 7개 + 백로그 가드
- `~/.claude/workflows/team-templates.md` — 팀 5종
- `~/.claude/workflows/self-modification-pattern.md` — 자기 설정 수정 절차
- `/decisions` — 과거 결정 검색
