#!/bin/zsh
# UserPromptSubmit: 발화 펜딩 캐시만 기록 (turn_id 미정 — transcript 에 아직 promptId 가 flush 되지 않음)
#
# 동작:
#   1) stdin 의 .prompt / .session_id 를 펜딩 파일에 저장
#   2) turn-finalize.sh (PostToolUse 첫 호출) 가 transcript 에서 promptId 를 끄집어 와
#      turns.jsonl 에 정식 라인 1줄 작성
#
# 왜 펜딩으로 분리하나:
#   UserPromptSubmit 시점에는 transcript JSONL 마지막 user 이벤트가 *직전* 발화임 (실측).
#   여기서 promptId 를 잡으면 turn_id 는 직전 promptId, prompt_preview 는 이번 본문 → 한 칸 어긋남.
#   PostToolUse 시점에는 이번 발화가 이미 transcript 에 flush 된 상태라 정합 매칭 가능.

: "${HOME:?}"

INPUT=$(cat)

TRANSCRIPT=""
SESSION=""
PROMPT=""

if command -v jq >/dev/null 2>&1; then
    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | cut -c1-8)
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
fi

[ -z "$SESSION" ] && exit 0

PENDING_DIR="$HOME/.claude/cache/md-live/_pending"
mkdir -p "$PENDING_DIR"

TS_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 펜딩 파일 — 세션별 1개. 한 발화당 1줄(가장 최근 발화 = 마지막 줄).
PENDING_FILE="$PENDING_DIR/${SESSION}.jsonl"

# 본문 escape
PROMPT_PREVIEW=$(printf '%s' "$PROMPT" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g')

# transcript path 도 같이 저장 — finalize 가 다시 jq 안 돌려도 되도록
TRANSCRIPT_ESC=$(printf '%s' "$TRANSCRIPT" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{"session":"%s","ts_utc":"%s","prompt_preview":"%s","transcript":"%s","finalized":false}\n' \
    "$SESSION" "$TS_UTC" "$PROMPT_PREVIEW" "$TRANSCRIPT_ESC" >> "$PENDING_FILE"

exit 0
