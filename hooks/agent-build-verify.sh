#!/bin/zsh
# PostToolUse(Agent): 호출 후 agent-quality 의 unique_hits 가 0인 경우 빌드 누락 경고
# 데이터 부재(첫 호출)면 무시. 같은 agent 같은 세션에서 한 번만 알림.

: "${HOME:?}"

INPUT=$(cat)

AGENT=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$AGENT" ] && exit 0

# knowledge 가 있는 agent type 만 (general-purpose 등 제외)
KNOWLEDGE_DIR="$HOME/.claude/agents/knowledge/$AGENT"
[ -d "$KNOWLEDGE_DIR" ] || exit 0

QUALITY_FILE="$HOME/.claude/cache/md-live/agent-quality.jsonl"
[ -f "$QUALITY_FILE" ] || exit 0

# 이 agent 의 최근 5건 평균 unique_hits 계산
ZERO_RATE=$(/usr/bin/python3 - "$QUALITY_FILE" "$AGENT" <<'PYEOF' 2>/dev/null
import json, sys
qf, agent = sys.argv[1], sys.argv[2]
hits = []
try:
    with open(qf) as f:
        for ln in f:
            try: d = json.loads(ln)
            except: continue
            if d.get("agent_type") == agent:
                hits.append(d.get("domain", {}).get("unique_hits", 0))
except: pass
recent = hits[-5:] if hits else []
if len(recent) < 3:
    sys.exit(0)
zero_count = sum(1 for h in recent if h == 0)
print(f"{zero_count}/{len(recent)}")
PYEOF
)

[ -z "$ZERO_RATE" ] && exit 0

ZERO=$(echo "$ZERO_RATE" | cut -d'/' -f1)
TOTAL=$(echo "$ZERO_RATE" | cut -d'/' -f2)

# 최근 N건 중 절반 이상이 unique=0 이면 빌드/knowledge 문제 의심
if [ "$ZERO" -lt "$((TOTAL / 2 + 1))" ]; then
    exit 0
fi

# 알림 중복 방지 — 같은 agent 하루 1번만
ALERT_DIR="$HOME/.claude/cache/agent-build-alerts"
mkdir -p "$ALERT_DIR"
ALERT_FILE="$ALERT_DIR/${AGENT}_$(date +%Y-%m-%d)"
[ -f "$ALERT_FILE" ] && exit 0
: > "$ALERT_FILE"

# 빌드된 agent 파일 mtime vs knowledge mtime 비교
BUILD_FILE=""
for d in "$HOME/.claude/agents/builds/"{root,python,kotlin,nodejs,php,nokb}/; do
    if [ -f "$d$AGENT.md" ]; then BUILD_FILE="$d$AGENT.md"; break; fi
done

REBUILD_HINT=""
if [ -n "$BUILD_FILE" ]; then
    BUILD_TS=$(/usr/bin/stat -f%m "$BUILD_FILE" 2>/dev/null)
    NEWEST_KB=$(/usr/bin/find "$KNOWLEDGE_DIR" -name '*.md' -type f -exec /usr/bin/stat -f%m {} \; 2>/dev/null | sort -n | tail -1)
    if [ -n "$BUILD_TS" ] && [ -n "$NEWEST_KB" ] && [ "$NEWEST_KB" -gt "$BUILD_TS" ]; then
        REBUILD_HINT="🔧 knowledge 가 빌드보다 새 — 재빌드 필요: ~/.claude/agents/build-agents.sh $AGENT"
    fi
fi

cat <<EOF
⚠️ Agent Knowledge 활용 의심: $AGENT

최근 ${TOTAL}건 중 ${ZERO}건이 자기 knowledge 용어 0개 매칭.
가능 원인:
1. knowledge 빌드 누락 / 압축 손실
2. knowledge 도메인이 실제 작업과 미스매치 (예: ops-lead = 콘텐츠운영 vs DevOps)
3. agent system prompt 가 knowledge 안 참조

권장 액션:
- 빌드 재생성: ~/.claude/agents/build-agents.sh $AGENT
- knowledge 점검: ls $KNOWLEDGE_DIR
- 대시보드: http://localhost:8765/agent-quality (필터: $AGENT)
$REBUILD_HINT

(이 알림은 하루 1회. ~/.claude/cache/agent-build-alerts/ 에서 reset 가능)
EOF

exit 0
