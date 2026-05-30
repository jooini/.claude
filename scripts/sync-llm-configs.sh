#!/usr/bin/env bash
# LLM CLI 순수 설정(비시크릿) 백업/복원
#
# 목적:
#   ~/.codex, ~/.gemini 의 "손으로 만든 설정"(instructions/rules/settings 등) 중
#   sync-external.sh 가 생성하지 않는 것 + 시크릿이 아닌 것만 골라
#   ~/.claude/llm-configs/ 로 백업(git 추적)하거나 거기서 원본으로 복원한다.
#
# 절대 다루지 않는 것 (시크릿/런타임 — 화이트리스트 방식이라 자동 제외):
#   auth.json, oauth_creds.json, google_accounts.json, config.toml,
#   *-state.json, history.jsonl, *.sqlite*, sessions/, cache/, tmp/
#   sync-external.sh 생성물(AGENTS.md, GEMINI.md, hooks.json, workflows/, agents/, skills 심링크)
#
# 사용법:
#   sync-llm-configs.sh backup    # 원본 → llm-configs/ (기본값)
#   sync-llm-configs.sh restore   # llm-configs/ → 원본 (새 머신 셋업)
#   sync-llm-configs.sh status    # drift 확인 (변경된 파일 표시)
#   --dry-run 으로 미리보기

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
STORE="${CLAUDE_DIR}/llm-configs"
DRY_RUN=false

# === 백업 화이트리스트 (원본경로  →  저장경로) ===
# 시크릿이 아니고 sync-external 생성물이 아닌 순수 설정만 명시 등록.
# 새 항목 추가 시 반드시 시크릿 여부를 먼저 확인할 것.
MAPPING=(
    "${HOME}/.codex/instructions.md|codex/instructions.md"
    "${HOME}/.codex/rules/default.rules|codex/rules/default.rules"
    "${HOME}/.gemini/settings.json|gemini/settings.json"
    "${HOME}/.gemini/scripts/sync-project-rules.sh|gemini/scripts/sync-project-rules.sh"
)

log()  { printf '  %s\n' "$1"; }
warn() { printf '  ⚠️  %s\n' "$1" >&2; }

copy_file() {
    local src="$1" dst="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '  [dry-run] cp %s → %s\n' "$src" "$dst"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst"
}

cmd_backup() {
    log "[백업] 원본 → llm-configs/"
    local n=0
    for pair in "${MAPPING[@]}"; do
        local origin="${pair%%|*}"
        local stored="${STORE}/${pair##*|}"
        if [[ -f "$origin" ]]; then
            copy_file "$origin" "$stored"
            log "✓ ${pair##*|}"
            n=$((n + 1))
        else
            warn "원본 없음(건너뜀): ${origin/#$HOME/~}"
        fi
    done
    log "백업 ${n}개 완료. git add llm-configs/ 후 커밋하면 버전관리됨."
}

cmd_restore() {
    log "[복원] llm-configs/ → 원본 (기존 파일은 .bak 백업)"
    local n=0
    for pair in "${MAPPING[@]}"; do
        local origin="${pair%%|*}"
        local stored="${STORE}/${pair##*|}"
        if [[ -f "$stored" ]]; then
            if [[ -f "$origin" && "$DRY_RUN" != "true" ]]; then
                cp -p "$origin" "${origin}.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
            fi
            copy_file "$stored" "$origin"
            log "✓ ${origin/#$HOME/~}"
            n=$((n + 1))
        else
            warn "저장본 없음(건너뜀): ${pair##*|}"
        fi
    done
    log "복원 ${n}개 완료."
}

cmd_status() {
    log "[상태] 원본 vs 저장본 drift"
    for pair in "${MAPPING[@]}"; do
        local origin="${pair%%|*}"
        local stored="${STORE}/${pair##*|}"
        local label="${pair##*|}"
        if [[ ! -f "$origin" ]]; then
            log "✗ ${label}: 원본 없음"
        elif [[ ! -f "$stored" ]]; then
            log "＋ ${label}: 저장본 없음 (백업 필요)"
        elif cmp -s "$origin" "$stored"; then
            log "= ${label}: 동일"
        else
            log "≠ ${label}: 변경됨 (백업 필요)"
        fi
    done
}

ACTION="backup"
for arg in "$@"; do
    case "$arg" in
        backup|restore|status) ACTION="$arg" ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) warn "알 수 없는 인자: $arg" ;;
    esac
done

case "$ACTION" in
    backup)  cmd_backup ;;
    restore) cmd_restore ;;
    status)  cmd_status ;;
esac
