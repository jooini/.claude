#!/bin/zsh
# Hook execution timing & no-op detection wrapper
# 다른 훅들이 source 해서 사용:
#   source "$HOME/.claude/hooks/_lib/hook-timing.sh"
#   hook_timing_start "my-hook-name"
#   ... 훅 본문 ...
#   hook_timing_end  # 자동으로 stdout/stderr/exit 차이 기록
#
# 또는 외부 wrapper로 사용 (settings.json에서):
#   /bin/zsh ~/.claude/hooks/_lib/hook-timing.sh ~/.claude/hooks/실제훅.sh
#
# 출력: ~/.claude/cache/hook-timing/YYYY-MM-DD.tsv
# 컬럼: timestamp	hook_name	duration_ms	exit_code	stdout_bytes	stderr_bytes	side_effect

: "${HOME:?}"

TIMING_DIR="$HOME/.claude/cache/hook-timing"
TRACE_DIR="$HOME/.claude/cache/hook-trace"
mkdir -p "$TIMING_DIR" "$TRACE_DIR"

_hook_timing_log() {
    local hook_name="$1"
    local duration_ms="$2"
    local exit_code="$3"
    local stdout_bytes="$4"
    local stderr_bytes="$5"
    local event="${6:-}"
    local tool="${7:-}"
    local session="${8:-}"

    local side_effect="noop"
    if [ "$exit_code" != "0" ]; then
        side_effect="block_or_error"
    elif [ "$stdout_bytes" -gt 0 ] || [ "$stderr_bytes" -gt 0 ]; then
        side_effect="output"
    fi

    local date_str=$(date +"%Y-%m-%d")
    local ts=$(date +"%Y-%m-%dT%H:%M:%S")
    local tsv_file="$TIMING_DIR/${date_str}.tsv"
    local jsonl_file="$TRACE_DIR/${date_str}.jsonl"

    # 기존 TSV (호환성 유지)
    if [ ! -f "$tsv_file" ]; then
        echo -e "timestamp\thook\tduration_ms\texit\tstdout_bytes\tstderr_bytes\tside_effect" > "$tsv_file"
    fi
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$ts" "$hook_name" "$duration_ms" "$exit_code" "$stdout_bytes" "$stderr_bytes" "$side_effect" \
        >> "$tsv_file"

    # 신규 JSONL (E안: event/tool/session 포함)
    # printf %s 시 따옴표 이스케이프 — 단순 슬래시/공백만 가정
    printf '{"ts":"%s","hook":"%s","ms":%s,"exit":%s,"side":"%s","event":"%s","tool":"%s","session":"%s"}\n' \
        "$ts" "$hook_name" "$duration_ms" "$exit_code" "$side_effect" "$event" "$tool" "$session" \
        >> "$jsonl_file"
}

# 외부 wrapper 모드: $1 = 실행할 훅 경로
if [ "${ZSH_EVAL_CONTEXT:-toplevel}" = "toplevel" ] && [ -n "$1" ] && [ -x "$1" ]; then
    HOOK_PATH="$1"
    HOOK_NAME=$(basename "$HOOK_PATH" .sh)

    # stdin 캡처 (메타데이터 추출용 + 훅에 그대로 전달)
    STDIN_FILE=$(mktemp)
    STDOUT_FILE=$(mktemp)
    STDERR_FILE=$(mktemp)
    trap 'rm -f "$STDIN_FILE" "$STDOUT_FILE" "$STDERR_FILE"' EXIT

    # stdin을 변수로 한 번만 읽기 (mktemp 파일 IO 회피)
    STDIN_RAW="$(cat)"
    printf '%s' "$STDIN_RAW" > "$STDIN_FILE"

    # 메타 추출 — zsh regex (외부 명령 0회)
    EVENT=""; TOOL=""; SESSION=""
    # 앞 4KB만 검사 (긴 tool_input 본문 스킵)
    STDIN_HEAD="${STDIN_RAW[1,4096]}"
    if [[ "$STDIN_HEAD" =~ '"hook_event_name":"([^"]*)"' ]]; then
        EVENT="${match[1]}"
    fi
    if [[ "$STDIN_HEAD" =~ '"tool_name":"([^"]*)"' ]]; then
        TOOL="${match[1]}"
    fi
    if [[ "$STDIN_HEAD" =~ '"session_id":"([^"]{0,8})' ]]; then
        SESSION="${match[1]}"
    fi

    # zsh 내장 EPOCHREALTIME 사용 — 외부 명령 호출 0회 (python3 2회 제거)
    zmodload -F zsh/datetime b:strftime 2>/dev/null
    zmodload zsh/datetime
    START_NS="$EPOCHREALTIME"
    "$HOOK_PATH" < "$STDIN_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE"
    EXIT_CODE=$?
    END_NS="$EPOCHREALTIME"

    # 부동소수점 ms 차이 계산 (정수만)
    DURATION_MS=$(( (END_NS - START_NS) * 1000 ))
    DURATION_MS=${DURATION_MS%.*}
    # zsh stat 모듈로 wc -c 대체 (외부 명령 0회)
    zmodload -F zsh/stat b:zstat 2>/dev/null
    zstat -A SO_STAT +size "$STDOUT_FILE" 2>/dev/null
    zstat -A SE_STAT +size "$STDERR_FILE" 2>/dev/null
    STDOUT_BYTES="${SO_STAT[1]:-0}"
    STDERR_BYTES="${SE_STAT[1]:-0}"

    _hook_timing_log "$HOOK_NAME" "$DURATION_MS" "$EXIT_CODE" "$STDOUT_BYTES" "$STDERR_BYTES" "$EVENT" "$TOOL" "$SESSION"

    cat "$STDOUT_FILE"
    cat "$STDERR_FILE" >&2

    exit $EXIT_CODE
fi
