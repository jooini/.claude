#!/bin/zsh
# PostToolUse(Agent): 방금 종료된 subagent 1개 분석 → quality.jsonl 1줄 append
# 추가: 100건 단위로 routing-rules.json 자동 재학습 (X2)
# 백그라운드 실행 — Claude turn 지연 없도록.

: "${HOME:?}"

INPUT=$(cat)
SESSION=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$SESSION" ] && exit 0

# 같은 메인 session 의 가장 최근 subagent jsonl (mtime)
SUB_DIR=$(find "$HOME/.claude/projects" -path "*${SESSION}/subagents" -type d 2>/dev/null | head -1)
[ -z "$SUB_DIR" ] && exit 0
LATEST=$(/bin/ls -t "$SUB_DIR"/agent-*.jsonl 2>/dev/null | head -1)
[ -z "$LATEST" ] && exit 0

# 너무 최근(<1초)이면 아직 flush 안 됐을 수도 — 분석은 백그라운드라 안전
QUALITY="$HOME/.claude/cache/md-live/agent-quality.jsonl"
RULES="$HOME/.claude/cache/md-live/agent-routing-rules.json"
LEARN_MARKER="$HOME/.claude/cache/md-live/.last-learn-count"
LOG="$HOME/.claude/cache/md-live/.incremental.log"

(
    /usr/bin/python3 "$HOME/.claude/scripts/agent-quality-analyze.py" --single "$LATEST" >> "$LOG" 2>&1

    # X2: 100건 단위 자동 룰 재학습
    COUNT=$(/usr/bin/wc -l < "$QUALITY" 2>/dev/null | tr -d ' ')
    LAST=0
    [ -f "$LEARN_MARKER" ] && LAST=$(/bin/cat "$LEARN_MARKER" 2>/dev/null | tr -d ' \n')
    [ -z "$LAST" ] && LAST=0
    DIFF=$((COUNT - LAST))
    if [ "$DIFF" -ge 100 ]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) re-learn count=$COUNT (last=$LAST diff=$DIFF)" >> "$LOG"
        /usr/bin/python3 "$HOME/.claude/scripts/agent-routing-learn.py" >> "$LOG" 2>&1
        echo "$COUNT" > "$LEARN_MARKER"
    fi
) &

exit 0
