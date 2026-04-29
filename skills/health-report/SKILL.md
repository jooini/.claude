---
name: health-report
description: "오늘의 워크플로우 헬스 리포트 생성. 세션 로그·git 활동·도구 사용량을 분석해 Gemma가 팩폭 평가 + 내일 우선순위 추천. /health 또는 /health 2026-04-21 로 트리거."
argument-hint: "[YYYY-MM-DD, 기본값 오늘]"
disable-model-invocation: true
allowed-tools: Bash(python3 *)
---

# /health — 워크플로우 헬스 리포트

오늘(또는 지정 날짜) 작업 데이터를 Gemma가 분석해 팩폭 리포트 생성한다.

## 실행

```bash
python3 ~/.claude/scripts/gemma-health-report.py $ARGUMENTS
```

## 리포트 내용

- **활동 시간**: 첫/마지막 활동, 세션 수, 프로젝트 전환
- **AI 사용**: 도구별 호출, 수정 파일 수, Claude 토큰 추정
- **Git 활동**: 오늘 커밋한 프로젝트/건수, 미커밋 누적
- **Gemma 평가**: 오늘 평가 / 잘한 점 / 아쉬운 점 / 내일 우선순위 3개 / 경고 신호

## 저장 경로

`~/.claude/cache/health-report/{YYYY-MM-DD}.md`

## 사용 시점

- 퇴근 전 오늘 정리 (`/done`보다 분석 강함)
- 아침 출근 시 어제 리포트 확인 — 오늘 우선순위 힌트
- 주말 회고 시 지난 주 리포트 모아 보기

## 호출 예시

```
/health              # 오늘
/health 2026-04-21   # 어제
```

## 규칙

- Ollama 서버 다운 시 데이터만 수집, 평가 없이 저장
- Gemma 평가는 환각 가능 — 근거 데이터와 교차 검증
- 토큰 추정치는 도구 가중치 기반 개략값 (정확치 아님)
- 민감 커밋 메시지 포함될 수 있지만 로컬 처리라 외부 유출 0
