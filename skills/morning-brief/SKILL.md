---
name: morning-brief
description: "세션 시작 브리핑 수동 재생성. 어제 health 리포트 + 오늘 git 상태 → Gemma가 4줄 브리핑. SessionStart 훅으로 자동 실행되지만 캐시 무시하고 재생성할 때 사용."
argument-hint: ""
disable-model-invocation: true
allowed-tools: Bash(zsh *), Bash(rm *)
---

# /brief — 세션 시작 브리핑 재생성

자동 훅이 SessionStart 시 알아서 돌지만, 수동으로 재생성하고 싶을 때 사용.

## 실행

```bash
TODAY=$(date +%Y-%m-%d)
# 캐시 삭제 후 훅 재실행
rm -f ~/.claude/cache/morning-brief/${TODAY}.md
/bin/zsh ~/.claude/hooks/gemma-morning-brief.sh
```

## 내용 구성

- 어제: 핵심 성과/이슈
- 오늘 상태: 미커밋/미푸시 요약
- 오늘 우선순위: 가장 먼저 손댈 것
- 목표 제안: 오늘 최소 달성 목표

## 저장 경로

`~/.claude/cache/morning-brief/{YYYY-MM-DD}.md`

## 관련 스킬

- `/health [date]` — 상세 헬스 리포트
- `/triage [N]` — 미커밋 정리 로드맵
- `/daily-draft [date]` — 일일 보고서 초안
