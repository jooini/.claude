#!/bin/zsh
# Provider-neutral LLM router wrapper.
exec /usr/bin/python3 "$HOME/.claude/scripts/llm-router.py" "$@"
