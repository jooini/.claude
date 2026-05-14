#!/usr/bin/env bash

assert_exit_code() {
    local expected="$1"
    local actual="$2"

    if [ "$expected" = "$actual" ]; then
        return 0
    fi

    printf 'ASSERT FAIL: expected exit code %s, got %s\n' "$expected" "$actual" >&2
    return 1
}

assert_stdout_contains() {
    local stdout="$1"
    local substring="$2"

    case "$stdout" in
        *"$substring"*)
            return 0
            ;;
    esac

    printf 'ASSERT FAIL: stdout does not contain: %s\n' "$substring" >&2
    return 1
}

assert_outcome_logged() {
    local hook_name="$1"
    local outcome="$2"
    local dir="${HOOK_OUTCOME_DIR:-$HOME/.claude/cache/hook-outcomes}"
    local file

    if [ ! -d "$dir" ]; then
        printf 'ASSERT FAIL: outcome dir does not exist: %s\n' "$dir" >&2
        return 1
    fi

    for file in "$dir"/*.jsonl; do
        [ -e "$file" ] || continue
        if grep -F "\"hook\":\"$hook_name\"" "$file" | grep -F "\"outcome\":\"$outcome\"" >/dev/null; then
            return 0
        fi
    done

    printf 'ASSERT FAIL: outcome not logged: hook=%s outcome=%s dir=%s\n' "$hook_name" "$outcome" "$dir" >&2
    return 1
}
