---
name: orchestrator
description: "멀티 프로젝트 자율 업무 오케스트레이터. /orchestrator 로 실행하면 전체 프로젝트 백로그를 순회하며 에이전트가 자율적으로 태스크를 처리한다."
argument-hint: "[all | 프로젝트명 | --dry-run]"
---

# orchestrator

멀티 프로젝트 백로그를 순회하며 `@dev backlog` 를 자동 실행하는 오케스트레이터.

## 프로젝트 목록 (우선순위 순)

```bash
PROJECTS=(
  "identity-hub"
  "maxai-b2c-backend"
  "identity-keycloak"
  "speakingmax-backend"
  "identity-hub-frontend"
  "identity-hub-python-sdk"
  "keycloak-kakao-social-provider"
  "sso-fallback-monitor"
  "member-api"
  "wb-platform-backend"
  "maxai-docker"
  "identity-platform-docker"
  "ai-agentic-workflow"
)
```

## 실행 모드

| 인자 | 동작 |
|------|------|
| (없음) | 전체 프로젝트 순회, 각 프로젝트에서 백로그 1개씩 처리 |
| `all` | 전체 프로젝트 순회, 각 프로젝트의 모든 백로그 처리 |
| `{프로젝트명}` | 해당 프로젝트만 백로그 전체 처리 |
| `--dry-run` | 각 프로젝트 백로그 현황만 출력 (실행 안 함) |
| `--status` | 각 프로젝트 active/ 상태 + 백로그 잔여 항목 수 출력 |

## 실행 절차

### Phase 0: 현황 스캔

모든 프로젝트의 `docs/backlog.md`와 `docs/active/` 를 스캔한다:

```bash
BASE="$HOME/Workspace"
for proj in "${PROJECTS[@]}"; do
  BACKLOG="$BASE/$proj/docs/backlog.md"
  ACTIVE_DIR="$BASE/$proj/docs/active"

  if [ -f "$BACKLOG" ]; then
    TODO_COUNT=$(grep -c '^\- \[ \]' "$BACKLOG" 2>/dev/null || echo 0)
    DONE_COUNT=$(grep -c '^\- \[x\]' "$BACKLOG" 2>/dev/null || echo 0)
  else
    TODO_COUNT=0
    DONE_COUNT=0
  fi

  ACTIVE_COUNT=0
  if [ -d "$ACTIVE_DIR" ]; then
    ACTIVE_COUNT=$(/bin/ls -1 "$ACTIVE_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  fi

  echo "$proj|$TODO_COUNT|$DONE_COUNT|$ACTIVE_COUNT"
done
```

### Phase 1: 현황 출력

```
🔄 멀티 프로젝트 오케스트레이터
══════════════════════════════════════════

프로젝트                    | 백로그 | 완료 | 진행중
─────────────────────────────────────────
identity-hub               |   3   |  1  |   0
maxai-b2c-backend          |   7   |  0  |   0
...

총 대기: {N}개 | 진행중: {M}개
══════════════════════════════════════════
```

`--dry-run` 또는 `--status` 이면 여기서 종료.

### Phase 2: 태스크 실행

프로젝트별로 순회하며 처리:

1. **active/ 먼저 확인** — 미완료 active 파일이 있으면 그것부터 처리
2. **active 없으면 backlog에서 선택** — `- [ ]` 중 최상위 항목 1개 선택
3. **태스크 파일 생성** — `docs/active/YYYY-MM-DD-{태스크요약}.md` 생성

```markdown
# {태스크 제목}

- 상태: 진행중
- 시작: {YYYY-MM-DD HH:MM}
- 출처: backlog.md #{항목번호}

## 목표

{백로그 항목 내용}

## 진행 기록

(에이전트가 작업하며 기록)
```

4. **에이전트 디스패치** — 해당 프로젝트의 `@dev` 에이전트를 Agent 도구로 실행

```
프로젝트 {proj}의 dev.md 에이전트를 실행한다.
작업 디렉토리: ~/Workspace/{proj}
태스크: {백로그 항목 내용}
active 파일: docs/active/{파일명}.md

dev.md의 세션 시작 프로토콜 → 태스크 라우팅 → 실행 → 완료 처리까지 자율 수행.
```

5. **완료 처리**
   - active 파일 상태 → `완료`, 종료 시각 기록
   - backlog.md `- [ ]` → `- [x]`
   - active/ → `docs/archive/YYYY-MM/` 이동

### Phase 3: 결과 보고

```
✅ 오케스트레이터 완료
══════════════════════════════════════════

처리 결과:
  identity-hub: 1건 완료 ✅
  maxai-b2c-backend: 1건 완료 ✅
  identity-keycloak: 스킵 (백로그 없음)
  ...

총 처리: {N}건 | 성공: {S}건 | 실패: {F}건
잔여 백로그: {R}건
══════════════════════════════════════════
```

## 병렬 실행 규칙

- **독립 프로젝트는 병렬 실행 가능** — 예: identity-hub와 identity-keycloak 동시 처리
- **의존 프로젝트는 순차** — 예: identity-hub 변경 → identity-hub-frontend 후행
- **최대 동시 실행**: 3개 프로젝트

### 의존성 그래프

```
identity-hub ← identity-hub-frontend (Admin Dashboard)
identity-hub ← identity-hub-python-sdk (SDK)
identity-hub ← maxai-b2c-backend (B2C 연동)
identity-keycloak ← maxai-b2c-backend (KC 테마/SPI)
identity-keycloak ← keycloak-kakao-social-provider (Kakao SPI)
speakingmax-backend (독립)
sso-fallback-monitor (독립)
member-api (독립)
wb-platform-backend (독립)
maxai-docker (독립)
identity-platform-docker (독립)
ai-agentic-workflow (독립)
```

## 에스컬레이션

- 에이전트가 태스크 처리 실패 시 → active 파일에 실패 사유 기록, 다음 프로젝트로 진행
- 3개 프로젝트 연속 실패 → 사용자에게 알림 후 중단
- 크로스 프로젝트 영향 감지 → `@team` 스폰 권유

## 주의사항

- Docker 프로젝트(maxai-docker, identity-platform-docker)는 코드 변경 없이 설정/보안 개선만 수행
- PHP 프로젝트(maxai-b2c-backend, speakingmax-backend)는 테스트 파이프라인 제한적
- 커밋 메시지는 한글로 작성
- Co-Authored-By 절대 금지
