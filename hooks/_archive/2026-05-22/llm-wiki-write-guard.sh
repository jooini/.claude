#!/bin/zsh
# PreToolUse: weaversbrain Vault 의 LLM-Wiki shadow wiki 안전장치
# 기존 Vault 노트(Projects/Sessions/Daily/Learning/...) 를 LLM이 수정하려 하면 차단.
# LLM-Wiki/wiki/**, LLM-Wiki/index.md, LLM-Wiki/log.md, LLM-Wiki/raw/** 만 허용.
# exit 2 + stderr = 차단

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

# Edit/Write 의 file_path 추출
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

# weaversbrain Vault 안의 파일이 아니면 통과
VAULT="/Users/leonard/Workspace/weaversbrain/weaversbrain"
case "$FILE_PATH" in
  "$VAULT"/*) ;;
  *) outcome_log "llm-wiki-write-guard" "pass" "" "outside-vault"; exit 0 ;;
esac

# Vault 안이면 LLM-Wiki 허용 경로인지 검사
REL="${FILE_PATH#$VAULT/}"

case "$REL" in
  LLM-Wiki/wiki/*)            outcome_log "llm-wiki-write-guard" "pass" "" "wiki-allowed"; exit 0 ;;
  LLM-Wiki/index.md)          outcome_log "llm-wiki-write-guard" "pass" "" "index-allowed"; exit 0 ;;
  LLM-Wiki/log.md)            outcome_log "llm-wiki-write-guard" "pass" "" "log-allowed"; exit 0 ;;
  LLM-Wiki/raw/*)             outcome_log "llm-wiki-write-guard" "pass" "" "raw-allowed"; exit 0 ;;
  LLM-Wiki/CLAUDE.md)         outcome_log "llm-wiki-write-guard" "pass" "" "schema-allowed"; exit 0 ;;
  LLM-Wiki/README.md)         outcome_log "llm-wiki-write-guard" "pass" "" "readme-allowed"; exit 0 ;;
  Sessions/*)                 outcome_log "llm-wiki-write-guard" "pass" "" "sessions-allowed"; exit 0 ;;
esac

# Vault 안의 LLM-Wiki 밖 경로 = 차단
cat >&2 <<MSGEOF
[차단] weaversbrain Vault 의 LLM-Wiki 외부 경로에 Write/Edit 시도

대상: $FILE_PATH

이 Vault 는 사용자가 손으로 쓴 노트 1,800+개의 source of truth.
LLM-Wiki/CLAUDE.md 의 write allowlist 정책 위반.

허용 경로:
  - LLM-Wiki/wiki/**
  - LLM-Wiki/index.md, log.md
  - LLM-Wiki/raw/**
  - LLM-Wiki/CLAUDE.md, README.md

기존 노트(Projects/Sessions/Daily/Learning/...)에 합성물을 만들고 싶다면:
  → LLM-Wiki/wiki/topics/ 또는 wiki/concepts/ 하위에 새 페이지로 작성
  → 원본을 참조(wikilink) 하되 수정하지 말 것

예외: 사용자가 "기존 노트 X 를 수정해줘" 라고 명시적으로 요청한 경우만.
이 경우 사용자에게 한 번 더 확인 후 hook을 일시 우회할 것.
MSGEOF

outcome_log "llm-wiki-write-guard" "block" "$REL" "outside-llm-wiki"
exit 2
