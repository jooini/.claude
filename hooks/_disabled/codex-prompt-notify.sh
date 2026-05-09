#!/bin/zsh
# Codex UserPromptSubmit: 프롬프트 실행 알림
osascript -e 'display notification "Codex 작업 실행 중" with title "Codex CLI"' 2>/dev/null &
exit 0
