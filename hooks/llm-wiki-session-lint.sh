#!/bin/zsh
# SessionEnd: 세션 종료 시 LLM-Wiki 헬스체크.
# Pending (깨진 위키링크), 고아 페이지 검출. 보고만, 수정 안 함.

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

WIKI="/Users/leonard/Workspace/weaversbrain/weaversbrain/LLM-Wiki"

if [ ! -d "$WIKI/wiki" ]; then
  outcome_log "llm-wiki-session-lint" "pass" "" "no-wiki"
  exit 0
fi

cd "$WIKI" 2>/dev/null || exit 0

# Pending — 위키링크 있지만 페이지 없음
PENDING=$(grep -rEho '\[\[wiki/[^]|]+' wiki/ index.md 2>/dev/null | sed 's/\[\[//;s/|.*//' | sort -u | while read link; do
  [ ! -f "${link}.md" ] && echo "$link"
done)

# 고아 — 인바운드 0 인 페이지
ORPHANS=""
for f in wiki/topics/*.md wiki/concepts/*.md wiki/entities/*.md wiki/sources/*.md; do
  [ ! -f "$f" ] && continue
  base=$(basename "$f" .md)
  count=$(grep -rl "\[\[.*${base}\]\]\|\[\[.*${base}|" wiki/ index.md 2>/dev/null | grep -v "^$f$" | wc -l | tr -d ' ')
  if [ "$count" = "0" ]; then
    if [ -z "$ORPHANS" ]; then
      ORPHANS="$f"
    else
      ORPHANS="$ORPHANS
$f"
    fi
  fi
done

if [ -z "$PENDING" ]; then
  P_COUNT=0
else
  P_COUNT=$(printf '%s\n' "$PENDING" | grep -c .)
fi
if [ -z "$ORPHANS" ]; then
  O_COUNT=0
else
  O_COUNT=$(printf '%s\n' "$ORPHANS" | grep -c .)
fi

# 둘 다 0 이면 조용히 통과
if [ "$P_COUNT" = "0" ] && [ "$O_COUNT" = "0" ]; then
  outcome_log "llm-wiki-session-lint" "pass" "" "healthy"
  exit 0
fi

cat >&2 <<MSGEOF
[LLM-Wiki 세션 종료 lint]
pending=$P_COUNT  orphans=$O_COUNT

MSGEOF

if [ "$P_COUNT" -gt "0" ]; then
  echo "Pending (깨진 위키링크):" >&2
  echo "$PENDING" | head -5 | sed 's/^/  ❌ /' >&2
fi

if [ "$O_COUNT" -gt "0" ]; then
  echo "고아 (인바운드 0):" >&2
  printf '%s\n' "$ORPHANS" | head -5 | sed 's/^/  🔸 /' >&2
fi

echo "" >&2
echo "다음 세션에서 'lint' 호출로 일괄 처리 가능." >&2

outcome_log "llm-wiki-session-lint" "notify" "p=$P_COUNT o=$O_COUNT" "issues-found"
exit 0
