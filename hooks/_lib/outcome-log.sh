#!/bin/zsh
# 공통 outcome 계측 라이브러리
#
# 사용법:
#   source ~/.claude/hooks/_lib/outcome-log.sh
#   outcome_log "<hook-name>" "<outcome>" "<detail>" ["<trigger_reason>"]
#
# outcome 분류:
#   pass      - 훅 진입했으나 차단/경고 조건 미해당 (정상 통과)
#   warn      - 사용자에게 경고만 출력 (실행은 허용)
#   block     - exit 2로 실행 차단
#   detect    - 패턴 감지만 (액션 없음, 로그 목적)
#   summarize - LLM 요약 결과 주입
#   trigger   - 컨텍스트 주입/모드 발동
#
# trigger_reason (4번째 인자, 옵션):
#   왜 이 outcome이 발생했는지 분류 라벨.
#   비교 분석용 — router_regret(warn 후 사용자 정정 비율), cost_per_success 측정에 사용.
#   예: "rm-rf-root", "heredoc-py", "main-force-push", "explicit-ultrathink", "exit-nonzero"
#
# 출력: ${HOOK_OUTCOME_DIR:-~/.claude/cache/hook-outcomes}/{date}.jsonl
# 스키마: {ts, hook, outcome, session, detail, trigger}
#
# 테스트 격리: HOOK_OUTCOME_DIR 환경변수로 출력 디렉토리 override 가능
#   예: HOOK_OUTCOME_DIR=/tmp/test-outcomes bash test.sh

outcome_log() {
    local hook="$1"
    local outcome="$2"
    local detail="${3:-}"
    local trigger="${4:-}"

    local dir="${HOOK_OUTCOME_DIR:-$HOME/.claude/cache/hook-outcomes}"
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 0

    local date_str
    date_str=$(date +%Y-%m-%d)
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local session="${CLAUDE_SESSION_ID:-${SESSION:-}}"
    [ -z "$session" ] && session="${HOOK_SESSION:-}"

    # sanitize: 제어문자 제거, 따옴표 이스케이프, 길이 제한
    detail=$(printf '%s' "$detail" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | sed 's/"/\\"/g' | cut -c1-200)
    trigger=$(printf '%s' "$trigger" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | sed 's/"/\\"/g' | cut -c1-100)

    printf '{"ts":"%s","hook":"%s","outcome":"%s","session":"%s","detail":"%s","trigger":"%s"}\n' \
        "$ts" "$hook" "$outcome" "$session" "$detail" "$trigger" \
        >> "$dir/${date_str}.jsonl" 2>/dev/null

    return 0
}
