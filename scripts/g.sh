#!/bin/bash
# Gemma 원샷 질문 — 터미널 어디서든 `g "질문"`
# 파이프 입력도 받음: `cat error.log | g "이 에러 원인"`

OLLAMA="${OLLAMA_HOST_LAN:-leonard.local:11434}"
MODEL="${GEMMA_MODEL:-gemma4:e4b}"

# stdin 파이프 입력 감지
STDIN_DATA=""
if [ ! -t 0 ]; then
    STDIN_DATA=$(cat)
fi

QUESTION="$*"

if [ -z "$QUESTION" ] && [ -z "$STDIN_DATA" ]; then
    echo "사용법: g \"질문\"  또는  cat file | g \"요약해줘\""
    exit 1
fi

# 프롬프트 조립
if [ -n "$STDIN_DATA" ] && [ -n "$QUESTION" ]; then
    PROMPT="$QUESTION

---
$STDIN_DATA"
elif [ -n "$STDIN_DATA" ]; then
    PROMPT="다음 내용 요약/분석:

$STDIN_DATA"
else
    PROMPT="$QUESTION"
fi

# 로거 경유 (기록 남김)
~/.claude/scripts/gemma-logger.sh "g-cli" "$MODEL" "$PROMPT" 1200 0.3
