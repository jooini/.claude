#!/bin/zsh
# Stop hook: 세션 종료 시 ini로 학습 내용 추출
#
# 작동:
#   - 세션 jsonl에서 user/assistant 텍스트 추출 (300건 cap)
#   - ini (learning 페르소나)에 전달 → "learnings:" YAML 응답
#   - 빈 learnings면 skip
#   - ~/Workspace/weaversbrain/weaversbrain/Learning/YYYY-MM-DD.md 에 append
#
# 비동기/best-effort. 실패 무시. 다른 Stop hook과 병행 안전.
# 다른 출력 경로:
#   - daily-learning-capture.sh   → Learning/YYYY-MM/YYYY-MM-DD.md
#   - qwen-learning-capture.sh    → Learning/YYYY-MM-DD.md
#   - decision-capture.sh         → decisions/

: "${HOME:?}"

QWEN="$HOME/.local/bin/ini"
[ -x "$QWEN" ] || exit 0

# 회사 LAN 외부에서 호출 시 즉시 skip (TCP 1초 캐시 5분)
source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

LEARNING_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Learning"
/bin/mkdir -p "$LEARNING_DIR" 2>/dev/null

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0

# jsonl 찾기
JSONL=""
for dir in "$HOME/.claude/projects"/*/; do
    candidate="${dir}${SESSION_ID}.jsonl"
    if [ -f "$candidate" ]; then
        JSONL="$candidate"
        break
    fi
done

[ -z "$JSONL" ] || [ ! -f "$JSONL" ] && exit 0

# 짧은 세션 skip (라인 30 미만)
LINE_COUNT=$(/usr/bin/wc -l < "$JSONL" 2>/dev/null | /usr/bin/tr -d ' ')
if [ -z "$LINE_COUNT" ] || [ "$LINE_COUNT" -lt 30 ]; then
    exit 0
fi

# user/assistant 텍스트 추출 (300건 cap)
export JSONL_PATH="$JSONL"
TRANSCRIPT=$(/usr/bin/python3 <<'PYEOF'
import json, os

path = os.environ["JSONL_PATH"]
items = []
CAP = 300

with open(path, encoding='utf-8', errors='replace') as f:
    for line in f:
        try:
            r = json.loads(line)
            mtype = r.get('type')
            if mtype == 'user':
                content = r.get('message', {}).get('content', '')
                text = content if isinstance(content, str) else ' '.join(
                    c.get('text', '') for c in content if isinstance(c, dict) and c.get('type') == 'text'
                )
                text = text.strip()
                if text and len(text) > 10 and not text.startswith('<'):
                    items.append(('U', text[:400]))
            elif mtype == 'assistant':
                msg = r.get('message', {})
                content = msg.get('content', [])
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get('type') == 'text':
                            t = (c.get('text') or '').strip()
                            if t and len(t) > 20:
                                items.append(('A', t[:400]))
        except Exception:
            continue

# 300건 cap (앞뒤 균형 — 처음 100 + 마지막 200)
if len(items) > CAP:
    head = items[:100]
    tail = items[-200:]
    items = head + tail

out = []
for kind, text in items:
    role = '사용자' if kind == 'U' else '어시스턴트'
    out.append(f"[{role}] {text}")

print('\n'.join(out))
PYEOF
)

[ -z "$TRANSCRIPT" ] && exit 0

# 너무 길면 자름 (qwen num-ctx 8192 기준 안전 마진)
TRANSCRIPT=$(echo "$TRANSCRIPT" | /usr/bin/tail -c 24000)

# 프롬프트 구성 — YAML 응답 강제
PROMPT=$(printf '다음은 방금 끝난 Claude Code 세션 기록이다. 사용자가 새로 알게 된 학습 거리(개념, 패턴, 함정, 디버깅 통찰)를 추출해라.\n\n세션 기록:\n%s\n\n출력 형식 (정확히 YAML, 다른 텍스트 금지):\nlearnings:\n  - topic: <주제 5단어 이내>\n    insight: <핵심 통찰 1~2문장>\n    context: <어떤 상황에서 배웠는지 한 줄>\n  - topic: ...\n\n규칙:\n- 세션 기록 근거만 사용. 추측/일반론 금지.\n- 진짜 새로 알게 된 것만. 단순 작업 진행은 학습 아님.\n- 학습 거리 없으면 정확히 "learnings: []" 만 출력.\n- 최대 5개.\n- 한국어.\n' "$TRANSCRIPT")

# ini 호출 — learning 페르소나, 8192 컨텍스트, quiet
RESULT=$(echo "$PROMPT" | "$QWEN" -p - --profile learning --num-ctx 8192 --quiet 2>/dev/null)
EXIT=$?

if [ "$EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    exit 0
fi

# 빈 learnings 응답 감지 — "learnings: []" 또는 항목 0개
EMPTY_CHECK=$(echo "$RESULT" | /usr/bin/python3 -c '
import sys, re
text = sys.stdin.read()
# "learnings: []" 또는 "learnings:" 다음에 항목 없는 경우
if re.search(r"learnings:\s*\[\s*\]", text):
    print("EMPTY")
elif re.search(r"learnings:\s*$", text.strip(), re.MULTILINE):
    # learnings: 다음에 - topic 같은 항목 있는지
    after = text.split("learnings:", 1)[1] if "learnings:" in text else ""
    if not re.search(r"-\s*topic\s*:", after):
        print("EMPTY")
    else:
        print("HAS")
else:
    if re.search(r"-\s*topic\s*:", text):
        print("HAS")
    else:
        print("EMPTY")
' 2>/dev/null)

if [ "$EMPTY_CHECK" = "EMPTY" ]; then
    exit 0
fi

# 출력 파일
TODAY=$(/bin/date +%Y-%m-%d)
TIME_NOW=$(/bin/date +%H:%M)
SHORT_SESSION=$(echo "$SESSION_ID" | /usr/bin/cut -c1-8)
OUTPUT_FILE="$LEARNING_DIR/${TODAY}.md"

# 파일 없으면 frontmatter + heading 포함하여 새로 생성
if [ ! -f "$OUTPUT_FILE" ]; then
    cat > "$OUTPUT_FILE" <<HEADER
---
date: $TODAY
type: learning
auto_generated: true
source: qwen-learning-capture
---

# 학습 추출 — $TODAY

HEADER
fi

# append: 새 세션 섹션을 본문 끝에 추가
{
    /bin/echo ""
    /bin/echo "## 세션 $SHORT_SESSION ($TIME_NOW)"
    /bin/echo ""
    /bin/echo "엔진: ini (learning)"
    /bin/echo ""
    /bin/echo "\`\`\`yaml"
    /bin/echo "$RESULT"
    /bin/echo "\`\`\`"
    /bin/echo ""
} >> "$OUTPUT_FILE"

exit 0
