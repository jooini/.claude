#!/bin/bash
# git post-commit / Bash PostToolUse 양쪽에서 호출 가능.
# 입력: stdin JSON 또는 환경변수 GIT_REPO/GIT_BRANCH/GIT_SHA/GIT_MESSAGE.
# 동작: /api/ingest/git-event 로 forward. 실패 무시.
set -u

BASE="${TASKHUB_BASE:-http://127.0.0.1:8001}"

# --- 1) Bash PostToolUse 매처에서 호출된 경우: stdin JSON 파싱 ---
INPUT=$(cat 2>/dev/null || true)

REPO="${GIT_REPO:-}"
BRANCH="${GIT_BRANCH:-}"
SHA="${GIT_SHA:-}"
MESSAGE="${GIT_MESSAGE:-}"
EVENT="${GIT_EVENT:-commit}"

if [ -n "$INPUT" ] && [ -z "$SHA" ]; then
    # bash 변수로 한번 받아서 python 에 -c 로 전달 — heredoc 내부 stdin 충돌 회피.
    IS_GIT_COMMIT=$(/usr/bin/python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    print("0"); sys.exit(0)
cmd = (d.get("tool_input") or d.get("input") or {}).get("command", "")
print("1" if cmd and "git commit" in cmd else "0")
' "$INPUT" 2>/dev/null)
    if [ "$IS_GIT_COMMIT" = "1" ]; then
        REPO=$(/usr/bin/git rev-parse --show-toplevel 2>/dev/null || true)
        BRANCH=$(/usr/bin/git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        SHA=$(/usr/bin/git rev-parse HEAD 2>/dev/null || true)
        MESSAGE=$(/usr/bin/git log -1 --pretty=%B 2>/dev/null || true)
    fi
fi

[ -z "$SHA" ] && exit 0

PAYLOAD=$(/usr/bin/python3 -c '
import json, sys
print(json.dumps({
    "repo": sys.argv[1],
    "event": sys.argv[2],
    "branch": sys.argv[3] or None,
    "sha": sys.argv[4],
    "message": sys.argv[5],
    "files": [],
}))
' "$REPO" "$EVENT" "$BRANCH" "$SHA" "$MESSAGE" 2>/dev/null) || exit 0

RESP=$(/usr/bin/curl -sS --max-time 3 \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$BASE/api/ingest/git-event" 2>/dev/null) || exit 0

# 매칭/완료된 경우만 stdout 1줄 출력
echo "$RESP" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
a = d.get("action", "")
tid = d.get("task_id", "")
if a == "completed":
    print(f"✅ git → task {tid[:8]} 자동 완료")
elif a == "suggested":
    print(f"💡 git → task {tid[:8]} 완료 제안 (사용자 수동 lock)")
elif a == "linked":
    print(f"🔗 git → task {tid[:8]} 링크")
' 2>/dev/null || true
exit 0
