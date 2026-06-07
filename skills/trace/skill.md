---
name: trace
description: 훅 실행 트레이스를 분석하고 자동화 동작을 가시화한다. /trace 로 오늘자, /trace today, /trace 7 (최근 N일), /trace HOOK_NAME (특정 훅) 형태로 사용. 관측성 1순위 대응 — 어떤 자동화가 왜 발동했는지 추적.
---

# /trace — Hook Execution Tracer

훅 시스템이 89회 등록 + 22 이벤트로 거대해진 상태. 어떤 룰이 어떤 순서로 발동했는지 사람이 머리로 추적하기 어려움.

이 스킬은 `~/.claude/cache/hook-wrapper-runs.jsonl`을 읽어 사람 친화적으로 표시한다.

## 데이터 출처

- **현재 위치 (2026-05-30~)**: `~/.claude/cache/hook-wrapper-runs.jsonl` (단일 JSONL)
- **포맷**: `{ts, plan_id, event, matcher, exit_code, steps[{hook_id, command, timeout_seconds, exit_code, timed_out, stdout_bytes, stderr_bytes, blocked}]}`
- **생성자**: `~/.claude/scripts/hook-wrapper-runner.py` (settings.json composite plan 실행기)
- **분석기**: `~/.claude/scripts/hook-wrapper-analyze.py` (구 hook-timing TSV 분석기 후계)
- **레거시 (~5/30)**: `~/.claude/cache/hook-timing/*.tsv` — 5/30 wrapper 전환 후 비활성. _archive로 이동 예정. blocked/timed_out/stderr_bytes 같은 새 필드는 wrapper-runs.jsonl에만 존재

## 사용 시나리오

| 발화 | 의도 |
|---|---|
| `/trace` | 오늘 발동된 훅 빈도 TOP 10 + 평균 시간 |
| `/trace today` | 오늘 timeline 압축 표시 |
| `/trace 7` | 최근 7일 통계 |
| `/trace bash-postproc-sync` | 특정 훅의 호출 패턴 |
| `/trace slow` | 평균 실행시간 TOP 10 (느린 훅) |
| `/trace blocked` | exit≠0 (차단/에러) 발생한 훅 |

## 실행 절차

### 1단계: 모드 판별

사용자 발화에서 키워드 추출:
- 숫자 N → 최근 N일
- `today` → 오늘만
- `slow` / `blocked` → 특수 모드
- 알파벳 토큰 → 특정 훅명 (부분 매칭)
- 인자 없음 → 오늘 빈도 TOP 10

### 2단계: 분석 실행

모든 모드는 `~/.claude/scripts/hook-wrapper-analyze.py`(wrapper-runs.jsonl 분석기)로 통합한다.

| 발화 | 명령 |
|---|---|
| `/trace` 또는 `/trace today` | `python3 ~/.claude/scripts/hook-wrapper-analyze.py --days 1` |
| `/trace N` | `python3 ~/.claude/scripts/hook-wrapper-analyze.py --days N` |
| `/trace HOOK_NAME` | `python3 ~/.claude/scripts/hook-wrapper-analyze.py --days 7 --hook HOOK_NAME` |
| `/trace slow` 또는 `/trace blocked` | `python3 ~/.claude/scripts/hook-wrapper-analyze.py --days 7 --slow` (timed_out·blocked·exit≠0 step만) |
| 대시보드 JSON | `--json` 추가 |

레거시 TSV(`~/.claude/cache/hook-timing/*.tsv`)는 5/30에 멈춤. 그 이전 데이터가 필요하면 직접 `cat`해서 awk로 처리. duration_ms는 wrapper-runs.jsonl에 없음(steps에 timed_out 플래그만) — duration 필요한 분석은 별도 timing wrapper 부활 필요.

### 3단계: 결과 해석

표시 후 다음 인사이트 자동 추가:

1. **이상치**: 같은 훅이 비정상 빈도(>500회/일)면 표시
2. **느린 훅**: 평균 200ms 초과면 ⚠️
3. **차단 누적**: 같은 훅이 exit≠0를 5회 이상 내면 ⚠️
4. **고아 훅**: 등록되지 않은 훅이 timing 로그에 나타나면 표시

## 출력 형식

```
## /trace 결과 (YYYY-MM-DD)

**총 발동**: NNN회 / NN개 훅 종류
**평균 응답**: NN ms

### TOP 10 (빈도)
[표]

### ⚠️ 주의
- {훅명}: {사유}

### Claude 판단
{이상 패턴 / 통폐합 후보 / 다음 액션 제안}
```

## 규칙

- 절대 timing 데이터 삭제하지 말 것 (`~/.claude/cache/hook-timing/`)
- 결과는 stdout만 — 파일 쓰지 않음
- 일자별 데이터 디스크 누적량은 `du -sh ~/.claude/cache/hook-timing/`로 확인
- 30일 이상 된 .tsv는 직접 정리 권장 (자동 정리는 별도 cron 필요)
