#!/bin/zsh
# malformed-toolcall-guard.sh — UserPromptSubmit P0 sub-hook
# Inject a strong format reminder ONLY when the previous turn's tool call broke
# (malformed = missing function_calls opening token, leaked invoke/parameter as text).
# Evidence: session 89ada186 (2026-06-01) — 9 success / 5 fail coexist, single-shot
# token omission. Static CLAUDE.md rules alone did not prevent recurrence.
: "${HOME:?}"

# Drain stdin (router re-feeds it; we do not use it)
cat >/dev/null 2>&1 || true

TDIR="$HOME/.claude/projects/-Users-leonard--claude"
LATEST=$(ls -t "$TDIR"/*.jsonl 2>/dev/null | head -1)
[ -n "$LATEST" ] && [ -r "$LATEST" ] || exit 0

DETECT=$(tail -n 6 "$LATEST" 2>/dev/null | python3 "$HOME/.claude/hooks/lib/malformed-detect.py" 2>/dev/null)
[ "$DETECT" = "1" ] || exit 0

print -r -- "[MALFORMED TOOLCALL DETECTED on previous turn — format enforcement]"
print -r -- "Previous tool call broke (opening token missing). This call MUST:"
print -r -- "1. Start the tool-call block with the correct function_calls opening token as the very first output (no text before it)."
print -r -- "2. Use namespaced invoke tags and correct parameter format."
print -r -- "3. Call ONE tool only to stabilize format. If it breaks again, respond with TEXT only (no tool) to break the loop."
print -r -- "4. Avoid heredoc with nested quotes — prefer Write tool for file creation."
exit 0
