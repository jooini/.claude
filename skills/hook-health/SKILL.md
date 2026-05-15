---
name: hook-health
description: ~/.claude/cache/hook-outcomes/*.jsonl 누적 분석. /hook-health [N일] 로 hook outcome 추세, trigger TOP, warn/block 이슈, 느린 hook 자동 리포트.
---

# Hook Health Report

오늘 누적되는 hook outcome 로그를 사람이 보는 리포트로 압축한다.

## 트리거

- `/hook-health` — 기본 7일
- `/hook-health 3` — 최근 3일
- `/hook-health 30` — 최근 30일

## 실행 절차

### 1단계: 데이터 수집

```bash
DAYS="${1:-7}"
OUTCOME_DIR="$HOME/.claude/cache/hook-outcomes"
TIMING_DIR="$HOME/.claude/cache/hook-timing"

# 분석 대상 날짜
START_DATE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d)
END_DATE=$(date +%Y-%m-%d)
```

### 2단계: 집계 (jq 한 줄 패턴)

```bash
# 모든 outcome 파일 collect (날짜 범위 내)
find "$OUTCOME_DIR" -name "*.jsonl" -newer /tmp/_marker 2>/dev/null \
  -o -newermt "$START_DATE" 2>/dev/null \
  | xargs cat \
  | jq -s '.'
```

핵심 메트릭:

| 메트릭 | jq 표현 |
|--------|---------|
| 총 outcome | `length` |
| outcome 분포 | `group_by(.outcome) \| map({outcome: .[0].outcome, count: length})` |
| hook 별 호출수 | `group_by(.hook) \| map({hook: .[0].hook, count: length}) \| sort_by(-.count)` |
| trigger TOP | `map(select(.outcome=="trigger")) \| group_by(.trigger // .detail) \| map({reason: .[0].trigger // .[0].detail, count: length}) \| sort_by(-.count)` |
| warn/block 이슈 | `map(select(.outcome=="warn" or .outcome=="block"))` |

### 3단계: 성능 분석 (timing)

```bash
# hook-timing TSV 포맷: timestamp\thook_name\tduration_ms
awk -F'\t' -v start="$START_DATE" '
  $1 >= start {
    cnt[$2]++; sum[$2]+=$3
    if ($3 > max[$2]) max[$2] = $3
  }
  END {
    for (h in cnt) printf "%s\t%d\t%.1f\t%d\n", h, cnt[h], sum[h]/cnt[h], max[h]
  }
' "$TIMING_DIR"/*.tsv | sort -k3 -rn
```

### 4단계: 리포트 출력

마크다운 표 형식. 섹션:

```markdown
# Hook Health Report ({DAYS}일)

## 요약
- 총 outcome: {N}건 ({N/days}/day)
- pass율: {%}
- 활성 hook: {N}개

## Outcome 분포
| outcome | 건수 | 비율 |
|---------|------|------|
| pass    | 666  | 99% |
| trigger | 11   | 1.6% |
| warn    | 1    | 0.1% |
| block   | 1    | 0.1% |

## 호출 TOP 10
| hook | 호출수 | avg ms | p95 ms |
|------|--------|--------|--------|

## ⚠️ Warn/Block 이슈 (요주의)
| 시각 | hook | outcome | detail |
|------|------|---------|--------|

## 🎯 Trigger TOP 5
| 사유 | 건수 |
|------|------|

## 🐢 느린 hook TOP 5
| hook | avg | max |
|------|-----|-----|

## 💡 권고
- (자동 생성: warn 추세, 느려진 hook, 미사용 hook 등)
```

### 5단계: 비교/추세 (옵션)

`--compare` 플래그가 있으면 직전 같은 기간과 비교 (% 증감).

## 구현 노트

- **단순 집계만** — 추론은 Claude 가 결과 보고 판단
- **출력은 stdout 마크다운** — Obsidian/리포트 파일 자동 생성 안 함
- **/retro 와 상호보완** — /retro 는 파이프라인/에이전트, /hook-health 는 hook
- **데이터 없으면**: "outcome 로그 누적 부족 (X건). 이번 주 사용 후 다시" 안내

## 참고

- outcome 스키마: `{ts, hook, outcome, session, detail, trigger}`
- 로그 파일: `~/.claude/cache/hook-outcomes/{date}.jsonl`
- 타이밍 파일: `~/.claude/cache/hook-timing/{date}.tsv`
- 1주일 후 follow-up 리마인더 (mem ID 8041) 와 시점 일치
