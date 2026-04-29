#!/bin/zsh
# 주간 파이프라인 회고 자동 생성 (매주 금요일 17시 cron)
#
# 출력: ~/.claude/cache/retro/YYYY-MM-DD-weekly.md
# 또한 Obsidian Vault에도 저장: ~/Workspace/weaversbrain/weaversbrain/Plans/retro-YYYY-MM-DD.md

: "${HOME:?}"

DAYS=7
METRICS_DIR="$HOME/.claude/cache/metrics"
RETRO_DIR="$HOME/.claude/cache/retro"
OBSIDIAN_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Plans"

mkdir -p "$RETRO_DIR"
mkdir -p "$OBSIDIAN_DIR"

DATE_TODAY=$(date +%Y-%m-%d)
DATE_START=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "$DAYS days ago" +%Y-%m-%d)

OUTPUT="$RETRO_DIR/${DATE_TODAY}-weekly.md"
OBSIDIAN_OUTPUT="$OBSIDIAN_DIR/${DATE_TODAY}-1700-weekly-retro.md"

# 파일 모음
files=()
for i in $(seq 0 $((DAYS-1))); do
    d=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "$i days ago" +%Y-%m-%d)
    [ -f "$METRICS_DIR/${d}.tsv" ] && files+=("$METRICS_DIR/${d}.tsv")
done

if [ ${#files[@]} -eq 0 ]; then
    echo "[retro-weekly] 메트릭 파일 없음, 스킵"
    exit 0
fi

# 집계
RAW_DATA=$(cat "${files[@]}" 2>/dev/null | grep -v "^timestamp" | \
  awk -F'\t' '
    {
      total++
      agent_count[$2]++
      agent_duration[$2] += $5
      proj_count[$3]++
      if ($4 == "fail") { fail_count[$2]++; total_fail++ }
    }
    END {
      print "TOTAL\t" total "\t" (total_fail ? total_fail : 0)
      for (a in agent_count) {
        avg = agent_count[a] ? agent_duration[a] / agent_count[a] : 0
        fr = (fail_count[a] ? fail_count[a]/agent_count[a]*100 : 0)
        printf "AGENT\t%s\t%d\t%.0f\t%.1f\n", a, agent_count[a], avg, fr
      }
      for (p in proj_count) {
        printf "PROJECT\t%s\t%d\n", p, proj_count[p]
      }
    }
  ')

# 마크다운 리포트 생성
{
  echo "---"
  echo "date: $DATE_TODAY"
  echo "type: retro"
  echo "period: weekly"
  echo "auto_generated: true"
  echo "---"
  echo ""
  echo "# 주간 파이프라인 회고 — $DATE_START ~ $DATE_TODAY"
  echo ""

  TOTAL=$(echo "$RAW_DATA" | awk -F'\t' '$1=="TOTAL" {print $2}')
  TOTAL_FAIL=$(echo "$RAW_DATA" | awk -F'\t' '$1=="TOTAL" {print $3}')
  FAIL_RATE=0
  if [ -n "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
    FAIL_RATE=$(echo "scale=1; $TOTAL_FAIL * 100 / $TOTAL" | bc 2>/dev/null || echo "0")
  fi

  echo "## 종합"
  echo "- 총 에이전트 호출: ${TOTAL:-0}회"
  echo "- 실패: ${TOTAL_FAIL:-0}회 (${FAIL_RATE}%)"
  echo ""

  echo "## 에이전트별 (상위 10)"
  echo ""
  echo "| 에이전트 | 호출 | 평균(s) | 실패율 |"
  echo "|----------|------|---------|--------|"
  echo "$RAW_DATA" | awk -F'\t' '$1=="AGENT" { print "| " $2 " | " $3 " | " $4 " | " $5 "% |" }' | sort -t'|' -k3 -rn | head -10
  echo ""

  echo "## 프로젝트별"
  echo ""
  echo "| 프로젝트 | 호출 |"
  echo "|----------|------|"
  echo "$RAW_DATA" | awk -F'\t' '$1=="PROJECT" { print "| " ($2=="" ? "(미지정)" : $2) " | " $3 " |" }' | sort -t'|' -k3 -rn
  echo ""

  echo "## 자동 인사이트"
  echo ""

  # 실패율 높은 에이전트
  HIGH_FAIL=$(echo "$RAW_DATA" | awk -F'\t' '$1=="AGENT" && $5+0 > 20 { print "  - " $2 " 실패율 " $5 "% — 재검토 권장" }')
  if [ -n "$HIGH_FAIL" ]; then
    echo "### 실패율 높음 (>20%)"
    echo "$HIGH_FAIL"
    echo ""
  fi

  # 평균 시간 긴 에이전트
  SLOW=$(echo "$RAW_DATA" | awk -F'\t' '$1=="AGENT" && $4+0 > 60 { print "  - " $2 " 평균 " $4 "s — 병렬화 검토" }')
  if [ -n "$SLOW" ]; then
    echo "### 평균 시간 긴 에이전트 (>60s)"
    echo "$SLOW"
    echo ""
  fi

  # 가장 많이 쓰인 에이전트
  TOP_AGENT=$(echo "$RAW_DATA" | awk -F'\t' '$1=="AGENT" { print $3 "\t" $2 }' | sort -rn | head -1 | cut -f2)
  if [ -n "$TOP_AGENT" ]; then
    echo "### 핵심 에이전트"
    echo "  - 가장 많이 쓰임: $TOP_AGENT"
    echo ""
  fi

  # 호출 0건인 에이전트 검출 (글로벌 13개 중)
  GLOBAL_AGENTS=("backend-developer" "frontend-developer" "ai-engineer" "code-reviewer" "code-tester" "qa" "designer" "po" "data-analyst" "ops-lead" "prompt-engineer" "debug-master" "dev-lead")
  UNUSED=""
  for agent in "${GLOBAL_AGENTS[@]}"; do
    if ! echo "$RAW_DATA" | grep -q "AGENT	$agent	"; then
      UNUSED="$UNUSED  - $agent\n"
    fi
  done
  if [ -n "$UNUSED" ]; then
    echo "### 미사용 에이전트 (이번 주 호출 0건)"
    printf "$UNUSED"
    echo ""
    echo "→ 다음 주 의식적 활용 또는 정리 후보"
    echo ""
  fi

  echo "## 다음 주 액션"
  echo ""
  echo "- [ ] 실패율 높은 에이전트 파이프라인 재검토"
  echo "- [ ] 미사용 에이전트 활용 또는 정리"
  echo "- [ ] 호출 패턴 다양화 (현재 \\$TOP_AGENT 의존도 높음 가능성)"
  echo ""
  echo "_자동 생성: \`~/.claude/scripts/retro-weekly.sh\` ($(date +%Y-%m-%d_%H:%M))_"
} > "$OUTPUT"

# Obsidian에도 복사
cp "$OUTPUT" "$OBSIDIAN_OUTPUT" 2>/dev/null

echo "[retro-weekly] 완료"
echo "  - $OUTPUT"
echo "  - $OBSIDIAN_OUTPUT"
