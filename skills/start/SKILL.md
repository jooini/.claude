---
name: start
description: "아침 작업 시작 루틴. /start 로 실행하면 오늘 할 일 확인 → 작업 선택 → 브랜치 생성 → 작업 시작까지 자동 진행."
argument-hint: "[프로젝트명 또는 작업 설명]"
---

# start

아침에 작업을 시작할 때 사용하는 루틴 스킬.

## 실행 절차

### 1단계: 오늘 할 일 수집 (병렬)

아래를 **병렬로** 수집한다:

#### 1-1. Git 저장소 상태

```bash
PROJECTS=(
  "$HOME/Workspace/identity-hub"
  "$HOME/Workspace/maxai-b2c-backend"
  "$HOME/Workspace/identity-keycloak"
  "$HOME/Workspace/identity-hub-frontend"
  "$HOME/Workspace/identity-hub-python-sdk"
  "$HOME/Workspace/sso-fallback-monitor"
  "$HOME/Workspace/maxai-stt-engine"
  "$HOME/Workspace/wb-platform-backend"
  "$HOME/Workspace/speakingmax-backend"
)

for proj in "${PROJECTS[@]}"; do
  if [ -d "$proj/.git" ]; then
    BRANCH=$(git -C "$proj" branch --show-current 2>/dev/null)
    DIRTY=$(git -C "$proj" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DIRTY" != "0" ] || [ "$BRANCH" != "main" -a "$BRANCH" != "master" -a "$BRANCH" != "develop" ]; then
      echo "$(basename $proj)|$BRANCH|$DIRTY"
    fi
  fi
done
```

#### 1-2. GitLab 할당 이슈/MR

MCP GitLab 도구로 수집:
- `mcp__gitlab__list_issues` — 나에게 할당된 미완료 이슈
- `mcp__gitlab__list_merge_requests` — 리뷰 요청된 MR

#### 1-3. 전날 보고서 미완료 항목

```bash
VAULT="$HOME/Workspace/weaversbrain/weaversbrain"
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
MONTH=$(echo $YESTERDAY | cut -d'-' -f1-2)
cat "$VAULT/Daily/$MONTH/$YESTERDAY.md" 2>/dev/null
```

전날 보고서에서 `- [ ]` 미완료 항목과 "내일 할 일" 섹션 추출.

#### 1-4. 메모리에서 진행 중 작업

```bash
cat "$HOME/.claude/projects/-Users-leonard-Workspace/memory/MEMORY.md" 2>/dev/null
```

"진행 중인 작업" 섹션 확인.

#### 1-5. 프로젝트 백로그 현황

```bash
BASE="$HOME/Workspace"
BACKLOG_PROJECTS=(
  "identity-hub" "maxai-b2c-backend" "identity-keycloak"
  "speakingmax-backend" "identity-hub-frontend" "identity-hub-python-sdk"
  "keycloak-kakao-social-provider" "sso-fallback-monitor"
  "member-api" "wb-platform-backend" "ai-agentic-workflow"
)

for proj in "${BACKLOG_PROJECTS[@]}"; do
  BACKLOG="$BASE/$proj/docs/backlog.md"
  ACTIVE_DIR="$BASE/$proj/docs/active"
  if [ -f "$BACKLOG" ]; then
    TODO=$(grep -c '^\- \[ \]' "$BACKLOG" 2>/dev/null || echo 0)
    ACTIVE=$(/bin/ls -1 "$ACTIVE_DIR"/*.md 2>/dev/null | grep -v gitkeep | wc -l | tr -d ' ')
    if [ "$TODO" != "0" ] || [ "$ACTIVE" != "0" ]; then
      echo "$proj|$TODO|$ACTIVE"
    fi
  fi
done
```

백로그 대기 항목 + active 진행 중 항목 요약.

#### 1-6. 학습 컨텍스트 (자동 진단)

학습 큐 + Hook 차단 + 최근 노트를 한 번에 조회한다. 보조 스크립트 사용:

```bash
~/.claude/scripts/learning-morning-context.sh
```

스크립트 출력에 다음이 포함된다 (실측 — 가정 금지):
- 어제 큐에 추가된 항목 N개 (어제 날짜 grep)
- 미정리 큐 항목 수 + 가장 오래된 미정리 (며칠 경과)
- 어제/오늘 차단된 발화 수 (Hook 효과 확인)
- 최근 7일 학습 노트 N개

직접 호출하려면:
```bash
# 어제 큐 추가
grep "$(date -v-1d +%Y-%m-%d)" ~/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md | wc -l

# 미정리 + 가장 오래된
grep -c "^- \[ \]" ~/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md
grep "^- \[ \]" ~/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md | head -1

# 어제 차단
grep "$(date -v-1d +%Y-%m-%d)" ~/.claude/cache/learning-queue-blocked.log | wc -l

# 최근 7일 학습 노트
find ~/Workspace/weaversbrain/weaversbrain/Learning -name "*.md" -mtime -7 -not -name "learning-queue*" | wc -l
```

권고 규칙 (스크립트가 자동 출력):
- 미정리 ≥ 5개 → `/deep-learn queue` 제안
- 가장 오래된 > 14일 → 즉시 close 또는 학습

### 2단계: 요약 출력

수집 결과를 아래 형식으로 출력:

```
🌅 작업 시작 — {YYYY-MM-DD} ({요일})
══════════════════════════════════════════

🔧 진행 중 (미커밋 변경 또는 피처 브랜치)
  1. {프로젝트} → {브랜치} ({변경 수}개 수정)
  2. ...

📋 전날 미완료
  3. {미완료 항목}
  4. ...

📌 GitLab
  5. #{번호} {제목} — {저장소}
  6. ...

📦 백로그 (자동 처리 가능)
  7. {프로젝트} — {N}건 대기, {M}건 진행중
  8. ...
  💡 `/orchestrator --dry-run` 으로 상세 확인

📚 학습 컨텍스트
  • 어제 큐 추가: {N}건 / 미정리: {M}건
  • 어제/오늘 차단: {a}/{b}건 (Hook 효과)
  • 최근 7일 노트: {K}개
  • (조건부) 권고: /deep-learn queue / 14일 경과 항목 처리

──────────────────────────────────────────
💡 추천: {가장 먼저 할 것}

어떤 작업부터 시작할까? (번호 또는 직접 입력)
```

### 3단계: 작업 선택

- `$ARGUMENTS`가 있으면 해당 작업으로 바로 시작
- 없으면 2단계 출력 후 사용자 입력 대기
- 번호를 선택하면 해당 항목으로 시작
- 직접 입력하면 새 작업으로 시작

### 4단계: 작업 환경 세팅

선택된 작업에 따라:

1. **진행 중 작업 선택 시**: 해당 프로젝트 디렉토리 확인, 브랜치 상태 출력
2. **새 작업 시작 시**:
   - 대상 프로젝트 판단 (작업 설명에서 추론)
   - 브랜치 생성: `feature/{작업-요약}` 또는 `fix/{이슈-요약}`
   - `git checkout -b {브랜치}`

### 5단계: 작업 시작 안내

```
✅ 준비 완료
  프로젝트: {프로젝트명}
  브랜치: {브랜치명}
  작업: {작업 설명}

작업을 지시해주세요. (예: "회원 API에 nickname 필드 추가하고 MR까지")
```

## 주의사항

- 각 소스에서 에러가 나면 해당 섹션 스킵
- 브랜치 생성 시 기존 브랜치와 충돌하면 사용자에게 확인
- 새 작업 시 프로젝트를 추론할 수 없으면 사용자에게 질문
