#!/usr/bin/env bash
# claude-mem 자동 컨텍스트 주입 비활성화 (업데이트 후 재적용용)
# 사용: bash ~/.claude/scripts/claude-mem-disable-injection.sh

set -euo pipefail

HOOKS_DIR="$HOME/.claude/plugins/cache/thedotmack/claude-mem"
LATEST=$(/bin/ls -1 "$HOOKS_DIR" 2>/dev/null | /usr/bin/sort -V | /usr/bin/tail -1)

if [ -z "$LATEST" ]; then
    echo "claude-mem 플러그인 캐시 없음"
    exit 1
fi

TARGET="$HOOKS_DIR/$LATEST/hooks/hooks.json"

if [ ! -f "$TARGET" ]; then
    echo "hooks.json 없음: $TARGET"
    exit 1
fi

# context + session-init 훅 제거 (observation/summarize/session-complete는 유지)
/usr/bin/python3 - "$TARGET" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text())
hooks = data.get("hooks", {})

def strip_cmd(cmds, needle):
    return [h for h in cmds if needle not in h.get("command", "")]

# SessionStart에서 context 훅만 제거
for entry in hooks.get("SessionStart", []):
    entry["hooks"] = strip_cmd(entry.get("hooks", []), "hook claude-code context")

# UserPromptSubmit 전체 제거
hooks.pop("UserPromptSubmit", None)

p.write_text(json.dumps(data, indent=2) + "\n")
print(f"패치 완료: {p}")
PY
