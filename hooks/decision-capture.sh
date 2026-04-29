#!/bin/zsh
# PostToolUse(Agent): code-reviewer / Plan / planner 등의 출력에서
# 설계 결정·채택·기각 패턴을 추출하여 Obsidian Vault에 자동 저장
#
# 패턴: "결정:", "채택:", "기각:", "Decision:", "Selected:", "Rejected:"
# 저장: ~/Workspace/weaversbrain/weaversbrain/decisions/YYYY-MM-DD-HHMM-{topic}.md
# 비차단 — 추출 실패 시 무시

: "${HOME:?}"

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# 의사결정 캡처 대상 에이전트만
case "$AGENT_TYPE" in
    code-reviewer|Plan|qa|po|backend-developer|frontend-developer|ai-engineer|data-analyst|ops-lead)
        ;;
    *)
        exit 0
        ;;
esac

# tool_response 추출 (JSON에서 큰 필드일 수 있음 → python으로 안전 파싱)
RESPONSE=$(echo "$INPUT" | /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    resp = data.get("tool_response", "") or data.get("response", "")
    if isinstance(resp, dict):
        resp = json.dumps(resp, ensure_ascii=False)
    print(resp)
except Exception:
    pass
' 2>/dev/null)

[ -z "$RESPONSE" ] && exit 0

# 결정 패턴 추출
DECISIONS=$(echo "$RESPONSE" | grep -E '^(결정|채택|기각|Decision|Selected|Rejected|Recommendation|권장)[:：]' | head -20)

# 결정 키워드 없으면 스킵
[ -z "$DECISIONS" ] && exit 0

VAULT_DIR="$HOME/Workspace/weaversbrain/weaversbrain/decisions"
mkdir -p "$VAULT_DIR"

CWD=$(pwd)
PROJECT=$(basename "$CWD")
TIMESTAMP=$(date +"%Y-%m-%d-%H%M")
DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H:%M")

# 토픽 추출 — description 필드에서 첫 단어. 공백·슬래시·콜론을 하이픈으로
TOPIC=$(echo "$INPUT" | /usr/bin/python3 -c '
import json, sys, re
try:
    data = json.load(sys.stdin)
    desc = data.get("description", "")
    # 공백·슬래시·콜론을 하이픈으로, 길이 30자 제한
    topic = re.sub(r"[\s/:]+", "-", desc)[:30]
    # 영숫자·하이픈·한글만
    topic = re.sub(r"[^\w\-가-힣]", "", topic)
    print(topic)
except Exception:
    pass
' 2>/dev/null)
[ -z "$TOPIC" ] && TOPIC="${AGENT_TYPE}-decision"

OUT_FILE="$VAULT_DIR/${TIMESTAMP}-${PROJECT}-${TOPIC}.md"

cat > "$OUT_FILE" <<EOF
---
title: "${PROJECT} — ${TOPIC}"
date: ${DATE}
time: ${TIME}
project: ${PROJECT}
agent: ${AGENT_TYPE}
type: decision
tags: [decision, auto-capture, ${PROJECT}]
---

# ${PROJECT} — ${AGENT_TYPE} 결정 기록

## 추출된 결정

\`\`\`
${DECISIONS}
\`\`\`

## 컨텍스트

- 프로젝트: ${PROJECT}
- 에이전트: ${AGENT_TYPE}
- 작업 경로: ${CWD}
- 타임스탬프: ${DATE} ${TIME}

## 메모 (수동 추가)

<!-- 사후 메모/검증 결과를 여기에 추가 -->
EOF

# 인덱스 파일 갱신
INDEX_FILE="$VAULT_DIR/INDEX.md"
if [ ! -f "$INDEX_FILE" ]; then
    cat > "$INDEX_FILE" <<EOF
# 결정 기록 인덱스

자동 캡처된 설계/리뷰 결정 모음. \`decision-capture.sh\` 훅이 갱신.

## 목록 (최신순)

EOF
fi

# 인덱스 상단에 새 항목 추가
TMP=$(mktemp)
{
    head -6 "$INDEX_FILE"
    echo "- [${DATE} ${TIME}] [${PROJECT}/${TOPIC}](./${TIMESTAMP}-${PROJECT}-${TOPIC}.md) — ${AGENT_TYPE}"
    tail -n +7 "$INDEX_FILE"
} > "$TMP" && mv "$TMP" "$INDEX_FILE"

exit 0
