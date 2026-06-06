#!/bin/bash
# Gemma/Ollama 호환 래퍼.
#
# 사용법:
#   RESULT=$(~/.claude/scripts/gemma-logger.sh <caller_name> <model> <prompt> [num_predict] [temperature])
#
# 실제 호출, ini fallback, urllib fallback, JSONL 로깅은 Python 공용 라이브러리
# scripts/_lib_ini_call.py가 담당한다. 이 파일은 기존 shell 호출부 호환성만 유지한다.

set -euo pipefail

: "${HOME:?}"

CALLER="${1:-unknown}"
MODEL="${2:-gemma4:e4b}"
PROMPT="${3:-}"
NUM_PREDICT="${4:-800}"
TEMPERATURE="${5:-0.3}"
TIMEOUT="${GEMMA_LOGGER_TIMEOUT:-90}"

if [ -z "$PROMPT" ]; then
    echo "Usage: gemma-logger.sh <caller> <model> <prompt> [num_predict] [temperature]" >&2
    exit 1
fi

exec python3 "$HOME/.claude/scripts/_lib_ini_call.py" \
    --caller "$CALLER" \
    --model "$MODEL" \
    --prompt "$PROMPT" \
    --num-predict "$NUM_PREDICT" \
    --temperature "$TEMPERATURE" \
    --timeout "$TIMEOUT"
