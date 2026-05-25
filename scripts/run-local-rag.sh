#!/bin/bash
# local-rag MCP launcher (hardened 2026-05-25)
# - PATH 고정: Claude Code sub-shell이 nvm을 못 sourcing해도 npx/node를 찾도록
# - prewarm: npx 패키지 캐시를 강제로 데워서 tools/list 응답 지연을 줄임
# - 첫 응답이 deferred 카탈로그 빌드 윈도우(15s)를 못 넘기는 사고 방지

set -u

# 1) node 22 우선, fallback chain
NODE_BIN_DIR=""
for v in v22.22.0 v22.4.1 v14.1.0; do
  if [ -x "/Users/leonard/.nvm/versions/node/$v/bin/npx" ]; then
    NODE_BIN_DIR="/Users/leonard/.nvm/versions/node/$v/bin"
    break
  fi
done

if [ -z "$NODE_BIN_DIR" ]; then
  echo "run-local-rag: npx not found in known nvm paths" >&2
  exit 127
fi

# 2) PATH 명시 (sub-shell 의존 제거)
export PATH="$NODE_BIN_DIR:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"

# 3) BASE_DIR = Workspace (노트 + 코드 둘 다 검색)
export RAG_BASE_DIR="/Users/leonard/Workspace"
export BASE_DIR="/Users/leonard/Workspace"
export DB_PATH="/Users/leonard/Workspace/lancedb"
export CACHE_DIR="/Users/leonard/.claude/cache/rag-models"
export MODEL_NAME="Xenova/multilingual-e5-small"

# 4) npx 패키지 캐시 prewarm (백그라운드로 분리하지 않음 — 동기적으로 한 번 dry-run)
#    --quiet --no-install 로 cache hit 확인만, miss면 실제 install (한 번만 비용 발생)
#    실패해도 본 실행은 계속
"$NODE_BIN_DIR/npm" exec --prefix /tmp -c 'true' --package=mcp-local-rag --silent 2>/dev/null || true

# 5) cd to Workspace — 상대경로 스캔 시작점 고정
cd "/Users/leonard/Workspace" || exit 1

# 6) 실제 MCP 서버 기동 (stdio)
exec "$NODE_BIN_DIR/npx" -y mcp-local-rag
