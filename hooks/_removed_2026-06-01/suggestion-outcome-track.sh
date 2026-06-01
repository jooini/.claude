#!/bin/zsh
# PostToolUse(Agent): 추천 시점에 저장된 suggestion 과 실제 호출 비교
# - 같은 session 의 5분 안 pending suggestion 1개 매칭
# - current_agent 가 그대로면 "ignored", suggested_agent 면 "accepted"
# - 결과 → ~/.claude/cache/md-live/suggestion-outcomes.jsonl

: "${HOME:?}"

INPUT=$(cat)
SESSION=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$SESSION" ] && exit 0

# tool_input 안의 subagent_type 추출 (PostToolUse 페이로드 구조)
# stdin 으로 안전하게 전달 (heredoc + 변수 보간은 따옴표 깨질 위험)
ACTUAL_AGENT=$(printf '%s' "$INPUT" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
ti = d.get("tool_input", {}) or {}
print(ti.get("subagent_type", ""))
' 2>/dev/null)
[ -z "$ACTUAL_AGENT" ] && exit 0

SUGG_DIR="$HOME/.claude/cache/md-live/.suggestions"
[ -d "$SUGG_DIR" ] || exit 0

OUT="$HOME/.claude/cache/md-live/suggestion-outcomes.jsonl"
NOW=$(date +%s)

(
    /usr/bin/python3 - "$SUGG_DIR" "$SESSION" "$ACTUAL_AGENT" "$NOW" "$OUT" <<'PYEOF' 2>/dev/null
import json, os, sys, glob
sugg_dir, session, actual, now, out_path = sys.argv[1:6]
now = int(now)
WINDOW = 300  # 5분
matched = None

# 같은 세션의 pending suggestion 중 가장 최근 (5분 윈도우)
candidates = sorted(glob.glob(os.path.join(sugg_dir, f"{session}_*.json")), reverse=True)
for path in candidates:
    try:
        with open(path) as f:
            s = json.load(f)
    except Exception:
        continue
    if s.get("outcome") != "pending":
        continue
    ts = int(s.get("ts", 0))
    if now - ts > WINDOW:
        continue
    matched = (path, s)
    break

if not matched:
    sys.exit(0)

path, s = matched
suggested = s.get("suggested_agent", "")
current = s.get("current_agent", "")

if actual == suggested:
    outcome = "accepted"
elif actual == current:
    outcome = "ignored"
else:
    outcome = "other"  # 제3의 agent 호출

s["outcome"] = outcome
s["actual_agent"] = actual
s["resolved_at"] = now

# 결과 append
with open(out_path, "a") as f:
    f.write(json.dumps(s, ensure_ascii=False) + "\n")

# pending file 제거 (디스크 정리)
try:
    os.remove(path)
except Exception:
    pass

# 오래된 pending 도 정리 (>10분 = expired)
for p in candidates:
    try:
        with open(p) as f:
            old = json.load(f)
    except Exception:
        continue
    if old.get("outcome") == "pending" and now - int(old.get("ts", 0)) > 600:
        old["outcome"] = "expired"
        old["resolved_at"] = now
        with open(out_path, "a") as f:
            f.write(json.dumps(old, ensure_ascii=False) + "\n")
        try: os.remove(p)
        except Exception: pass
PYEOF
) &

exit 0
