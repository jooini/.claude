#!/usr/bin/env bash
# Vault 의 .md 파일이 Write/Edit 후 local-rag 에 자동 ingest 되도록 하는 PostToolUse hook.
#
# 설치 방법 (~/.claude/settings.json 의 hooks 섹션에 추가):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Write|Edit",
#           "hooks": [
#             { "type": "command", "command": "~/.claude/skills/vault-find/scripts/ingest_hook.sh" }
#           ]
#         }
#       ]
#     }
#   }
#
# Claude Code 가 stdin 으로 전달하는 JSON 에서 file_path 추출 → Vault 내부면 ingest.
set -euo pipefail

VAULT="${HOME}/Workspace/weaversbrain/weaversbrain"
LOG="${HOME}/.claude/logs/vault-ingest.log"
mkdir -p "$(dirname "$LOG")"

payload="$(cat 2>/dev/null || true)"
[[ -z "$payload" ]] && exit 0

file_path="$(printf '%s' "$payload" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    pass
" 2>/dev/null || true)"

[[ -z "$file_path" ]] && exit 0
[[ "$file_path" != "$VAULT"* ]] && exit 0
[[ "$file_path" != *.md ]] && exit 0
[[ "$file_path" == *"/MOC.md" ]] && exit 0   # 자동 생성 파일 제외
[[ "$file_path" == *"/.obsidian/"* ]] && exit 0
[[ "$file_path" == *"/Attachments/"* ]] && exit 0

# 인덱스 다시 빌드 (백그라운드)
nohup python3 "$VAULT/scripts/build_vault_index.py" --quiet \
    >> "$LOG" 2>&1 &
disown

echo "[$(date '+%Y-%m-%d %H:%M:%S')] indexed: $file_path" >> "$LOG"
exit 0
