---
name: today-tasks
description: "오늘 할 일 목록을 수집하고 보여주는 스킬. /today 로 실행하면 캘린더 이벤트, GitHub 이슈/PR, Linear 티켓, 옵시디언 데일리 노트 등에서 오늘 할 일을 모아서 보여준다."
version: 1.0.0
author: Leonard
created: 2026-03-27
platforms: [claude-code]
category: productivity
tags: [todo, daily, tasks, productivity]
risk: safe
---

# today-tasks

## Purpose

오늘 해야 할 일을 여러 소스에서 수집하여 한눈에 보여준다.

## When to Use

- `/today` 실행 시
- "오늘 할 일", "오늘 뭐해야 돼", "today tasks" 등 요청 시

## Workflow

### Step 1: 날짜 확인

오늘 날짜를 확인한다. `date +%Y-%m-%d` 실행.

### Step 2: 소스별 데이터 수집 (병렬)

아래 소스들을 **병렬로** 수집한다. 각 소스에서 에러가 나면 해당 섹션은 "접근 불가"로 표시하고 넘어간다.

#### 2-1. GitHub (gh CLI)

```bash
# 나에게 할당된 이슈
gh issue list --assignee @me --state open --limit 10 --json number,title,repository,labels,updatedAt

# 내가 리뷰해야 할 PR
gh search prs --review-requested @me --state open --limit 10 --json number,title,repository,updatedAt

# 내가 만든 PR (열린 것)
gh pr list --author @me --state open --limit 10 --json number,title,repository,updatedAt,reviewDecision
```

#### 2-2. 옵시디언 데일리 노트

옵시디언 Vault에서 오늘 날짜의 데일리 노트를 찾는다:

```bash
# 데일리 노트 경로 패턴
VAULT="$HOME/Workspace/weaversbrain/weaversbrain"
TODAY=$(date +%Y-%m-%d)

# 가능한 경로들 탐색
find "$VAULT" -name "${TODAY}*" -o -name "Daily/${TODAY}*" 2>/dev/null | head -5
```

파일이 있으면 읽어서 TODO/체크리스트 항목을 추출한다:
- `- [ ]` 미완료 항목
- `- [x]` 완료 항목

#### 2-3. Git 저장소 상태

프로젝트 목록에서 각 저장소의 미커밋 변경사항과 현재 브랜치를 확인:

```bash
PROJECTS=(
  "$HOME/Workspace/identity-hub"
  "$HOME/Workspace/maxai-b2c-backend"
  "$HOME/Workspace/identity-keycloak"
  "$HOME/Workspace/identity-hub-frontend"
  "$HOME/Workspace/maxai-stt-engine"
  "$HOME/Workspace/wb-platform-backend"
)

for proj in "${PROJECTS[@]}"; do
  if [ -d "$proj/.git" ]; then
    BRANCH=$(git -C "$proj" branch --show-current 2>/dev/null)
    DIRTY=$(git -C "$proj" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DIRTY" != "0" ] || [ "$BRANCH" != "main" -a "$BRANCH" != "master" ]; then
      echo "$(basename $proj)|$BRANCH|$DIRTY"
    fi
  fi
done
```

#### 2-4. 메모리에서 진행 중인 작업

Claude 메모리 시스템에서 "진행 중인 작업" 관련 메모리를 확인:

```bash
# MEMORY.md에서 진행 중 작업 섹션 확인
cat "$HOME/.claude/projects/-Users-leonard-Workspace/memory/MEMORY.md" 2>/dev/null
```

관련 메모리 파일들을 읽어서 현재 진행 중인 작업 목록을 추출한다.

### Step 3: 결과 포맷팅

수집한 데이터를 아래 형식으로 출력한다:

```
📅 오늘 할 일 — {YYYY-MM-DD} ({요일})
══════════════════════════════════════════

🔧 진행 중인 작업
  • {프로젝트명}: {작업 설명} ({상태})
  • ...

📌 GitHub 이슈 (나에게 할당됨)
  • #{번호} {제목} — {저장소}
  • ...

🔍 리뷰 대기 PR
  • #{번호} {제목} — {저장소}
  • ...

📝 내 PR
  • #{번호} {제목} — {상태: approved/changes_requested/pending}
  • ...

🗂️ 작업 중인 브랜치
  • {프로젝트} → {브랜치} ({변경 파일 수}개 수정됨)
  • ...

📓 옵시디언 TODO
  ☐ {미완료 항목}
  ☑ {완료 항목}
  ({완료}/{전체} 완료)

──────────────────────────────────────────
💡 우선순위 제안: {가장 급한 것 1-2개 추천}
```

### Step 4: 우선순위 제안

수집된 데이터를 기반으로 오늘 가장 먼저 해야 할 것 1-2개를 추천한다:
- 리뷰 요청이 있으면 리뷰 우선
- 오래된 PR이 있으면 머지/업데이트 권장
- 진행 중 작업 중 블로커가 있으면 해결 우선

## Notes

- `gh` CLI가 인증되어 있어야 GitHub 데이터를 가져올 수 있다
- 옵시디언 Vault 경로는 CLAUDE.md의 설정을 따른다
- 프로젝트 목록은 CLAUDE.md의 프로젝트 테이블 기준
- 각 소스에서 실패해도 나머지는 정상 출력한다
