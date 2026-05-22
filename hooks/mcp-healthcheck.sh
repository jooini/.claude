#!/bin/zsh
# SessionStart: MCP 서버 + 외부 의존성 헬스체크
#
# 검증 대상:
#   1. local-rag (RAG_BASE_DIR 존재)
#   2. claude-mem worker (port 37777)
#   3. Ollama (leonard.local:11434) — Gemma 호출용
#   4. Gemini CLI (gemini 명령어 가용)
#   5. Codex CLI (codex 명령어 가용)
#
# 결과:
#   - 모두 정상 → 침묵
#   - 1개 이상 실패 → 컨텍스트 주입 (사용자가 알아채도록)
#
# 조건: startup 매처만 (resume/clear 시 스킵)

: "${HOME:?}"

INPUT=$(cat)
MATCHER=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('matcher', ''))
except Exception:
    pass
" 2>/dev/null)

if [ "$MATCHER" != "startup" ]; then
    exit 0
fi

# 캐시: 30분 이내 이미 체크했으면 스킵 (성능)
CACHE="$HOME/.claude/cache/mcp-healthcheck.cache"
if [ -f "$CACHE" ]; then
    AGE=$(( $(date +%s) - $(/usr/bin/stat -f "%m" "$CACHE" 2>/dev/null || echo 0) ))
    if [ "$AGE" -lt 1800 ]; then
        # 캐시 결과만 출력
        if [ -s "$CACHE" ]; then
            cat "$CACHE"
        fi
        exit 0
    fi
fi

ERRORS=()

# 1. local-rag (DB 파일 존재 + 크기 확인)
RAG_DB="$HOME/Workspace/lancedb/chunks.lance"
if [ ! -d "$RAG_DB" ]; then
    ERRORS+=("local-rag: DB 디렉토리 없음 ($RAG_DB)")
fi

# 2. claude-mem worker (port 37777) — 깨졌으면 자동 재기동 시도
HEALTH=$(/usr/bin/curl -s --max-time 2 http://localhost:37777/health 2>/dev/null)
if [ -z "$HEALTH" ] || ! echo "$HEALTH" | /usr/bin/grep -q "ok"; then
    # 자동 재기동: worker-cli.js start (detached)
    # Codex 권고: kill 단독은 PID/캐시 꼬임 → worker-service의 start 명령 사용
    WORKER_DIR="$HOME/.claude/plugins/cache/thedotmack/claude-mem/10.6.2"

    if [ -d "$WORKER_DIR" ] && [ -x "/opt/homebrew/bin/node" ]; then
        # Stale PID 파일 정리 (프로세스 죽었는데 파일만 남은 경우)
        OLD_PID_FILE="$HOME/.claude-mem/worker.pid"
        if [ -f "$OLD_PID_FILE" ]; then
            OLD_PID=$(/usr/bin/python3 -c "
import json
try:
    print(json.load(open('$OLD_PID_FILE')).get('pid',''))
except: pass
" 2>/dev/null)
            if [ -n "$OLD_PID" ] && ! /bin/kill -0 "$OLD_PID" 2>/dev/null; then
                /bin/rm -f "$OLD_PID_FILE"
            fi
        fi

        # 새 워커 detached spawn
        (
            cd "$WORKER_DIR" && \
            /usr/bin/nohup /opt/homebrew/bin/node scripts/bun-runner.js scripts/worker-cli.js start \
                </dev/null >/dev/null 2>&1 &
        ) 2>/dev/null

        # 최대 5초 대기 후 재검증
        REVIVED=""
        for i in 1 2 3 4 5; do
            sleep 1
            NEW_HEALTH=$(/usr/bin/curl -s --max-time 1 http://localhost:37777/health 2>/dev/null)
            if echo "$NEW_HEALTH" | /usr/bin/grep -q "ok"; then
                REVIVED="$i"
                break
            fi
        done

        if [ -n "$REVIVED" ]; then
            ERRORS+=("claude-mem worker: 자동 재기동 성공 (port 37777, ${REVIVED}초)")
        else
            ERRORS+=("claude-mem worker (port 37777): 응답 없음 + 자동 재기동 실패 (5초 timeout) — 메모리 검색 작동 안 함")
        fi
    else
        ERRORS+=("claude-mem worker (port 37777): 응답 없음 — plugin 디렉토리 또는 node 없음")
    fi
fi

# 3. Ollama (Gemma 호출용)
OLLAMA_TAGS=$(/usr/bin/curl -s --max-time 2 http://leonard.local:11434/api/tags 2>/dev/null)
if [ -z "$OLLAMA_TAGS" ]; then
    ERRORS+=("Ollama (leonard.local:11434): 응답 없음 — Gemma cron + ask-gemma 작동 안 함")
fi

# 4. Gemini/Antigravity CLI (2026-06-18부터 agy가 기본)
if ! command -v agy >/dev/null 2>&1 && ! command -v gemini >/dev/null 2>&1; then
    ERRORS+=("agy/gemini CLI: 둘 다 없음 — Phase 0 스캔/3중 리뷰 작동 안 함")
fi

# 5. Codex CLI
if ! command -v codex >/dev/null 2>&1; then
    # codex는 npm/nvm 경로일 수도 있음 — 추가 확인
    if [ ! -x "$HOME/.nvm/versions/node/v22.22.0/bin/codex" ]; then
        ERRORS+=("Codex CLI: 명령어 없음 — codex:review/rescue 작동 안 함")
    fi
fi

# 결과 출력
if [ ${#ERRORS[@]} -eq 0 ]; then
    # 정상 — 캐시 비우고 종료
    > "$CACHE"
    exit 0
fi

# 비정상 — 컨텍스트 주입 + 캐시 저장
{
    echo "[⚠️ MCP/외부 도구 헬스체크 실패]"
    echo ""
    echo "다음 도구가 정상 동작하지 않음:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    echo ""
    echo "해결 방법:"
    echo "  - claude-mem: \`cd ~/.claude/plugins/marketplaces/thedotmack/plugin && node scripts/worker-service.cjs start\`"
    echo "  - Ollama: 윈도우 노트북에서 \`ollama serve\` 또는 트레이 실행"
    echo "  - agy(Antigravity): https://antigravity.google/download — 2026-06-18부터 gemini CLI deprecated"
    echo "  - Codex: \`npm install -g @openai/codex\`"
    echo ""
    echo "30분간 캐시됨. 재확인하려면 \`rm $CACHE\`"
} | tee "$CACHE"

exit 0
