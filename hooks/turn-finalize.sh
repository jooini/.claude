#!/bin/zsh
# PostToolUse: turn-marker.sh 가 남긴 펜딩 발화를 turns.jsonl 로 finalize
#
# 핵심:
#   - PostToolUse 시점에는 이번 발화의 promptId 가 transcript 에 이미 flush 됨
#   - transcript 마지막 user.promptId == 이번 발화의 promptId
#   - 펜딩의 prompt_preview 와 promptId 를 묶어 turns.jsonl 에 1줄 작성
#
# 동시성:
#   PostToolUse 는 한 turn 당 N번 호출. finalized 플래그로 1회만 처리.
#   여러 PostToolUse 동시 호출 시 mv 원자성으로 race 방지.

: "${HOME:?}"

INPUT=$(cat)

TRANSCRIPT=""
SESSION=""
if command -v jq >/dev/null 2>&1; then
    TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | cut -c1-8)
fi
[ -z "$SESSION" ] && exit 0
[ -z "$TRANSCRIPT" ] && exit 0
[ -f "$TRANSCRIPT" ] || exit 0

PENDING_DIR="$HOME/.claude/cache/md-live/_pending"
PENDING_FILE="$PENDING_DIR/${SESSION}.jsonl"
[ -f "$PENDING_FILE" ] || exit 0

# 미finalize 펜딩이 있는지 빠른 체크 (없으면 즉시 exit)
if ! grep -Fq '"finalized":false' "$PENDING_FILE" 2>/dev/null; then
    exit 0
fi

# transcript 마지막 user.promptId 추출
TURN_ID=$(/usr/bin/python3 - "$TRANSCRIPT" <<'PYEOF' 2>/dev/null
import json, sys
path = sys.argv[1]
last_pid = ""
try:
    with open(path) as f:
        for ln in f:
            try:
                d = json.loads(ln)
            except:
                continue
            if d.get("type") == "user" and "toolUseResult" not in d:
                msg = d.get("message", {})
                if isinstance(msg, dict) and isinstance(msg.get("content"), str):
                    pid = d.get("promptId")
                    if pid:
                        last_pid = pid
except Exception:
    pass
print(last_pid)
PYEOF
)

[ -z "$TURN_ID" ] && exit 0

LOG_DIR="$HOME/.claude/cache/md-live"
TURNS_FILE="$LOG_DIR/turns.jsonl"

# 이미 같은 turn_id 가 turns.jsonl 에 있으면 펜딩만 finalize 처리하고 끝
if [ -f "$TURNS_FILE" ] && grep -Fq "\"turn_id\":\"$TURN_ID\"" "$TURNS_FILE"; then
    # 펜딩에서 가장 오래된 미finalize 라인 1개를 finalized=true 로 마킹
    /usr/bin/python3 - "$PENDING_FILE" <<'PYEOF' 2>/dev/null
import json, sys, os
path = sys.argv[1]
lines = []
marked = False
try:
    with open(path) as f:
        for ln in f:
            try:
                d = json.loads(ln)
            except:
                lines.append(ln.rstrip("\n"))
                continue
            if not marked and not d.get("finalized", False):
                d["finalized"] = True
                marked = True
            lines.append(json.dumps(d, ensure_ascii=False))
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines))
        if lines: f.write("\n")
    os.replace(tmp, path)
except Exception:
    pass
PYEOF
    exit 0
fi

# 펜딩에서 가장 오래된 미finalize 발화 1개 꺼내기
/usr/bin/python3 - "$PENDING_FILE" "$TURN_ID" "$TURNS_FILE" <<'PYEOF' 2>/dev/null
import json, sys, os
pending_path, turn_id, turns_path = sys.argv[1], sys.argv[2], sys.argv[3]

lines = []
target = None
target_idx = -1
try:
    with open(pending_path) as f:
        for i, ln in enumerate(f):
            try:
                d = json.loads(ln)
            except:
                lines.append(ln.rstrip("\n"))
                continue
            if target is None and not d.get("finalized", False):
                target = d
                target_idx = len(lines)
                d["finalized"] = True
            lines.append(json.dumps(d, ensure_ascii=False))
except Exception:
    sys.exit(0)

if target is None:
    sys.exit(0)

# turns.jsonl 에 정식 라인 작성
turn_line = {
    "turn_id": turn_id,
    "session": target.get("session", ""),
    "ts_utc": target.get("ts_utc", ""),
    "prompt_preview": target.get("prompt_preview", ""),
}
try:
    with open(turns_path, "a") as f:
        f.write(json.dumps(turn_line, ensure_ascii=False) + "\n")
except Exception:
    sys.exit(0)

# 펜딩 파일 원자 교체
tmp = pending_path + ".tmp"
try:
    with open(tmp, "w") as f:
        f.write("\n".join(lines))
        if lines: f.write("\n")
    os.replace(tmp, pending_path)
except Exception:
    pass

# turns.jsonl 라인수 cap
try:
    with open(turns_path) as f:
        all_lines = f.readlines()
    if len(all_lines) > 10000:
        with open(turns_path, "w") as f:
            f.writelines(all_lines[-10000:])
except Exception:
    pass
PYEOF

exit 0
