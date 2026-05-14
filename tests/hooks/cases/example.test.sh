#!/usr/bin/env bash
set -u

# name: dangerous-command-detect example

source "${TEST_ROOT:-$HOME/.claude/tests/hooks}/lib/assert.sh"

hook="$HOME/.claude/hooks/dangerous-command-detect.sh"
stdin_json='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/claude-hook-test-target"}}'

stdout="$(printf '%s\n' "$stdin_json" | "$hook" 2>&1)"
actual=$?

assert_exit_code 0 "$actual" || exit 1
assert_outcome_logged "dangerous-command-detect" "warn" || exit 1
