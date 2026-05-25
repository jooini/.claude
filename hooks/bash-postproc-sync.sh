#!/bin/zsh
# PostToolUse(Bash) 동기 통합: stdout 주입 + side-effect hook 묶음
#   1) branch-switch-detect       → git checkout/switch 감지 → Gemini 리마인더
#   2) cwd-change-detect          → cd 감지 → 언어 재감지 + agent build 전환
#   3) gemini-auto-scan           → 프로젝트 디렉토리 진입 시 Gemini 백그라운드 스캔
#   4) gemini-test-failure-analyze → 테스트 3회 실패 시 Gemini 영향 분석
#
# 모든 출력은 stdout으로 누적. 각 hook은 독립적이며 어느 하나 실패해도 다른 hook 진행.

. "$HOME/.claude/scripts/_nvm-path.sh"  # nvm PATH 보강


: "${HOME:?}"

GEM_CLI="${GEMINI_CLI:-}"
if [ -z "$GEM_CLI" ]; then
    if command -v agy >/dev/null 2>&1; then GEM_CLI=agy
    elif command -v gemini >/dev/null 2>&1; then GEM_CLI=gemini
    fi
fi

INPUT=$(cat)

# ---------- 공통 파싱 (jq 우선, sed fallback) ----------
COMMAND=""
CWD=""
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
fi
if [ -z "$COMMAND" ]; then
    COMMAND=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)
fi
if [ -z "$CWD" ]; then
    CWD=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)
fi

# ========== 1) branch-switch-detect ==========
if echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)\s+' \
   && ! echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+'; then
    if echo "$COMMAND" | grep -qE '(-b|--branch|-c|--create)\s+'; then
        SWITCH_TYPE="새 브랜치 생성"
    else
        SWITCH_TYPE="브랜치 전환"
    fi
    BRANCH=$(echo "$COMMAND" | awk '{print $NF}')
    echo "[${SWITCH_TYPE}] ${BRANCH} — Gemini CLI로 이 브랜치의 코드베이스를 스캔하세요 (Phase 0). code-review-graph:build-graph도 고려하세요."
fi

# ========== 2) cwd-change-detect + 3) gemini-auto-scan (cd 명령 공통 트리거) ==========
if echo "$COMMAND" | grep -qE '(^cd |[;&|]\s*cd )' && [ -n "$CWD" ]; then

    # --- 2a) cwd-change-detect: 언어 재감지 + agent build 전환 ---
    STATE_FILE="/tmp/.claude-cwd-lang-$$"
    LAST_CWD=""
    [ -f "$STATE_FILE" ] && LAST_CWD=$(cat "$STATE_FILE")

    if [ "$CWD" != "$LAST_CWD" ]; then
        echo "$CWD" > "$STATE_FILE"

        # lib-detect-language.sh 가 DETECTED, FRAMEWORK, DOCKER 변수를 export
        DETECTED=""
        FRAMEWORK=""
        DOCKER=""
        if [ -f "$HOME/.claude/hooks/lib-detect-language.sh" ]; then
            source "$HOME/.claude/hooks/lib-detect-language.sh"
            detect_language "$CWD"
        fi

        PROJECT_NAME=$(basename "$CWD")
        AGENTS_DIR="$HOME/.claude/agents"
        BUILD_SCRIPT="$AGENTS_DIR/build-agents.sh"

        get_current_build() {
            for f in "$AGENTS_DIR"/*.md; do
                [ -L "$f" ] || continue
                readlink "$f" | sed -n 's|.*/builds/\([^/]*\)/.*|\1|p'
                return
            done
        }

        if [ -n "$DETECTED" ]; then
            if [ -n "$FRAMEWORK" ]; then
                echo "[프로젝트 전환] ${PROJECT_NAME}: ${DETECTED} (${FRAMEWORK})${DOCKER} — 스킬/knowledge를 이 스택 기준으로 전환"
            else
                echo "[프로젝트 전환] ${PROJECT_NAME}: ${DETECTED}${DOCKER} — 스킬/knowledge를 이 스택 기준으로 전환"
            fi

            LANG_MAP=""
            case "$DETECTED" in
                Python)     LANG_MAP="python" ;;
                Kotlin|Java) LANG_MAP="kotlin" ;;
                PHP)        LANG_MAP="php" ;;
                TypeScript|JavaScript) LANG_MAP="nodejs" ;;
            esac

            if [ -n "$LANG_MAP" ] && [ -d "$AGENTS_DIR/builds/$LANG_MAP" ] && [ -x "$BUILD_SCRIPT" ]; then
                CURRENT_BUILD=$(get_current_build)
                if [ "$CURRENT_BUILD" != "$LANG_MAP" ]; then
                    "$BUILD_SCRIPT" --use "$LANG_MAP" > /dev/null 2>&1
                    echo "[에이전트 빌드 전환] ${CURRENT_BUILD:-root} → ${LANG_MAP} (${DETECTED} knowledge 포함)"
                fi
            fi
        else
            if [ -x "$BUILD_SCRIPT" ] && [ -d "$AGENTS_DIR/builds/root" ]; then
                CURRENT_BUILD=$(get_current_build)
                if [ "$CURRENT_BUILD" != "root" ]; then
                    "$BUILD_SCRIPT" --use root > /dev/null 2>&1
                    echo "[에이전트 빌드 복원] ${CURRENT_BUILD} → root"
                fi
            fi
        fi
    fi

    # --- 2b) gemini-auto-scan: Workspace 코드 프로젝트면 Gemini 스캔 ---
    if echo "$CWD" | grep -q '/Workspace/'; then
        IS_PROJECT=0
        for f in pyproject.toml requirements.txt package.json composer.json build.gradle build.gradle.kts pom.xml go.mod Cargo.toml; do
            if [ -f "$CWD/$f" ]; then
                IS_PROJECT=1
                break
            fi
        done

        if [ "$IS_PROJECT" -eq 1 ]; then
            SCAN_STATE_FILE="$HOME/.claude/cache/.gemini-scan-state-$$"
            mkdir -p "$HOME/.claude/cache"
            LAST_SCANNED=""
            [ -f "$SCAN_STATE_FILE" ] && LAST_SCANNED=$(cat "$SCAN_STATE_FILE")

            if [ "$CWD" != "$LAST_SCANNED" ]; then
                echo "$CWD" > "$SCAN_STATE_FILE"

                PROJECT_NAME=$(basename "$CWD")
                CACHE_DIR="$HOME/.claude/cache/gemini"
                mkdir -p "$CACHE_DIR"
                OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-scan.md"

                USE_CACHE=0
                if [ -f "$OUTPUT_FILE" ]; then
                    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
                    if [ "$FILE_AGE" -lt 7200 ]; then
                        echo "[Gemini] ${PROJECT_NAME} 스캔 결과 캐시됨 → cat ${OUTPUT_FILE}"
                        USE_CACHE=1
                    fi
                fi

                if [ "$USE_CACHE" -eq 0 ] && [ -n "$GEM_CLI" ]; then
                    (
                        cd "$CWD"
                        "$GEM_CLI" -p "이 프로젝트의 구조, 주요 파일, 기술 스택, 아키텍처를 요약해줘. 핵심 엔트리포인트와 의존성 관계 중심으로. 한글로 답변." \
                            > "$OUTPUT_FILE" 2>/dev/null
                    ) &
                    echo "[Gemini 스캔 시작] ${PROJECT_NAME} — 백그라운드 실행 중 → 결과: cat ${OUTPUT_FILE}"
                fi
            fi
        fi
    fi
fi

# ========== 4) gemini-test-failure-analyze ==========
if [ -n "$GEM_CLI" ]; then
    TEST_RE='(pytest|jest|vitest|npm test|npm run test|gradle test|mvn test|go test|cargo test|phpunit|rspec)'
    if printf '%s' "$INPUT" | grep -qE "$TEST_RE"; then

        TF_EXIT_CODE=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    resp = data.get('tool_response', {})
    print(resp.get('exit_code', 0))
except Exception:
    print(0)
" 2>/dev/null)

        TF_COMMAND=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

        if echo "$TF_COMMAND" | grep -qE "$TEST_RE"; then
            TF_CWD=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('cwd', ''))
except Exception:
    pass
" 2>/dev/null)
            [ -z "$TF_CWD" ] && TF_CWD=$(pwd)

            TF_PROJECT=$(basename "$TF_CWD")
            COUNTER_DIR="$HOME/.claude/cache/test-failure"
            mkdir -p "$COUNTER_DIR"
            COUNTER_FILE="$COUNTER_DIR/${TF_PROJECT}.count"

            if [ "$TF_EXIT_CODE" = "0" ] || [ -z "$TF_EXIT_CODE" ]; then
                rm -f "$COUNTER_FILE"
            else
                COUNT=0
                [ -f "$COUNTER_FILE" ] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null)
                COUNT=$((COUNT + 1))
                echo "$COUNT" > "$COUNTER_FILE"

                if [ "$COUNT" -eq 3 ] && git -C "$TF_CWD" rev-parse --is-inside-work-tree &>/dev/null; then
                    CACHE_DIR="$HOME/.claude/cache/gemini"
                    mkdir -p "$CACHE_DIR"
                    TF_OUTPUT="$CACHE_DIR/${TF_PROJECT}-test-failure-analysis.md"

                    DIFF=$(git -C "$TF_CWD" diff HEAD 2>/dev/null | head -500)
                    RECENT_LOG=$(git -C "$TF_CWD" log --oneline -5 2>/dev/null)

                    echo "[Gemini 테스트 3회 실패 영향 분석 — ${TF_PROJECT}, 백그라운드]"
                    echo "[다음 실패 시 codex:rescue로 자동 위임 권장]"

                    (
                        PROMPT="프로젝트 ${TF_PROJECT} 테스트가 3회 연속 실패. 영향 범위와 가설을 분석.

최근 변경:
${DIFF}

최근 커밋:
${RECENT_LOG}

다음을 한국어로:
**가능성 높은 원인** (3개 가설, 각 한 줄):
**영향 받는 모듈** (변경된 파일이 의존하는 곳):
**Codex에 위임 시 우선 보여줄 파일**:
**자가 수정 시도 가치** (high/medium/low + 이유):

장식/인사 금지."

                        echo "$PROMPT" | "$GEM_CLI" -p "$(cat)" > "$TF_OUTPUT" 2>/dev/null
                    ) &
                fi
            fi
        fi
    fi
fi

exit 0
