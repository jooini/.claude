#!/bin/zsh
# UserPromptSubmit 통합 라우터
#
# 기존 13개 훅을 모두 호출하되, 출력을 우선순위(P0~P3)로 필터링하여 최대 N개만 표시.
# 행동(부수효과: 캡처/카운터/큐)은 모두 보존, 사용자에게 보이는 reminder만 압축.
#
# 우선순위:
#   P0 (필수): memory-search-suggest, ultrathink-auto-trigger, assumption-warning
#   P1 (강추천): workflow-md-inject
#   P2 (정보): auto-scale-detect, qq-realtime-warning, self-reflection-inject
#   P3 (선택): command-suggest, simple-query-ollama-route
#   SILENT: turn-marker, session-turn-counter, learning-queue-capture
#
# 표시 정책:
#   - P0 발동 시 P1/P2/P3 출력 억제 (최대 P0만 표시)
#   - P0 없으면 P1 1개 + P2 최대 1개
#   - SILENT는 출력 무관, 부수효과만

: "${HOME:?}"
HOOKS="$HOME/.claude/hooks"
LOG="$HOME/.claude/cache/user-prompt-router.log"
LOG_DIR="$(dirname "$LOG")"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# stdin은 한 번만 읽을 수 있으므로 캐싱
INPUT=$(cat)

emit_output() {
    local text="$1"
    [ -n "$text" ] || return 0

    if [ -n "${CODEX_THREAD_ID:-}" ] && [ "${CLAUDE_ROUTER_TEXT_OUTPUT:-0}" != "1" ]; then
        # Codex rejects Claude-specific UserPromptSubmit output schemas.
        # Keep sub-hook side effects, but suppress stdout for Codex sessions.
        return 0
    else
        printf '%s' "$text"
    fi
}

log_router() {
    [ -w "$LOG_DIR" ] || return 0
    { echo "$1"; } >> "$LOG" 2>/dev/null || true
}

# 단일 sub-hook 실행 — stdin 재공급 후 stdout 캡처
run_hook() {
    local name="$1"
    local script="$HOOKS/$name"
    [ -x "$script" ] || return 1
    echo "$INPUT" | "$script" 2>/dev/null
}

# 우선순위별 실행
P0_OUT=""
P1_OUT=""
P2_OUT=""
P3_OUT=""

# === P0 (필수, 행동 변경 강제) ===
out=$(run_hook assumption-warning.sh); [ -n "$out" ] && P0_OUT+="$out"$'\n'
out=$(run_hook ultrathink-auto-trigger.sh); [ -n "$out" ] && P0_OUT+="$out"$'\n'
out=$(run_hook memory-search-suggest.sh); [ -n "$out" ] && P0_OUT+="$out"$'\n'

# === P1 (강추천, 컨텍스트 보강) ===
out=$(run_hook workflow-md-inject.sh); [ -n "$out" ] && P1_OUT+="$out"$'\n'

# === P2 (정보, 압축 가능) ===
out=$(run_hook auto-scale-detect.sh); [ -n "$out" ] && P2_OUT+="$out"$'\n'
out=$(run_hook qq-realtime-warning.sh); [ -n "$out" ] && P2_OUT+="$out"$'\n'
out=$(run_hook self-reflection-inject.sh); [ -n "$out" ] && P2_OUT+="$out"$'\n'

# === P3 (선택, 발동 시에만) ===
out=$(run_hook simple-query-ollama-route.sh); [ -n "$out" ] && P3_OUT+="$out"$'\n'
out=$(run_hook command-suggest.sh); [ -n "$out" ] && P3_OUT+="$out"$'\n'

# === SILENT (부수효과만, 출력 무시) ===
run_hook turn-marker.sh >/dev/null 2>&1
run_hook session-turn-counter.sh >/dev/null 2>&1
run_hook learning-queue-capture.sh >/dev/null 2>&1

# === 출력 정책 적용 ===
TS=$(date '+%Y-%m-%d %H:%M:%S')
HAVE_P0=0
[ -n "$P0_OUT" ] && HAVE_P0=1
FINAL_OUT=""

if [ $HAVE_P0 -eq 1 ]; then
    # P0 발동: P0만 출력 (P1/P2/P3 억제)
    FINAL_OUT="$P0_OUT"
    log_router "[router $TS] P0 활성 — P1/P2/P3 출력 억제됨"
else
    # P0 없음: P1 + P2 최대 1개
    [ -n "$P1_OUT" ] && FINAL_OUT+="$P1_OUT"
    if [ -n "$P2_OUT" ]; then
        # P2 첫 블록만 (system-reminder 1개)
        FINAL_OUT+="$(echo "$P2_OUT" | awk '/UserPromptSubmit hook success/{c++} c<2' | head -20)"
        FINAL_OUT+=$'\n'
    fi
    # P3는 P1/P2 모두 없을 때만
    if [ -z "$P1_OUT" ] && [ -z "$P2_OUT" ] && [ -n "$P3_OUT" ]; then
        FINAL_OUT+="$(printf '%s' "$P3_OUT" | head -20)"
        FINAL_OUT+=$'\n'
    fi
    log_router "[router $TS] P1=$([ -n "$P1_OUT" ] && echo 1 || echo 0) P2=$([ -n "$P2_OUT" ] && echo 1 || echo 0) P3=$([ -n "$P3_OUT" ] && echo 1 || echo 0)"
fi

emit_output "$FINAL_OUT"

exit 0
