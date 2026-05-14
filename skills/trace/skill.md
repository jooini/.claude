---
name: trace
description: 훅 실행 트레이스를 분석하고 자동화 동작을 가시화한다. /trace 로 오늘자, /trace today, /trace 7 (최근 N일), /trace HOOK_NAME (특정 훅) 형태로 사용. 관측성 1순위 대응 — 어떤 자동화가 왜 발동했는지 추적.
---

# /trace — Hook Execution Tracer

훅 시스템이 89회 등록 + 22 이벤트로 거대해진 상태. 어떤 룰이 어떤 순서로 발동했는지 사람이 머리로 추적하기 어려움.

이 스킬은 `~/.claude/cache/hook-timing/YYYY-MM-DD.tsv`를 읽어 사람 친화적으로 표시한다.

## 데이터 출처

- **위치**: `~/.claude/cache/hook-timing/YYYY-MM-DD.tsv`
- **포맷**: `timestamp\thook\tduration_ms\texit\tstdout_bytes\tstderr_bytes\tside_effect`
- **생성자**: `~/.claude/hooks/_lib/hook-timing.sh` (settings.json의 모든 훅 등록이 이 래퍼를 통과)

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

기본 모드 (`/trace`):
```bash
TODAY_FILE=~/.claude/cache/hook-timing/$(date +%Y-%m-%d).tsv
[ -f "$TODAY_FILE" ] || { echo "오늘자 데이터 없음"; exit 0; }

echo "=== 오늘 발동 훅 TOP 10 ==="
tail -n +2 "$TODAY_FILE" | awk -F'\t' '{count[$2]++; sum[$2]+=$3} END {
  for (h in count) printf "%-40s %5d회 평균%4dms\n", h, count[h], sum[h]/count[h]
}' | sort -k2 -rn | head -10

echo ""
echo "=== 발동 사이드이펙트 분포 ==="
tail -n +2 "$TODAY_FILE" | awk -F'\t' '{print $7}' | sort | uniq -c | sort -rn

echo ""
echo "=== 차단/에러 발생 훅 (exit ≠ 0) ==="
tail -n +2 "$TODAY_FILE" | awk -F'\t' '$4 != 0 {count[$2]++} END {
  for (h in count) printf "%-40s %d회\n", h, count[h]
}' | sort -k2 -rn | head -5
```

`slow` 모드:
```bash
tail -n +2 "$TODAY_FILE" | awk -F'\t' '{count[$2]++; sum[$2]+=$3} END {
  for (h in count) if (count[h] >= 3) printf "%6d ms  %5d회  %s\n", sum[h]/count[h], count[h], h
}' | sort -rn | head -10
```

`blocked` 모드:
```bash
tail -n +2 "$TODAY_FILE" | awk -F'\t' '$4 != 0 {
  printf "%s  %s  exit=%s  stderr=%sB\n", $1, $2, $4, $6
}' | tail -20
```

특정 훅 모드 (`/trace HOOK_NAME`):
```bash
HOOK="$1"
tail -n +2 "$TODAY_FILE" | awk -F'\t' -v h="$HOOK" '$2 ~ h {print}' | tail -20
echo ""
echo "통계:"
tail -n +2 "$TODAY_FILE" | awk -F'\t' -v h="$HOOK" '$2 ~ h {
  count++; sum+=$3; if($3>max)max=$3; if(min==""||$3<min)min=$3
} END {
  if(count) printf "호출 %d회, 평균 %dms, 최소 %dms, 최대 %dms\n", count, sum/count, min, max
  else print "데이터 없음"
}'
```

`N일` 모드:
```bash
N="$1"
files=()
for i in $(seq 0 $((N-1))); do
  d=$(date -v-${i}d +%Y-%m-%d)
  f=~/.claude/cache/hook-timing/$d.tsv
  [ -f "$f" ] && files+=("$f")
done
[ ${#files[@]} -eq 0 ] && { echo "데이터 없음"; exit 0; }

echo "=== 최근 ${N}일 훅 통계 ==="
cat "${files[@]}" | grep -v "^timestamp" | awk -F'\t' '{count[$2]++; sum[$2]+=$3} END {
  for (h in count) printf "%-40s %6d회 평균%5dms\n", h, count[h], sum[h]/count[h]
}' | sort -k2 -rn | head -20
```

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
