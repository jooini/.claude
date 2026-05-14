# /closure - 닫기 부채 현황

오늘 닫지 못한 것을 한 번에 출력한다. SessionStart hook이 컨텍스트 주입 실패하는 문제 우회용 수동 명령.

## 사용법

- `/closure` - 부채 블록 즉시 출력
- `/closure refresh` - 캐시 무시하고 다시 계산

## 수행 작업

### 1단계: 캐시 갱신 (refresh 인자일 때)

`refresh` 인자가 있으면 오늘자 캐시 파일 삭제:

```bash
[ "$ARGUMENTS" = "refresh" ] && rm -f ~/.claude/cache/closure-debt-$(date +%Y-%m-%d).txt
```

### 2단계: closure-gate 스크립트 실행

```bash
/bin/zsh ~/.claude/hooks/closure-gate-session-start.sh <<< '{"source":"startup"}'
```

### 3단계: 결과 출력

스크립트 stdout을 그대로 사용자에게 전달. 추가 해석/요약 금지. 출력 형식:

```
[CLOSURE-GATE 일일 부채 — YYYY-MM-DD]

어제 닫지 못한 것:
  🔴 미커밋 N 프로젝트: ...
  🔴 미푸시 N 커밋
  🟡 어제 단언/추정/자의결정 위반 N건

지난 7일 자산 흐름:
  ▲ 신규: 스킬 N / 훅 N
  ▼ retire: N

→ 새 작업 시작 전 위 중 최소 1개 닫아라.
```

### 4단계: 처리 우선순위 제안

부채가 있으면 다음 액션 1~3개를 사용자에게 제안:
- 미커밋 프로젝트 중 가장 최근 수정된 1개부터 커밋
- 미푸시 커밋이 많은 repo 1개 push
- 일일 위반 패턴 분석 (`closure-violations.jsonl`)

부채 0이면 "오늘 닫을 부채 없음" 한 줄.

## 인자

$ARGUMENTS
