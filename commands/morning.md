# /morning - 아침 종합 시작

하루 시작 시 **백로그 + 캘린더 + 서버 상태 + 작업 선택**을 한 번에 처리하는 통합 명령.

## 사용법

- `/morning` — 전체 아침 루틴
- `/morning quick` — 빠른 버전 (서버 체크 생략)

## 수행 작업 (순차)

### 1단계: 오늘 할 일 수집 (`Skill(today-tasks)`)

다음 소스에서 통합 조회:
- 캘린더 이벤트
- GitHub 이슈/PR (assigned)
- Linear 티켓
- 옵시디언 데일리 노트
- 미완료 active 태스크 (12개 프로젝트)

### 2단계: 백로그 현황 (`Skill(backlog)`)

12개 프로젝트 백로그 대시보드:
- 프로젝트별 H/M/L 카운트
- Active 진행 중 작업
- 방치된 프로젝트 (14일+)
- 우선순위 High 추천 5개

### 3단계: 핵심 서버 상태 (`Skill(check-server)`)

dev2-backend 컨테이너 상태:
- 모든 컨테이너 Up?
- Unhealthy 없는지
- 야간 자동 작업 (Gemma cron, backup-cleanup) 정상 동작?

`quick` 인자 시 스킵.

### 4단계: 프로젝트 상태 (`Skill(project-status)`)

다중 프로젝트 git 상태:
- 미커밋 변경 있는 프로젝트
- 푸시 안 된 커밋
- 충돌 발생 프로젝트
- 어제 작업 마무리 안 된 곳

### 5단계: 종합 + 작업 선택

위 4단계 결과를 종합해서 한 화면에 표시:

```
🌅 오늘 시작 - YYYY-MM-DD

📅 일정 (캘린더): ...
📋 오늘 할 일: ... (총 N개)
🔥 우선순위 High 백로그: ... (5개)

🖥️ 서버: ✅ 모두 정상 / ⚠️ 1개 unhealthy
📂 프로젝트: ⚠️ X 프로젝트 미커밋 (어제 마무리 필요)

[추천 시작]
1. {프로젝트명} - {태스크명} (P:H)
2. ...

다음 액션:
- "1번으로 시작" → /start로 진행
- "어제 미커밋 마무리" → /done 먼저
- "백로그 정리" → /backlog --stale 14
```

### 6단계: 작업 선택 → /start 호출

사용자가 번호 선택하면 `Skill(start)` 자동 호출 — 브랜치 생성 + active 파일 + 작업 시작.

## 주의

- 매일 첫 세션에 자동 알림 표시 (session-today-reminder.sh hook)
- `quick` 모드는 서버 SSH 안 함 → 빠름 (5초 이내)
- 풀 모드는 SSH 포함 → 30초 정도

## 호출 예시

```
/morning
# → 1~5단계 통합 요약 → 작업 선택

/morning quick
# → 서버 체크 스킵, 빠른 시작
```

## 관련 자료

- `Skill(start)` — 작업 선택 후 브랜치 생성
- `Skill(today-tasks)` — 캘린더/이슈/노트 통합
- `Skill(backlog)` — 백로그 대시보드
- `Skill(check-server)` — 서버 상태
- `Skill(project-status)` — git 상태 통합
