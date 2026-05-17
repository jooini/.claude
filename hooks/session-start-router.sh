#!/bin/zsh
# SessionStart 통합 라우터
#
# 기존 15개 훅(GitKraken 제외)을 모두 호출하되, 사용자에게 보이는 reminder는
# 우선순위로 압축. 부수효과(빌드/캐시/restore)는 모두 보존.
#
# 우선순위:
#   P0 (필수 표시): delegation-principle-inject (위임 룰), session-today-reminder (오늘 브리핑)
#   P1 (선택 표시): qwen-project-context-inject, gemma-intent-restore
#   P2 (조용히): morning-brief, weekly-retro, alias-suggest — 가끔 길어서 부담
#   SILENT (부수효과만): node-version-sync, build-agents, detect-language, active-tasks,
#                       mcp-healthcheck, wsq-catalog-refresh, wsq-daily-sweep, hook-dormant-warn

: "${HOME:?}"
HOOKS="$HOME/.claude/hooks"
LOG="$HOME/.claude/cache/session-start-router.log"
mkdir -p "$(dirname "$LOG")"

INPUT=$(cat)

run_hook() {
    local name="$1"
    local script="$HOOKS/$name"
    [ -x "$script" ] || return 1
    echo "$INPUT" | "$script" 2>/dev/null
}

# === SILENT 먼저 (부수효과만, 결과 무시) ===
run_hook node-version-sync.sh >/dev/null 2>&1
run_hook session-build-agents.sh >/dev/null 2>&1
run_hook session-detect-language.sh >/dev/null 2>&1
run_hook session-active-tasks.sh >/dev/null 2>&1
run_hook mcp-healthcheck.sh >/dev/null 2>&1
run_hook SessionStart/wsq-catalog-refresh.sh >/dev/null 2>&1
run_hook SessionStart/wsq-daily-sweep.sh >/dev/null 2>&1
run_hook hook-dormant-warn.sh >/dev/null 2>&1

# === P0 (반드시 표시) ===
P0_OUT=""
out=$(run_hook delegation-principle-inject.sh); [ -n "$out" ] && P0_OUT+="$out"$'\n'
out=$(run_hook session-today-reminder.sh); [ -n "$out" ] && P0_OUT+="$out"$'\n'

# === P1 (있을 때만) ===
P1_OUT=""
out=$(run_hook qwen-project-context-inject.sh); [ -n "$out" ] && P1_OUT+="$out"$'\n'
out=$(run_hook gemma-intent-restore.sh); [ -n "$out" ] && P1_OUT+="$out"$'\n'

# === P2 (가끔 너무 길어서 압축 후보) ===
# 아침 브리핑/주간 회고: 무거워서 timeout 길게 잡혀있음. P0 정보와 겹칠 수 있어 압축.
P2_OUT=""
out=$(run_hook gemma-morning-brief.sh); [ -n "$out" ] && P2_OUT+="$out"$'\n'
out=$(run_hook qwen-weekly-retro.sh); [ -n "$out" ] && P2_OUT+="$out"$'\n'
out=$(run_hook qwen-alias-suggest.sh); [ -n "$out" ] && P2_OUT+="$out"$'\n'

# === LLM-Wiki manifest drift (있을 때만 출력, P1 동급 정보성) ===
out=$(run_hook vault-manifest-drift-detect.sh); [ -n "$out" ] && P1_OUT+="$out"$'\n'

# === 출력 정책 ===
TS=$(date '+%Y-%m-%d %H:%M:%S')

# 항상 P0 우선
[ -n "$P0_OUT" ] && printf '%s' "$P0_OUT"

# P1은 P0 있어도 같이 표시 (정보성)
[ -n "$P1_OUT" ] && printf '%s' "$P1_OUT"

# P2는 매번 다 보여주면 부담 → 첫 1개만
if [ -n "$P2_OUT" ]; then
    echo "$P2_OUT" | awk '/SessionStart:startup hook success/{c++} c<2' | head -40
fi

echo "[router $TS] P0=$([ -n "$P0_OUT" ] && echo 1 || echo 0) P1=$([ -n "$P1_OUT" ] && echo 1 || echo 0) P2=$([ -n "$P2_OUT" ] && echo 1 || echo 0)" >> "$LOG"

exit 0
