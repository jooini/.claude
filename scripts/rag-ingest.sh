#!/bin/bash

. "$HOME/.claude/scripts/_nvm-path.sh"  # nvm PATH 보강
# local-rag CLI ingest wrapper — same config as MCP server
# Usage: rag-ingest.sh <path> [--base-dir <dir>]

export DB_PATH="/Users/leonard/Workspace/lancedb"
export CACHE_DIR="/Users/leonard/.claude/cache/rag-models"
export MODEL_NAME="Xenova/multilingual-e5-small"
export BASE_DIR="/Users/leonard"

RAG_FORK_DIST="/Users/leonard/Workspace/mcp-local-rag/dist/index.js"

if [ -f "$RAG_FORK_DIST" ]; then
    exec node "$RAG_FORK_DIST" \
        --db-path "$DB_PATH" \
        --cache-dir "$CACHE_DIR" \
        --model-name "$MODEL_NAME" \
        ingest "$@"
else
    exec npx -y mcp-local-rag \
        --db-path "$DB_PATH" \
        --cache-dir "$CACHE_DIR" \
        --model-name "$MODEL_NAME" \
        ingest "$@"
fi
