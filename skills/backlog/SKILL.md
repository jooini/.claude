---
name: backlog
description: 멀티 프로젝트 백로그 대시보드. /backlog 로 전체 현황, /backlog {프로젝트명} 으로 상세, /backlog --stale N 으로 방치 기준 변경.
argument-hint: "[프로젝트명 | --stale N | --detail]"
---

# backlog

12개 프로젝트의 `docs/backlog.md` 를 집계해 한눈에 표시한다.

## 데이터 소스

각 `~/Workspace/{project}/docs/backlog.md` (v2 스키마 표 형식).

| 컬럼 | 의미 |
|---|---|
| ID | `{PREFIX}-{번호}` (예: `IH-01`) |
| P | H/M/L 우선순위 |
| 추정 | 자유 형식 (`4h`, `1d`) |
| 상태 | `backlog` / `active` / `review` / `blocked` / `done` |
| 의존성 | 다른 태스크 ID |
| 추가일/마감 | YYYY-MM-DD |

프로젝트 prefix 매핑은 `~/.claude/scripts/backlog-lib.py` 의 `PROJECTS` 참조.

## 실행

```bash
# 전체 요약 (기본)
python3 ~/.claude/scripts/backlog-dashboard.py

# 특정 프로젝트 상세
python3 ~/.claude/scripts/backlog-dashboard.py --project identity-hub

# 방치 기준 일수 (기본 14일)
python3 ~/.claude/scripts/backlog-dashboard.py --stale 30
```

사용자가 `/backlog` 만 치면 인자 없이 실행. `/backlog identity-hub` 는 `--project identity-hub` 로 매핑.

## 출력 구성

1. 표: 프로젝트별 H/M/L 카운트, active 수, 마지막 active 나이
2. `⚠ backlog.md 없음` — 파일 자체가 없는 프로젝트
3. `🔥 방치된 프로젝트` — stale 기준 초과
4. `🎯 다음 추천` — 각 프로젝트 첫 번째 High backlog 5개 제시

## 태스크 추가 절차 (수동)

1. 해당 프로젝트의 `docs/backlog.md` 표 마지막 줄에 다음 번호로 추가:
   ```
   | IH-26 | 새 태스크 제목 | H |  | backlog |  | 2026-04-24 |  |
   ```
2. `## 상세` 섹션에 항목 추가:
   ```markdown
   ### IH-26 — 새 태스크 제목
   - 위치: `app/...`
   - 근거: ...
   ```

## 상태 전환

- `backlog` → `active`: orchestrator 또는 직접 시작할 때 표의 상태 셀만 수정
- `active` → `review`: PR 생성 시점
- `review` → `done`: 머지 후

## 관련 스크립트

- `backlog-lib.py` — 파서/렌더러
- `backlog-migrate.py` — v1 → v2 일회성 변환 (이미 실행 완료)
- `backlog-dashboard.py` — 이 스킬의 실제 실행 대상

## 주의

- v1 원본은 `{project}/docs/backlog.md.v1.bak` 에 백업됨. 문제 없으면 추후 삭제 가능
- speakingmax-backend 는 backlog.md 없음 → 필요하면 동일 포맷으로 신규 생성
