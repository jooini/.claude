#!/bin/zsh
# PostToolUse: Vault 의 LLM-Wiki 외부 폴더에 새 markdown 이 생성되면
# "ingest 후보 발견" 알림. 차단 아님 (stderr 안내만).

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

# Write/Edit 의 file_path 추출
FILE_PATH=$(python3 - "$INPUT_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("tool_input", {}).get("file_path", ""))
except Exception:
    pass
PYEOF
)

[ -z "$FILE_PATH" ] && exit 0

# Vault 안의 markdown 만, LLM-Wiki/ 는 제외
VAULT="/Users/leonard/Workspace/weaversbrain/weaversbrain"
case "$FILE_PATH" in
  "$VAULT"/*.md) ;;
  *) outcome_log "vault-new-file-suggest" "pass" "" "non-vault-md"; exit 0 ;;
esac

REL="${FILE_PATH#$VAULT/}"
case "$REL" in
  LLM-Wiki/*) outcome_log "vault-new-file-suggest" "pass" "" "llm-wiki-internal"; exit 0 ;;
  .obsidian/*|.git/*|.trash/*) outcome_log "vault-new-file-suggest" "pass" "" "system-folder"; exit 0 ;;
esac

# 이미 manifest 에 있으면 알림 안 함 (drift hook 이 다룸)
MANIFEST="$VAULT/LLM-Wiki/raw/sources.yml"
if [ -f "$MANIFEST" ] && grep -qF "path: $REL" "$MANIFEST" 2>/dev/null; then
  outcome_log "vault-new-file-suggest" "pass" "$REL" "already-in-manifest"
  exit 0
fi

# Edit 인지 Write 인지 구별 — 신규 파일(Write) 만 알림. Edit 는 기존 파일 수정이라 노이즈.
TOOL_NAME=$(python3 - "$INPUT_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("tool_name", ""))
except Exception:
    pass
PYEOF
)

# 신규 파일은 Write 만 → Edit 는 통과
if [ "$TOOL_NAME" != "Write" ]; then
  outcome_log "vault-new-file-suggest" "pass" "$REL" "edit-not-suggest"
  exit 0
fi

cat >&2 <<MSGEOF
[LLM-Wiki ingest 후보 발견]
새 Vault 노트: $REL

이 파일이 위키 합성 가치 있다면:
  → "ingest $REL" 또는 "이거 위키에 정리해줘"

위키에 영향 없는 일상 노트면 무시 가능.
MSGEOF

outcome_log "vault-new-file-suggest" "notify" "$REL" "new-vault-md"
exit 0
