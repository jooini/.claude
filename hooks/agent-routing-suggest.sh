#!/bin/zsh
# PreToolUse(Agent): 호출 직전, 학습된 라우팅 룰로 다른 agent 추천
# 데이터: ~/.claude/cache/md-live/agent-routing-rules.json
# 출력: 사용자에게 stdout 으로 경고 (차단 X — Claude 가 보고 판단)

: "${HOME:?}"

INPUT=$(cat)

# subagent_type 추출
AGENT=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
DESC=$(echo "$INPUT" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

[ -z "$AGENT" ] && exit 0

RULES_FILE="$HOME/.claude/cache/md-live/agent-routing-rules.json"
[ -f "$RULES_FILE" ] || exit 0

# 가장 최근 사용자 발화 추출 (transcript 마지막 진짜 user prompt)
USER_PROMPT=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    USER_PROMPT=$(/usr/bin/python3 - "$TRANSCRIPT" <<'PYEOF' 2>/dev/null
import json, sys
last = ""
try:
    with open(sys.argv[1]) as f:
        for ln in f:
            try: d = json.loads(ln)
            except: continue
            if d.get("type") == "user" and "toolUseResult" not in d:
                msg = d.get("message", {})
                c = msg.get("content","") if isinstance(msg, dict) else ""
                if isinstance(c, str) and c.strip():
                    last = c
except: pass
print(last)
PYEOF
)
fi

# 발화 + description 합쳐서 키워드 매칭
COMBINED="${USER_PROMPT} ${DESC}"
[ -z "$COMBINED" ] && exit 0

# Python 으로 룰 매칭 — agent 추천
SUGGESTION=$(/usr/bin/python3 - "$RULES_FILE" "$AGENT" "$COMBINED" <<'PYEOF' 2>/dev/null
import json, sys, re

rules_file, current_agent, text = sys.argv[1], sys.argv[2], sys.argv[3].lower()
try:
    rules = json.loads(open(rules_file).read()).get("rules", [])
except:
    sys.exit(0)

# 텍스트에 있는 키워드들 → 매칭된 룰 수집
matched = []
KEYWORD_RE = re.compile(r"[가-힣a-zA-Z][가-힣a-zA-Z0-9]{1,29}")
words = set(KEYWORD_RE.findall(text))
words = {w.lower() for w in words}
for r in rules:
    if r["keyword"] in words and r["suggested"] != current_agent:
        matched.append(r)

if not matched:
    sys.exit(0)

# 같은 agent 추천 모으기 — agent 별로 lift 합산
from collections import defaultdict
agent_lift = defaultdict(lambda: {"lift": 0, "evidence": 0, "kws": []})
for r in matched:
    agent_lift[r["suggested"]]["lift"] += r["lift"]
    agent_lift[r["suggested"]]["evidence"] += r["evidence"]
    agent_lift[r["suggested"]]["kws"].append(r["keyword"])

# top 1
ranked = sorted(agent_lift.items(), key=lambda x: -x[1]["lift"])
top_agent, info = ranked[0]
# 최소 lift 합 3 이상 + evidence 5+ (노이즈 컷)
if info["lift"] < 3.0 or info["evidence"] < 5:
    sys.exit(0)

print(f"{top_agent}|{info['lift']:.1f}|{info['evidence']}|{','.join(info['kws'][:5])}")
PYEOF
)

[ -z "$SUGGESTION" ] && exit 0

# pipe 분리
SUGG_AGENT=$(echo "$SUGGESTION" | cut -d'|' -f1)
SUGG_LIFT=$(echo "$SUGGESTION" | cut -d'|' -f2)
SUGG_EVID=$(echo "$SUGGESTION" | cut -d'|' -f3)
SUGG_KWS=$(echo "$SUGGESTION" | cut -d'|' -f4)

# 같은 추천을 같은 세션에서 반복 안 하도록 메모 (5분 윈도우)
MEMO_DIR="$HOME/.claude/cache/agent-routing-memo"
mkdir -p "$MEMO_DIR"
SESSION=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]\{1,8\}\).*/\1/p')
MEMO_FILE="$MEMO_DIR/${SESSION}_${AGENT}_${SUGG_AGENT}"
NOW=$(date +%s)
if [ -f "$MEMO_FILE" ]; then
    LAST=$(cat "$MEMO_FILE")
    DIFF=$((NOW - LAST))
    [ "$DIFF" -lt 300 ] && exit 0  # 5분 안에 같은 추천 한 번만
fi
echo "$NOW" > "$MEMO_FILE"

# X3: 추천 기록 — outcome 추적용
SUGG_DIR="$HOME/.claude/cache/md-live/.suggestions"
mkdir -p "$SUGG_DIR"
FULL_SESSION=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
SUGG_FILE="$SUGG_DIR/${FULL_SESSION}_${NOW}.json"
/usr/bin/python3 - "$SUGG_FILE" "$FULL_SESSION" "$NOW" "$AGENT" "$SUGG_AGENT" "$SUGG_LIFT" "$SUGG_KWS" <<'PYEOF' 2>/dev/null
import json, sys
path, sess, ts, current, suggested, lift, kws = sys.argv[1:8]
open(path, "w").write(json.dumps({
    "session_id": sess,
    "ts": int(ts),
    "current_agent": current,
    "suggested_agent": suggested,
    "lift": float(lift),
    "keywords": kws.split(","),
    "outcome": "pending",
}, ensure_ascii=False))
PYEOF

# X5: general-purpose 호출 + 강한 추천이면 차단 (exit 2)
# 조건: 현재 g-p && lift>=5 && evidence>=10 && 추천이 도메인 에이전트
LIFT_INT=${SUGG_LIFT%.*}
case "$SUGG_AGENT" in
    general-purpose|Explore|Plan) BLOCKABLE=false ;;
    *) BLOCKABLE=true ;;
esac
if [ "$AGENT" = "general-purpose" ] && [ "${LIFT_INT:-0}" -ge 5 ] && [ "${SUGG_EVID:-0}" -ge 10 ] && [ "$BLOCKABLE" = "true" ]; then
    cat >&2 <<EOF
🚨 [라우팅 차단] general-purpose 호출이 도메인 에이전트로 차단됨

이 작업은 학습 데이터상 '$SUGG_AGENT' 영역 (lift=${SUGG_LIFT}x, evidence=${SUGG_EVID}건).
매칭 키워드: $SUGG_KWS

조치: 이번 Agent 호출을 취소하고 subagent_type="$SUGG_AGENT" 로 재호출하세요.
(차단 우회가 필요하면 ~/.claude/cache/md-live/agent-routing-rules.json 에서 해당 키워드 룰 제거)
EOF
    exit 2
fi

# 약한 경고 (lift>=5지만 evidence 부족 또는 추천이 차단불가 에이전트)
if [ "$AGENT" = "general-purpose" ] && [ "${LIFT_INT:-0}" -ge 5 ]; then
    cat <<EOF
🚨 [강한 라우팅 경고] general-purpose 호출 감지

이 작업은 과거 데이터 분석상 '$SUGG_AGENT' 영역 (lift=${SUGG_LIFT}x, evidence=${SUGG_EVID}건).
매칭 키워드: $SUGG_KWS

권장: 이번 Agent 호출 취소 → '$SUGG_AGENT' 로 재호출
(general-purpose 는 일반 탐색용이며, 도메인 전문 agent 가 더 정확한 결과를 냅니다)
EOF
    exit 0
fi

# 약한 경고는 silence (2026-05-22): 채택률 7.3% (41건 중 3건). 노이즈만 발생.
# 강한 차단(line 134-145)과 general-purpose 강한 경고(line 148-159)는 유지.
# 추천 기록은 여전히 cache/md-live/.suggestions/ 에 남으므로 추후 통계 분석 가능.

exit 0
