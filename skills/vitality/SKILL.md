---
name: vitality
description: 멀티 프로젝트 사망 감지기. /vitality 로 12+개 프로젝트의 vitality score 한눈에. 살아있는 척하지만 사실상 죽어가는 프로젝트(가짜 진전)를 자동 분류. 권고 액션 포함.
---

# Project Vitality — 사망 감지기

`~/Workspace/*` 의 모든 git 프로젝트를 한 번에 평가해 vitality score를 매긴다.

## 신호

| 신호 | 가중치 |
|---|---|
| 최근 N일 커밋 수 | + (최대 30) |
| 사용자-visible 커밋 (feat/fix/add/구현) | +3 each |
| 정리/리팩터 커밋 (chore/cleanup/리팩터) | -2 each |
| 같은 파일 3+회 반복 수정 | -4 each |
| active/ 완료 ACk | +5 each |
| 처리 안 된 backlog | -0.5 each |
| 사용자-visible 0건 + 커밋 5+개 | -25 (가짜 진전) |

## 등급

- 🟢 70+: 활기
- 🟡 40-69: 보통
- 🟠 20-39: 위태로움
- 🔴 <20 (가짜 진전): 사망 의심
- ⚫ 활동 없음: 휴면

## 사용법

- `/vitality` — 14일 윈도우 전체 분석
- `/vitality 7` — 7일 윈도우
- `/vitality 30 identity-hub` — 30일, 단일 프로젝트
- `/vitality show` — 리포트 즉시 출력

## 절차

```bash
python3 ~/.claude/scripts/project-vitality.py --days 14
```

리포트:
- `~/.claude/cache/vitality-report.md`
- `~/.claude/cache/vitality-report.json`

## 권고 패턴

- 🔴 사망 의심 → "다음 작업은 리팩터/정리 금지, 사용자-visible 결과 1개만 강제"
- ⚫ 휴면 → "프로젝트 archive 또는 명시적 종료 결정"
- 🟠 위태로움 → "백로그 정리 + 가장 작은 사용자-visible 작업 1개 우선"

## 자동 실행 (옵션)

주간 자동 실행:

```bash
# crontab 예
0 9 * * 1 /usr/bin/python3 /Users/leonard/.claude/scripts/project-vitality.py --days 7
```

또는 `gemma-morning-brief.sh` 훅에서 호출.
