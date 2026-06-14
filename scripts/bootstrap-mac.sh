#!/usr/bin/env bash
# Bootstrap the neutral ~/.agents control plane from the ~/.claude config checkout.
#
# Fresh Mac:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jooini/.claude/main/scripts/bootstrap-mac.sh)"
#
# Existing checkout:
#   ~/.claude/scripts/bootstrap-mac.sh
#
# Environment overrides:
#   CLAUDE_REPO_URL=git@github-jooini:jooini/.claude.git
#   CLAUDE_BRANCH=main
#   CLAUDE_DIR=~/.claude

set -euo pipefail

REPO_URL="${CLAUDE_REPO_URL:-git@github-jooini:jooini/.claude.git}"
BRANCH="${CLAUDE_BRANCH:-main}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DRY_RUN=false
NO_PULL=false
NO_LLM_CONFIG_RESTORE=false
NO_DOCTOR=false

usage() {
    cat <<'EOF'
Usage:
  bootstrap-mac.sh [options]

Options:
  --dry-run                 Print actions without changing files.
  --no-pull                 Do not pull an existing ~/.claude checkout.
  --no-llm-config-restore   Skip sync-llm-configs.sh restore.
  --no-doctor               Skip llm-router.sh doctor.
  -h, --help                Show this help.

Environment:
  CLAUDE_REPO_URL           Git remote for ~/.claude.
  CLAUDE_BRANCH             Git branch to clone/pull. Default: main.
  CLAUDE_DIR                Checkout path. Default: ~/.claude.
EOF
}

log() {
    printf '[bootstrap-mac] %s\n' "$*"
}

warn() {
    printf '[bootstrap-mac] %s\n' "$*" >&2
}

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

require_command() {
    local name="$1"
    if ! command -v "$name" >/dev/null 2>&1; then
        warn "missing required command: $name"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                ;;
            --no-pull)
                NO_PULL=true
                ;;
            --no-llm-config-restore)
                NO_LLM_CONFIG_RESTORE=true
                ;;
            --no-doctor)
                NO_DOCTOR=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                warn "unknown argument: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

ensure_claude_checkout() {
    if [[ -d "$CLAUDE_DIR/.git" ]]; then
        log "using existing checkout: $CLAUDE_DIR"
        if [[ "$NO_PULL" == "true" ]]; then
            log "skip pull (--no-pull)"
            return 0
        fi
        run git -C "$CLAUDE_DIR" fetch origin "$BRANCH"
        run git -C "$CLAUDE_DIR" pull --ff-only origin "$BRANCH"
        return 0
    fi

    if [[ -e "$CLAUDE_DIR" ]]; then
        warn "$CLAUDE_DIR exists but is not a git checkout; move it aside or set CLAUDE_DIR."
        exit 1
    fi

    log "cloning $REPO_URL -> $CLAUDE_DIR"
    run git clone --branch "$BRANCH" "$REPO_URL" "$CLAUDE_DIR"
}

restore_llm_configs() {
    local script="$CLAUDE_DIR/scripts/sync-llm-configs.sh"
    if [[ "$NO_LLM_CONFIG_RESTORE" == "true" ]]; then
        log "skip llm config restore (--no-llm-config-restore)"
        return 0
    fi
    if [[ ! -x "$script" ]]; then
        warn "skip llm config restore: missing executable $script"
        return 0
    fi
    log "restoring non-secret LLM configs"
    run "$script" restore
}

sync_external_outputs() {
    local script="$CLAUDE_DIR/scripts/sync-external.sh"
    if [[ ! -x "$script" ]]; then
        warn "missing executable $script"
        exit 1
    fi
    log "syncing Codex/Gemini/agents generated outputs"
    run "$script"
}

run_doctor() {
    local router="$HOME/.agents/scripts/llm-router.sh"
    if [[ "$NO_DOCTOR" == "true" ]]; then
        log "skip llm router doctor (--no-doctor)"
        return 0
    fi
    if [[ ! -x "$router" ]]; then
        warn "skip doctor: missing executable $router"
        return 0
    fi
    log "checking LLM router health"
    run "$router" doctor
}

print_next_steps() {
    cat <<EOF

=== bootstrap complete ===
Checkout: $CLAUDE_DIR

Useful checks:
  $CLAUDE_DIR/scripts/sync-external.sh status
  $HOME/.agents/scripts/llm-router.sh route-health
  git -C $CLAUDE_DIR status --short
EOF
}

main() {
    parse_args "$@"
    require_command git
    ensure_claude_checkout
    restore_llm_configs
    sync_external_outputs
    run_doctor
    print_next_steps
}

main "$@"
