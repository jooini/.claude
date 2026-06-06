#!/bin/zsh
# Common shell adapter for LLM calls from hooks/scripts.
#
# Usage:
#   llm-call.sh gemini --caller hook-name --timeout 30 --prompt "question"
#   llm-call.sh codex  --caller hook-name --timeout 90 --prompt "question"
#   printf '%s' "$PROMPT" | llm-call.sh ini --caller hook-name --timeout 30 --model gemma4:e4b --prompt -
#
# The provider output is written to stdout. Adapter telemetry is appended to:
#   ~/.claude/cache/llm-adapter-calls.jsonl

: "${HOME:?}"

ROOT="$HOME/.claude"
LOG_FILE="$ROOT/cache/llm-adapter-calls.jsonl"
mkdir -p "$ROOT/cache"

usage() {
    cat >&2 <<'EOF'
Usage: llm-call.sh <gemini|codex|ini> [--caller NAME] [--timeout SECONDS] [--prompt TEXT|-] [provider options]

Options:
  --caller NAME       Logical caller name for telemetry.
  --timeout SECONDS   Hard timeout for the provider command.
  --prompt TEXT       Prompt text. Use "-" to read prompt from stdin.
  --profile NAME      ini profile. Ignored by the Python Ollama fallback path.
  --num-ctx N         ini context window. Ignored by the Python Ollama fallback path.
  --model NAME        model override when supported.
EOF
}

if [ $# -lt 1 ]; then
    usage
    exit 2
fi

PROVIDER="$1"
shift

CALLER="unknown"
CALL_TIMEOUT=30
PROMPT=""
PROFILE=""
NUM_CTX=""
MODEL=""

while [ $# -gt 0 ]; do
    case "$1" in
        --caller)
            CALLER="$2"
            shift 2
            ;;
        --timeout)
            CALL_TIMEOUT="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --num-ctx)
            NUM_CTX="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "llm-call: unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [ "$PROMPT" = "-" ]; then
    PROMPT=$(cat)
fi

if [ -z "$PROMPT" ]; then
    echo "llm-call: --prompt is required" >&2
    exit 2
fi

if ! [[ "$CALL_TIMEOUT" =~ '^[0-9]+$' ]] || [ "$CALL_TIMEOUT" -le 0 ]; then
    echo "llm-call: --timeout must be a positive integer" >&2
    exit 2
fi

[ -f "$ROOT/scripts/_nvm-path.sh" ] && . "$ROOT/scripts/_nvm-path.sh"

OUT_FILE=$(mktemp)
ERR_FILE=$(mktemp)
PROMPT_FILE=$(mktemp)
trap 'rm -f "$OUT_FILE" "$ERR_FILE" "$PROMPT_FILE"' EXIT
printf '%s' "$PROMPT" > "$PROMPT_FILE"

START_MS=$(/usr/bin/python3 -c "import time; print(int(time.time() * 1000))")
EXIT_CODE=0

run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$CALL_TIMEOUT" "$@" > "$OUT_FILE" 2> "$ERR_FILE"
    else
        "$@" > "$OUT_FILE" 2> "$ERR_FILE"
    fi
    return $?
}

case "$PROVIDER" in
    gemini|agy)
        GEMINI_WRAPPER="$ROOT/scripts/gemini-wrapped.sh"
        if [ ! -x "$GEMINI_WRAPPER" ]; then
            echo "llm-call: missing executable $GEMINI_WRAPPER" >&2
            exit 127
        fi
        run_with_timeout env GEMINI_CALLER="$CALLER" "$GEMINI_WRAPPER" -p "$PROMPT"
        EXIT_CODE=$?
        ;;
    codex)
        CODEX_BIN="codex"
        if ! command -v codex >/dev/null 2>&1; then
            CODEX_BIN="$HOME/.nvm/versions/node/v22.22.0/bin/codex"
        fi
        if [ ! -x "$CODEX_BIN" ] && ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
            echo "llm-call: codex executable not found" >&2
            exit 127
        fi
        run_with_timeout "$CODEX_BIN" exec --skip-git-repo-check "$PROMPT"
        EXIT_CODE=$?
        ;;
    ini|ollama|gemma|qwen)
        INI_HELPER="$ROOT/scripts/_lib_ini_call.py"
        if [ ! -f "$INI_HELPER" ]; then
            echo "llm-call: missing helper $INI_HELPER" >&2
            exit 127
        fi
        INI_ARGS=(--caller "$CALLER" --timeout "$CALL_TIMEOUT" --prompt -)
        [ -n "$MODEL" ] && INI_ARGS+=(--model "$MODEL")
        if command -v timeout >/dev/null 2>&1; then
            timeout "$CALL_TIMEOUT" /usr/bin/python3 "$INI_HELPER" "${INI_ARGS[@]}" < "$PROMPT_FILE" > "$OUT_FILE" 2> "$ERR_FILE"
        else
            /usr/bin/python3 "$INI_HELPER" "${INI_ARGS[@]}" < "$PROMPT_FILE" > "$OUT_FILE" 2> "$ERR_FILE"
        fi
        EXIT_CODE=$?
        ;;
    *)
        echo "llm-call: unsupported provider: $PROVIDER" >&2
        usage
        exit 2
        ;;
esac

END_MS=$(/usr/bin/python3 -c "import time; print(int(time.time() * 1000))")
DURATION_MS=$((END_MS - START_MS))
OUT_BYTES=$(/usr/bin/wc -c < "$OUT_FILE" | tr -d ' ')
ERR_BYTES=$(/usr/bin/wc -c < "$ERR_FILE" | tr -d ' ')
PROMPT_LENGTH=${#PROMPT}
RESPONSE_LENGTH=$(/usr/bin/python3 - "$OUT_FILE" <<'PYEOF'
import sys
from pathlib import Path

print(len(Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")))
PYEOF
)

cat "$OUT_FILE"

/usr/bin/python3 - "$LOG_FILE" "$PROVIDER" "$CALLER" "$CALL_TIMEOUT" "$EXIT_CODE" "$DURATION_MS" "$OUT_BYTES" "$ERR_BYTES" "$PROMPT_LENGTH" "$RESPONSE_LENGTH" "$MODEL" <<'PYEOF'
import json
import sys
from datetime import datetime, timezone

(
    log_file,
    provider,
    caller,
    timeout,
    exit_code,
    duration_ms,
    out_bytes,
    err_bytes,
    prompt_length,
    response_length,
    model,
) = sys.argv[1:]
record = {
    "schema_version": 1,
    "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "adapter": "shell",
    "provider": provider,
    "caller": caller,
    "model": model or None,
    "timeout_seconds": int(timeout),
    "status": "ok" if int(exit_code) == 0 else "error",
    "exit_code": int(exit_code),
    "duration_ms": int(duration_ms),
    "output_bytes": int(out_bytes),
    "stderr_bytes": int(err_bytes),
    "prompt_length": int(prompt_length),
    "response_length": int(response_length),
}
with open(log_file, "a", encoding="utf-8") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")
PYEOF

if [ "$EXIT_CODE" -ne 0 ]; then
    if [ "$ERR_BYTES" -gt 0 ]; then
        head -20 "$ERR_FILE" >&2
    fi
fi

exit "$EXIT_CODE"
