#!/bin/zsh
# SessionStart: LLM-Wiki manifest 의 sha256 ↔ 실제 외부 Vault 파일 비교.
# drift (변경/누락) 있으면 stderr 알림. 차단 아님.

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

VAULT="/Users/leonard/Workspace/weaversbrain/weaversbrain"
MANIFEST="$VAULT/LLM-Wiki/raw/sources.yml"

# manifest 없으면 조용히 통과 (LLM-Wiki 미운영 상태)
if [ ! -f "$MANIFEST" ]; then
  outcome_log "vault-manifest-drift-detect" "pass" "" "no-manifest"
  exit 0
fi

# 변경/누락 카운트
REPORT=$(python3 <<'PYEOF'
import yaml, hashlib, sys
from pathlib import Path

vault = Path("/Users/leonard/Workspace/weaversbrain/weaversbrain")
manifest_path = vault / "LLM-Wiki/raw/sources.yml"

try:
    with open(manifest_path) as f:
        content = f.read()
    idx = content.find("\nsources:\n")
    if idx == -1:
        sys.exit(0)
    items = yaml.safe_load(content[idx + len("\nsources:\n"):])
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(0)

changed = []
missing = []
for item in items:
    p = vault / item['path']
    if not p.exists():
        missing.append(item['path'])
        continue
    try:
        current = hashlib.sha256(p.read_bytes()).hexdigest()[:16]
        if current != item['sha256']:
            changed.append((item['path'], item['sha256'], current))
    except Exception:
        pass

if changed or missing:
    print(f"total={len(items)}")
    print(f"changed={len(changed)}")
    print(f"missing={len(missing)}")
    for path, old, new in changed[:5]:
        print(f"CHANGED: {path} | {old} -> {new}")
    for path in missing[:5]:
        print(f"MISSING: {path}")
PYEOF
)

if [ -z "$REPORT" ]; then
  outcome_log "vault-manifest-drift-detect" "pass" "" "no-drift"
  exit 0
fi

# 변경/누락 있을 때만 알림
TOTAL=$(echo "$REPORT" | grep "^total=" | cut -d= -f2)
CHANGED=$(echo "$REPORT" | grep "^changed=" | cut -d= -f2)
MISSING=$(echo "$REPORT" | grep "^missing=" | cut -d= -f2)

cat >&2 <<MSGEOF
[LLM-Wiki manifest drift 감지]
total=$TOTAL  changed=$CHANGED  missing=$MISSING

상세 (최대 5건):
$(echo "$REPORT" | grep -E "^(CHANGED|MISSING):")

대응:
  - 변경: 원본 갱신됨 → "manifest 갱신" 또는 wiki 페이지 last_source_date 점검
  - 누락: 원본 삭제됨 → manifest 정리 + wiki 페이지에서 참조 제거

세션 작업 영향 없으면 무시 가능.
MSGEOF

outcome_log "vault-manifest-drift-detect" "notify" "$CHANGED/$TOTAL" "drift"
exit 0
