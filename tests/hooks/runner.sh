#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="$ROOT_DIR/cases"
VERBOSE=0
FILTER=""

usage() {
    printf 'Usage: bash %s [--verbose] [--filter <pattern>]\n' "$0"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --verbose)
            VERBOSE=1
            shift
            ;;
        --filter)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 1
            fi
            FILTER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
done

pass_count=0
fail_count=0
seen_count=0

case_display_name() {
    local case_file="$1"
    local name

    name="$(sed -n 's/^# *name: *//p' "$case_file" | head -n 1)"
    if [ -n "$name" ]; then
        printf '%s\n' "$name"
    else
        basename "$case_file"
    fi
}

run_case() {
    local case_file="$1"
    local case_name="$2"
    local case_tmp
    local output
    local status

    case_tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-hook-test.XXXXXX")"
    output="$(
        (
            export TEST_ROOT="$ROOT_DIR"
            export TEST_TMPDIR="$case_tmp"
            export HOOK_OUTCOME_DIR="$case_tmp/outcomes"
            mkdir -p "$HOOK_OUTCOME_DIR"
            cd "$ROOT_DIR" || exit 1
            bash "$case_file"
        ) 2>&1
    )"
    status=$?

    if [ "$status" -eq 0 ]; then
        pass_count=$((pass_count + 1))
        printf 'PASS %s\n' "$case_name"
        if [ "$VERBOSE" -eq 1 ] && [ -n "$output" ]; then
            printf '%s\n' "$output"
        fi
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL %s\n' "$case_name"
        if [ -n "$output" ]; then
            printf '%s\n' "$output"
        fi
    fi

    rm -rf "$case_tmp"
}

for case_file in "$CASES_DIR"/*.test.sh; do
    [ -e "$case_file" ] || continue
    case_name="$(case_display_name "$case_file")"

    if [ -n "$FILTER" ] && ! printf '%s\n' "$case_name" | grep -q -- "$FILTER"; then
        continue
    fi

    seen_count=$((seen_count + 1))
    run_case "$case_file" "$case_name"
done

if [ "$seen_count" -eq 0 ]; then
    printf 'FAIL no test cases matched\n'
    printf 'RESULT PASS=0 FAIL=1\n'
    exit 1
fi

printf 'RESULT PASS=%s FAIL=%s\n' "$pass_count" "$fail_count"

if [ "$fail_count" -eq 0 ]; then
    exit 0
fi

exit 1
