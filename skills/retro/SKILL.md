---
name: retro
description: 파이프라인 효과 측정 회고 리포트 생성. 최근 N일간 에이전트 사용 빈도, 평균 실행 시간, 실패율, 프로젝트별 분포를 집계하여 마크다운 리포트로 출력. "/retro", "/retro 7", "회고", "파이프라인 측정" 등으로 트리거.
---

# Retro — 파이프라인 회고/측정 리포트

`~/.claude/cache/metrics/` 의 TSV 로그를 집계하여 회고 리포트를 생성한다.

## 사용법

- `/retro` — 최근 7일
- `/retro 14` — 최근 14일
- `/retro 30 weavers-sso` — 최근 30일, 특정 프로젝트만

## 데이터 소스

- `~/.claude/cache/metrics/YYYY-MM-DD.tsv` — `pipeline-metrics-log.sh` 훅이 PostToolUse(Agent)에서 자동 기록
- `~/.claude/cache/usage/YYYY-MM-DD.log` — 기존 도구 사용 로그 (gemini/codex)

## 절차

### 1. 기간 결정
- 인자 없으면 7일
- 첫 인자가 숫자면 일 수, 비숫자면 프로젝트 필터
- 두번째 인자는 프로젝트 필터

### 2. 데이터 수집
다음 Bash 명령으로 집계 (Read는 사용하지 말 것 — 큰 파일 우려):

```bash
DAYS=${1:-7}
PROJECT_FILTER=${2:-}
METRICS_DIR="$HOME/.claude/cache/metrics"
USAGE_DIR="$HOME/.claude/cache/usage"

# 최근 N일 파일 모음
files=()
for i in $(seq 0 $((DAYS-1))); do
    d=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "$i days ago" +%Y-%m-%d)
    [ -f "$METRICS_DIR/${d}.tsv" ] && files+=("$METRICS_DIR/${d}.tsv")
done

# 헤더 제외, 필터 적용 후 awk 집계
cat "${files[@]}" 2>/dev/null | grep -v "^timestamp" | \
  awk -F'\t' -v proj="$PROJECT_FILTER" '
    proj == "" || $3 == proj {
      total++
      agent_count[$2]++
      agent_duration[$2] += $5
      proj_count[$3]++
      if ($4 == "fail") { fail_count[$2]++; total_fail++ }
    }
    END {
      print "TOTAL\t" total "\t" total_fail
      for (a in agent_count) {
        avg = agent_duration[a] / agent_count[a]
        fr = (fail_count[a] ? fail_count[a]/agent_count[a]*100 : 0)
        printf "AGENT\t%s\t%d\t%.0f\t%.1f\n", a, agent_count[a], avg, fr
      }
      for (p in proj_count) {
        printf "PROJECT\t%s\t%d\n", p, proj_count[p]
      }
    }
  '
```

### 3. 리포트 출력 (마크다운)

```markdown
# 파이프라인 회고 — 최근 {DAYS}일 ({시작일} ~ {종료일})

## 종합
- 총 에이전트 호출: {total}회
- 실패: {total_fail}회 ({fail_rate}%)

## 에이전트별 (상위 10)
| 에이전트 | 호출 | 평균 시간(s) | 실패율 |
|----------|------|------------|--------|
| ... | ... | ... | ... |

## 프로젝트별
| 프로젝트 | 호출 |
|----------|------|

## 인사이트 (자동 생성)
- 가장 많이 쓰인 에이전트: ...
- 가장 느린 에이전트: ...
- 실패율 높은 에이전트(>20%): ... → 파이프라인 재검토 권장
- 호출 0건 에이전트: ... → 정리 후보
```

### 4. 인사이트 자동 추론 룰
- 실패율 >20% 인 에이전트는 "재검토 권장"
- 평균 시간 60초 초과인 에이전트는 "병렬화 검토" 표시
- 7일간 호출 0건 에이전트는 정리 후보로 명시
- 특정 프로젝트가 전체 호출의 60% 이상이면 "워크플로우 분리 고려" 권장

## 주의

- 메트릭 파일이 비어있으면 (훅 도입 직후) "데이터 부족, 7일 후 재시도" 안내
- 사용자가 명시적으로 "저장해줘" 하면 Obsidian Vault에 `YYYY-MM-DD-HHMM-pipeline-retro.md` 로 저장
- 기본은 콘솔 출력만
