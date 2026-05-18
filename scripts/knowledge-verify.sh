#!/bin/zsh
# knowledge-verify: 최근 N분간 어떤 knowledge md 가 Read 됐는지 조회.
# 사용:
#   knowledge-verify           # 최근 10분
#   knowledge-verify 60        # 최근 60분
#   knowledge-verify 60 backend  # backend 만
#
# 데이터 소스: ~/.claude/cache/md-live/{date}.jsonl  (md-read-trace.sh 가 기록)

: "${HOME:?}"
MIN="${1:-10}"
FILTER="${2:-}"
LOG_DIR="$HOME/.claude/cache/md-live"

/usr/bin/python3 - "$MIN" "$FILTER" "$LOG_DIR" <<'PY'
import json, sys, os, glob
from datetime import datetime, timezone, timedelta

minutes = int(sys.argv[1])
filt = sys.argv[2].lower()
log_dir = sys.argv[3]

cutoff = datetime.now(timezone.utc) - timedelta(minutes=minutes)
cutoff_date = (cutoff - timedelta(days=1)).strftime("%Y-%m-%d")

rows = []
for f in sorted(glob.glob(f"{log_dir}/*.jsonl")):
    name = os.path.basename(f).replace(".jsonl", "")
    if name < cutoff_date:
        continue
    with open(f) as fp:
        for ln in fp:
            try:
                d = json.loads(ln)
            except Exception:
                continue
            if d.get("category") != "knowledge":
                continue
            ts = d.get("ts_utc", "")
            try:
                t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            except Exception:
                continue
            if t < cutoff:
                continue
            file = d.get("file", "")
            if filt and filt not in file.lower():
                continue
            rows.append((t, d.get("session", ""), d.get("turn_id", "")[:8], file))

if not rows:
    print(f"최근 {minutes}분 knowledge Read 없음" + (f" (필터: {filt})" if filt else ""))
    sys.exit(0)

print(f"최근 {minutes}분 knowledge Read: {len(rows)}건")
print(f"{'TIME':20} {'SESSION':10} {'TURN':10} FILE")
for t, sess, turn, file in rows[-50:]:
    local = t.astimezone().strftime("%m-%d %H:%M:%S")
    short = file.replace(os.path.expanduser("~/.claude/agents/knowledge/"), "")
    print(f"{local:20} {sess:10} {turn:10} {short}")
PY
