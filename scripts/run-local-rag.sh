#!/bin/bash
# BASE_DIR = Workspace (노트 + 코드 둘 다 검색)
# 홈(.Trash 등) 권한 에러 회피
export RAG_BASE_DIR="/Users/leonard/Workspace"
export BASE_DIR="/Users/leonard/Workspace"
export DB_PATH="/Users/leonard/Workspace/lancedb"
export CACHE_DIR="/Users/leonard/.claude/cache/rag-models"
export MODEL_NAME="Xenova/multilingual-e5-small"
# cd to Workspace — 상대경로 스캔 시작점 고정
cd "/Users/leonard/Workspace" || exit 1
exec npx -y mcp-local-rag
