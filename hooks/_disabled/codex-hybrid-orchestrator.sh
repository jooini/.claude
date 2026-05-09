#!/bin/zsh
set -euo pipefail

: "${HOME:?}"

INPUT="$(cat || true)"
WORKSPACE_DIR="$HOME/Workspace"
CLAUDE_CACHE_DIR="$HOME/.claude/cache/claude"
GEMINI_CACHE_DIR="$HOME/.claude/cache/gemini"
HYBRID_CACHE_DIR="$HOME/.claude/cache/hybrid"
STATE_FILE="$HYBRID_CACHE_DIR/last-userprompt-state.txt"
LAST_PAYLOAD_FILE="$HYBRID_CACHE_DIR/last-codex-userprompt.json"

mkdir -p "$CLAUDE_CACHE_DIR" "$GEMINI_CACHE_DIR" "$HYBRID_CACHE_DIR"

if [[ -n "$INPUT" ]]; then
    printf '%s\n' "$INPUT" > "$LAST_PAYLOAD_FILE"
fi

extract_prompt_from_input() {
    if [[ -z "$INPUT" ]]; then
        return 0
    fi

    printf '%s' "$INPUT" | jq -r '
        [
            .prompt?,
            .user_prompt?,
            .text?,
            .message?,
            .input?.prompt?,
            .input?.text?,
            .payload?.prompt?,
            .payload?.text?,
            (.content? | if type == "string" then . else empty end),
            (.messages?[-1].content? | if type == "string" then . else empty end),
            (.messages?[-1].content?[]?.text? // empty)
        ]
        | map(select(type == "string" and length > 0))
        | .[0] // empty
    ' 2>/dev/null
}

extract_cwd_from_input() {
    if [[ -z "$INPUT" ]]; then
        return 0
    fi

    printf '%s' "$INPUT" | jq -r '
        [
            .cwd?,
            .working_directory?,
            .workspace_path?,
            .project_path?,
            .payload?.cwd?,
            .payload?.working_directory?,
            .input?.cwd?
        ]
        | map(select(type == "string" and length > 0))
        | .[0] // empty
    ' 2>/dev/null
}

extract_latest_prompt_history() {
    jq -r '.["electron-persisted-atom-state"]["prompt-history"][-1] // empty' \
        "$HOME/.codex/.codex-global-state.json" 2>/dev/null
}

resolve_project_root_from_cwd() {
    local current_dir="$1"
    local dir="$current_dir"

    [[ -n "$dir" ]] || return 0
    [[ -d "$dir" ]] || dir="${dir:h}"
    [[ -d "$dir" ]] || return 0

    while [[ "$dir" == "$WORKSPACE_DIR"/* ]]; do
        if [[ -f "$dir/CLAUDE.md" || -f "$dir/.claude/CLAUDE.md" || -f "$dir/AGENTS.md" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi

        case "$dir" in
            */Workspace/*)
                dir="${dir:h}"
                ;;
            *)
                break
                ;;
        esac
    done
}

resolve_project_root_from_prompt() {
    local prompt="$1"
    local candidate
    local candidate_name
    local best_match=""

    [[ -n "$prompt" ]] || return 0

    while IFS= read -r candidate; do
        candidate_name="$(basename "$candidate")"
        if printf '%s' "$prompt" | grep -Fqi "$candidate_name"; then
            best_match="$candidate"
            break
        fi
    done < <(find "$WORKSPACE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

    [[ -n "$best_match" ]] && printf '%s\n' "$best_match"
}

is_fresh_file() {
    local file_path="$1"
    local ttl_seconds="$2"
    local modified_at
    local now

    [[ -f "$file_path" ]] || return 1

    modified_at="$(stat -f %m "$file_path" 2>/dev/null || echo 0)"
    now="$(date +%s)"

    [[ $(( now - modified_at )) -lt "$ttl_seconds" ]]
}

escape_prompt_for_log() {
    printf '%s' "$1" | tr '\n' ' ' | cut -c1-200
}

should_trigger_once() {
    local project_root="$1"
    local prompt="$2"
    local current_hash
    local previous_hash=""
    local previous_timestamp=0
    local now

    current_hash="$(printf '%s\n%s' "$project_root" "$prompt" | shasum -a 1 | awk '{print $1}')"
    now="$(date +%s)"

    if [[ -f "$STATE_FILE" ]]; then
        previous_hash="$(awk 'NR==1 {print $1}' "$STATE_FILE" 2>/dev/null || true)"
        previous_timestamp="$(awk 'NR==1 {print $2}' "$STATE_FILE" 2>/dev/null || echo 0)"
    fi

    if [[ "$current_hash" == "$previous_hash" && $(( now - previous_timestamp )) -lt 90 ]]; then
        return 1
    fi

    printf '%s %s\n' "$current_hash" "$now" > "$STATE_FILE"
    return 0
}

run_background_command() {
    local output_file="$1"
    local command_text="$2"
    local error_file="$3"

    if [[ "${HYBRID_DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] %s\n' "$command_text"
        return 0
    fi

    (
        if eval "$command_text" > "$output_file" 2> "$error_file"; then
            [[ -s "$output_file" ]] || rm -f "$output_file"
        else
            rm -f "$output_file"
        fi
    ) &
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

claude_is_authenticated() {
    command_exists claude || return 1
    claude auth status 2>/dev/null | jq -e '.loggedIn == true' >/dev/null 2>&1
}

gemini_seems_authenticated() {
    local accounts_file="$HOME/.gemini/google_accounts.json"
    local creds_file="$HOME/.gemini/oauth_creds.json"

    command_exists gemini || return 1
    [[ -s "$creds_file" ]] || return 1
    [[ -s "$accounts_file" ]] || return 1
    jq -e '.active | strings | length > 0' "$accounts_file" >/dev/null 2>&1
}

PROMPT_TEXT="$(extract_prompt_from_input)"
if [[ -z "$PROMPT_TEXT" ]]; then
    PROMPT_TEXT="$(extract_latest_prompt_history)"
fi

CURRENT_CWD="$(extract_cwd_from_input)"
if [[ -z "$CURRENT_CWD" ]]; then
    CURRENT_CWD="$(pwd)"
fi

PROJECT_ROOT="$(resolve_project_root_from_cwd "$CURRENT_CWD")"
if [[ -z "$PROJECT_ROOT" ]]; then
    PROJECT_ROOT="$(resolve_project_root_from_prompt "$PROMPT_TEXT")"
fi

[[ -n "$PROJECT_ROOT" ]] || exit 0

PROJECT_NAME="$(basename "$PROJECT_ROOT")"
PROMPT_TEXT="${PROMPT_TEXT:-}"

should_trigger_once "$PROJECT_ROOT" "$PROMPT_TEXT" || exit 0

LOWERED_PROMPT="$(printf '%s' "$PROMPT_TEXT" | tr '[:upper:]' '[:lower:]')"
GEMINI_SCAN_FILE="$GEMINI_CACHE_DIR/${PROJECT_NAME}-scan.md"
GEMINI_REVIEW_FILE="$GEMINI_CACHE_DIR/${PROJECT_NAME}-review-prescan.md"
CLAUDE_BRIEF_FILE="$CLAUDE_CACHE_DIR/${PROJECT_NAME}-codex-brief.md"

SCAN_REGEX='(@dev|@team|backlog|active|구조|아키텍처|architecture|설계|의존성|영향|요약|overview|scan|스캔|분석|debug|디버그|오류|버그)'
REVIEW_REGEX='(리뷰|리뷰어|review|reviewer|code-reviewer|diff|pr|검토|회귀)'
CLAUDE_REGEX='(@dev|@team|dev-lead|계획|plan|설계|architecture|아키텍처|분해|라우팅|backlog|active|영향 범위|오케스트)'
FORCE_GEMINI_REGEX='(gemini 같이|gemini도|gemini 호출|둘다|둘 다|하이브리드|hybrid)'
FORCE_CLAUDE_REGEX='(claude 같이|claude도|claude 호출|둘다|둘 다|하이브리드|hybrid)'

RUN_GEMINI_SCAN=0
RUN_GEMINI_REVIEW=0
RUN_CLAUDE_BRIEF=0

if printf '%s' "$LOWERED_PROMPT" | grep -qiE "$SCAN_REGEX|$FORCE_GEMINI_REGEX"; then
    RUN_GEMINI_SCAN=1
fi

if printf '%s' "$LOWERED_PROMPT" | grep -qiE "$REVIEW_REGEX|$FORCE_GEMINI_REGEX"; then
    RUN_GEMINI_REVIEW=1
fi

if printf '%s' "$LOWERED_PROMPT" | grep -qiE "$CLAUDE_REGEX|$FORCE_CLAUDE_REGEX"; then
    RUN_CLAUDE_BRIEF=1
fi

if ! gemini_seems_authenticated; then
    RUN_GEMINI_SCAN=0
    RUN_GEMINI_REVIEW=0
fi

if ! claude_is_authenticated; then
    RUN_CLAUDE_BRIEF=0
fi

if [[ "$RUN_GEMINI_SCAN" -eq 1 ]] && ! is_fresh_file "$GEMINI_SCAN_FILE" 1800; then
    GEMINI_SCAN_PROMPT="$(cat <<EOF
현재 Codex가 작업할 프로젝트의 빠른 컨텍스트를 만들어라.

프로젝트: $PROJECT_NAME
경로: $PROJECT_ROOT
사용자 요청:
$PROMPT_TEXT

아래만 한글로 간결하게 정리:
1. 기술 스택
2. 주요 진입점
3. 먼저 볼 파일 5개 이내
4. 영향 범위 주의점
EOF
)"

    run_background_command \
        "$GEMINI_SCAN_FILE" \
        "cd '$PROJECT_ROOT' && timeout 90 gemini -p $(printf '%q' "$GEMINI_SCAN_PROMPT")" \
        "$HYBRID_CACHE_DIR/${PROJECT_NAME}-gemini-scan.log"
fi

if [[ "$RUN_GEMINI_REVIEW" -eq 1 ]] && ! is_fresh_file "$GEMINI_REVIEW_FILE" 600; then
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        DIFF_TEXT="$(git -C "$PROJECT_ROOT" diff HEAD 2>/dev/null)"
        if [[ -z "$DIFF_TEXT" ]]; then
            DIFF_TEXT="$(git -C "$PROJECT_ROOT" diff HEAD~1 2>/dev/null)"
        fi

        if [[ -n "$DIFF_TEXT" ]]; then
            DIFF_TEXT="$(printf '%s' "$DIFF_TEXT" | head -500)"
            GEMINI_REVIEW_PROMPT="$(cat <<EOF
Codex가 참고할 사전 리뷰 메모를 만든다.

프로젝트: $PROJECT_NAME
사용자 요청:
$PROMPT_TEXT

변경사항:
$DIFF_TEXT

아래만 한글로 정리:
1. 로직 오류 가능성
2. 회귀 위험
3. 누락된 테스트
4. 먼저 확인할 파일
EOF
)"

            run_background_command \
                "$GEMINI_REVIEW_FILE" \
                "cd '$PROJECT_ROOT' && timeout 90 gemini -p $(printf '%q' "$GEMINI_REVIEW_PROMPT")" \
                "$HYBRID_CACHE_DIR/${PROJECT_NAME}-gemini-review.log"
        fi
    fi
fi

if [[ "$RUN_CLAUDE_BRIEF" -eq 1 ]] && ! is_fresh_file "$CLAUDE_BRIEF_FILE" 900; then
    PROJECT_RULES_SNIPPET=""
    if [[ -f "$PROJECT_ROOT/AGENTS.md" ]]; then
        PROJECT_RULES_SNIPPET="$(sed -n '1,80p' "$PROJECT_ROOT/AGENTS.md")"
    elif [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
        PROJECT_RULES_SNIPPET="$(sed -n '1,80p' "$PROJECT_ROOT/CLAUDE.md")"
    elif [[ -f "$PROJECT_ROOT/.claude/CLAUDE.md" ]]; then
        PROJECT_RULES_SNIPPET="$(sed -n '1,80p' "$PROJECT_ROOT/.claude/CLAUDE.md")"
    fi

    GEMINI_SCAN_SNIPPET=""
    if [[ -f "$GEMINI_SCAN_FILE" ]]; then
        GEMINI_SCAN_SNIPPET="$(sed -n '1,80p' "$GEMINI_SCAN_FILE")"
    fi

    CLAUDE_BRIEF_PROMPT="$(cat <<EOF
너는 Codex를 보조하는 백그라운드 오케스트레이터다.
사용자 요청을 대신 수행하지 말고, Codex가 바로 참고할 실행 메모만 만든다.

프로젝트: $PROJECT_NAME
경로: $PROJECT_ROOT

사용자 요청:
$PROMPT_TEXT

프로젝트 규칙 요약:
$PROJECT_RULES_SNIPPET

Gemini 요약:
$GEMINI_SCAN_SNIPPET

출력 형식:
- 추천 역할/에이전트
- 병렬 가능 작업
- 먼저 읽을 파일
- 위험 포인트

한글, 12줄 이내, 간결하게.
EOF
)"

    run_background_command \
        "$CLAUDE_BRIEF_FILE" \
        "cd '$PROJECT_ROOT' && timeout 120 claude -p --tools '' --model sonnet $(printf '%q' "$CLAUDE_BRIEF_PROMPT")" \
        "$HYBRID_CACHE_DIR/${PROJECT_NAME}-claude-brief.log"
fi

if [[ "${HYBRID_DRY_RUN:-0}" == "1" ]]; then
    printf '[hybrid] project=%s prompt=%s\n' "$PROJECT_NAME" "$(escape_prompt_for_log "$PROMPT_TEXT")"
    printf '[hybrid] gemini_scan=%s gemini_review=%s claude_brief=%s\n' \
        "$RUN_GEMINI_SCAN" "$RUN_GEMINI_REVIEW" "$RUN_CLAUDE_BRIEF"
fi

exit 0
