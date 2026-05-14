#!/bin/zsh
# SessionStart hook: 어제 닫지 못한 부채를 컨텍스트에 주입한다.
#
# 측정 항목:
#   - 미커밋 프로젝트 수 (~/Workspace 하위)
#   - 미푸시 커밋 수
#   - 어제 closure-violations 위반 건수 (closure-gate-stop.sh가 기록)
#   - 신규 스킬/훅 (지난 7일) vs retire 건수 (지난 7일 _disabled/ 이동)
#
# additionalContext로 출력 → Claude 컨텍스트에 주입.

: "${HOME:?}"

# 첫 SessionStart에만 발동 (resume/clear는 패스)
INPUT=$(cat 2>/dev/null || true)
SOURCE=$(echo "$INPUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('source',''))
except: pass" 2>/dev/null)

# startup 일 때만 실행 (resume/clear/compact 시엔 노이즈)
if [ -n "$SOURCE" ] && [ "$SOURCE" != "startup" ]; then
    exit 0
fi

CACHE_DIR="$HOME/.claude/cache"
mkdir -p "$CACHE_DIR"
DEBT_CACHE="$CACHE_DIR/closure-debt-$(date +%Y-%m-%d).txt"

# SessionStart hook stdout (exit 0) = Claude LLM 컨텍스트로 주입.
# 사용자가 원하는 동작: Claude가 첫 응답에 부채를 자동 언급.
if [ -f "$DEBT_CACHE" ]; then
    if [ -s "$DEBT_CACHE" ]; then
        cat "$DEBT_CACHE"
    fi
    exit 0
fi

YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d 'yesterday' +%Y-%m-%d 2>/dev/null)
WORKSPACE="$HOME/Workspace"
VIOLATIONS_LOG="$CACHE_DIR/closure-violations.jsonl"

# 1. 미커밋 프로젝트 — Workspace 하위 git repo 중 dirty 상태인 것
UNCOMMITTED=0
UNCOMMITTED_LIST=""
if [ -d "$WORKSPACE" ]; then
    while IFS= read -r repo; do
        [ -z "$repo" ] && continue
        repo_dir=$(dirname "$repo")
        [ -d "$repo_dir" ] || continue
        if ! git -C "$repo_dir" diff --quiet 2>/dev/null || \
           ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
            UNCOMMITTED=$((UNCOMMITTED + 1))
            UNCOMMITTED_LIST="$UNCOMMITTED_LIST $(basename "$repo_dir")"
        fi
    done < <(find "$WORKSPACE" -maxdepth 3 -type d -name .git 2>/dev/null | head -100)
fi

# 2. 미푸시 커밋 — Workspace 하위 ahead > 0
UNPUSHED=0
if [ -d "$WORKSPACE" ]; then
    while IFS= read -r repo; do
        [ -z "$repo" ] && continue
        repo_dir=$(dirname "$repo")
        [ -d "$repo_dir" ] || continue
        ahead=$(git -C "$repo_dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
        UNPUSHED=$((UNPUSHED + ahead))
    done < <(find "$WORKSPACE" -maxdepth 3 -type d -name .git 2>/dev/null | head -100)
fi

# 3. 어제 위반 건수
YESTERDAY_VIOLATIONS=0
if [ -f "$VIOLATIONS_LOG" ]; then
    YESTERDAY_VIOLATIONS=$(grep -c "\"date\":\"$YESTERDAY\"" "$VIOLATIONS_LOG" 2>/dev/null | tr -d ' \n' || true)
    [ -z "$YESTERDAY_VIOLATIONS" ] && YESTERDAY_VIOLATIONS=0
fi

# 4. 7일간 신규 스킬/훅 vs retire
SKILL_DIR="$HOME/.claude/skills"
HOOK_DIR="$HOME/.claude/hooks"
NEW_SKILLS=0
NEW_HOOKS=0
RETIRED=0
if [ -d "$SKILL_DIR" ]; then
    NEW_SKILLS=$(find "$SKILL_DIR" -maxdepth 2 -type d -mtime -7 2>/dev/null | grep -cv "^$SKILL_DIR$" 2>/dev/null | tr -d ' \n' || true)
    [ -z "$NEW_SKILLS" ] && NEW_SKILLS=0
fi
if [ -d "$HOOK_DIR" ]; then
    NEW_HOOKS=$(find "$HOOK_DIR" -maxdepth 1 -type f -name "*.sh" -mtime -7 2>/dev/null | wc -l | tr -d ' \n')
fi
if [ -d "$HOOK_DIR/_disabled" ]; then
    RETIRED=$(find "$HOOK_DIR/_disabled" -maxdepth 1 -type f -mtime -7 2>/dev/null | wc -l | tr -d ' \n')
fi

# 출력 — 부채가 없으면 침묵
TOTAL=$((UNCOMMITTED + UNPUSHED + YESTERDAY_VIOLATIONS))
if [ "$TOTAL" -eq 0 ]; then
    > "$DEBT_CACHE"
    exit 0
fi

DEBT_BODY=$({
    echo "[CLOSURE-GATE 일일 부채 — $(date +%Y-%m-%d)]"
    echo ""
    echo "*** Claude는 이번 세션 첫 응답을 시작하기 전, 사용자에게 아래 부채 현황을 명시적으로 알리고 처리 우선순위를 제안할 것. ***"
    echo ""
    echo "어제 닫지 못한 것:"
    [ "$UNCOMMITTED" -gt 0 ] && echo "  🔴 미커밋 ${UNCOMMITTED} 프로젝트:${UNCOMMITTED_LIST}"
    [ "$UNPUSHED" -gt 0 ] && echo "  🔴 미푸시 ${UNPUSHED} 커밋"
    [ "$YESTERDAY_VIOLATIONS" -gt 0 ] && echo "  🟡 어제 단언/추정/자의결정 위반 ${YESTERDAY_VIOLATIONS}건 (closure-violations.jsonl)"
    echo ""
    echo "지난 7일 자산 흐름:"
    echo "  ▲ 신규: 스킬 ${NEW_SKILLS} / 훅 ${NEW_HOOKS}"
    echo "  ▼ retire: ${RETIRED}"
    if [ "$RETIRED" -eq 0 ] && [ $((NEW_SKILLS + NEW_HOOKS)) -gt 5 ]; then
        echo "  ⚠️ 자산 라이프사이클 불균형 — 새로 만들기 전에 정리 권장"
    fi
    echo ""
    echo "→ 새 작업 시작 전 위 중 최소 1개 닫아라. /done 또는 명시적 결정."
})

printf '%s\n' "$DEBT_BODY" | tee "$DEBT_CACHE"
exit 0
