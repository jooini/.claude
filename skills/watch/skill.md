---
name: watch
description: 훅 발동을 실시간으로 보는 도구를 띄운다. /watch (터미널 라이브 스트림), /watch dashboard (브라우저 대시보드), /watch slow (느린 훅만), /watch HOOK_NAME (특정 훅). 별도 창/터미널에서 띄워두면 Claude Code 사용 중 자동화 동작이 흘러감.
---

# /watch — 실시간 훅 모니터

훅 시스템이 거대해서(89개 등록, 22개 이벤트, 일일 4,000+회 발동) 무엇이 어떻게 도는지 사람이 머리로 추적 불가. 이 스킬은 **실시간으로 보는 3가지 도구**를 안내한다.

## 모드

| 발화 | 도구 | 출력 위치 |
|---|---|---|
| `/watch` | hook-watch.sh (터미널 라이브) | 새 터미널 창 권장 |
| `/watch dashboard` 또는 `/watch web` | hook-dashboard.py (웹) | 브라우저 자동 |
| `/watch slow` | 느린 훅(100ms+)만 라이브 | 터미널 |
| `/watch blocked` | exit≠0(차단/에러)만 | 터미널 |
| `/watch HOOK_NAME` | 특정 훅 패턴 매칭 | 터미널 |

## 실행 절차

### 모드 1: 터미널 라이브 스트림 (기본)

```bash
~/.claude/scripts/hook-watch.sh         # 모든 훅
~/.claude/scripts/hook-watch.sh slow    # 100ms+
~/.claude/scripts/hook-watch.sh blocked # exit≠0
~/.claude/scripts/hook-watch.sh gemini  # 이름 패턴
```

`tail -F`로 `~/.claude/cache/hook-timing/YYYY-MM-DD.tsv`를 따라가며 컬러로 표시.
- 초록: <100ms
- 노랑: 100~199ms
- 빨강: 200ms+
- 사이드이펙트별 색

별도 터미널에서 띄워두는 것이 가장 효과적.

### 모드 2: 웹 대시보드

```bash
/usr/bin/python3 ~/.claude/scripts/hook-dashboard.py
# 자동으로 브라우저 열림 → http://localhost:8765
```

특징:
- 좌: TOP 10 빈도, 이벤트 분포, 요약 통계
- 우: 실시간 스트림 (필터 박스 — 훅명/이벤트/도구)
- 분당 발동율 라이브 표시
- noop 비율, 차단/에러 카운트
- 의존성 0 (표준 라이브러리만)

`--no-browser` 플래그로 브라우저 자동 열기 비활성화 가능.

### 모드 3: 백그라운드 상시 운영

작업 중 항상 켜두려면:
```bash
nohup /usr/bin/python3 ~/.claude/scripts/hook-dashboard.py --no-browser \
  > ~/.claude/cache/dashboard.log 2>&1 &
open http://localhost:8765
```

## 데이터 출처

- **TSV (호환성)**: `~/.claude/cache/hook-timing/YYYY-MM-DD.tsv`
  - 컬럼: timestamp, hook, duration_ms, exit, stdout_bytes, stderr_bytes, side_effect
- **JSONL (강화)**: `~/.claude/cache/hook-trace/YYYY-MM-DD.jsonl`
  - 추가 필드: event(이벤트명), tool(도구명), session(세션ID 8자)

`hook-watch.sh`는 TSV, `hook-dashboard.py`는 JSONL 사용.

## 보조 도구 (이 스킬과 별개)

- `/trace` — 정적 통계 스냅샷 (회고용)
- `turn-summary.sh` — Stop 훅에 자동 등록되어 매 응답 끝에 30초 요약 출력 (별도 액션 불필요)

## 규칙

- 백그라운드 데몬 띄우기 전 `lsof -i :8765`로 포트 충돌 확인
- 실시간 데이터 자체는 절대 삭제하지 말 것
- `--no-browser` 옵션 사용 시 직접 브라우저 열기 (`open http://localhost:8765`)
- 자정 넘어가면 새 일자 파일로 자동 전환 (대시보드는 자동 follow, hook-watch는 재시작 필요)
