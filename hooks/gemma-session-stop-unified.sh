#!/bin/zsh

: "${HOME:?}"

setopt NULL_GLOB

QWEN="$HOME/.local/bin/ini"
SUMMARY_DIR="$HOME/.claude/cache/session-summary"
INTENT_DIR="$HOME/.claude/intent"
DECISIONS_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Decisions"
LEARNING_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Learning"

[ -x "$QWEN" ] || exit 0

source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

INPUT=$(/bin/cat)

SESSION_ID=$(printf '%s' "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0

SUMMARY_FILE="$SUMMARY_DIR/${SESSION_ID}.md"
[ -f "$SUMMARY_FILE" ] && exit 0

JSONL=""
PROJECT=""
DECISION_PROJECT=""
PROJECT_ROOT_NAME=""

for dir in "$HOME/.claude/projects"/*/; do
    candidate="${dir}${SESSION_ID}.jsonl"
    if [ -f "$candidate" ]; then
        JSONL="$candidate"
        PROJECT_ROOT_NAME=$(/usr/bin/basename "$dir")
        PROJECT=$(printf '%s' "$PROJECT_ROOT_NAME" | /usr/bin/sed 's/^-Users-leonard-Workspace-//;s/^-Users-leonard//' | /usr/bin/tr -d '-' | /usr/bin/head -c 40)
        DECISION_PROJECT=$(printf '%s' "$PROJECT_ROOT_NAME" | /usr/bin/sed 's/^-Users-leonard-Workspace-//;s/^-Users-leonard-Work-//;s/^-Users-leonard//' | /usr/bin/tr -d '-' | /usr/bin/head -c 40)
        break
    fi
done

if [ -z "$JSONL" ] || [ ! -f "$JSONL" ]; then
    exit 0
fi

LINE_COUNT=$(/usr/bin/wc -l < "$JSONL" 2>/dev/null | /usr/bin/tr -d ' ')
if [ -z "$LINE_COUNT" ] || [ "$LINE_COUNT" -lt 30 ]; then
    exit 0
fi

[ -z "$DECISION_PROJECT" ] && DECISION_PROJECT="general"

/bin/mkdir -p "$SUMMARY_DIR" "$INTENT_DIR" 2>/dev/null

export JSONL_PATH="$JSONL"
EXTRACTED=$(/usr/bin/python3 <<'PYEOF'
import json
import os

MAX_CHARS = 24000
MIN_TRANSCRIPT_CHARS = 6000

path = os.environ["JSONL_PATH"]
user_messages = []
edited_files = []
bash_commands = []
tail_records = []
transcript_records = []

try:
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except Exception:
                continue

            message_type = record.get("type")
            if message_type == "user":
                content = record.get("message", {}).get("content", "")
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    text = " ".join(
                        item.get("text", "")
                        for item in content
                        if isinstance(item, dict) and item.get("type") == "text"
                    )
                else:
                    text = ""

                text = text.strip()
                if text and len(text) > 5 and not text.startswith("<"):
                    user_messages.append(text[:300])
                    tail_records.append(("user", text[:300]))
                    transcript_records.append(("user", text[:500]))

            elif message_type == "assistant":
                message = record.get("message", {})
                content = message.get("content", [])
                if isinstance(content, list):
                    text_parts = []
                    for item in content:
                        if not isinstance(item, dict):
                            continue

                        if item.get("type") == "text":
                            text = (item.get("text", "") or "").strip()
                            if text:
                                text_parts.append(text)
                        elif item.get("type") == "tool_use":
                            tool_name = item.get("name", "")
                            tool_input = item.get("input", {}) or {}
                            if tool_name in ("Edit", "Write", "NotebookEdit"):
                                file_path = tool_input.get("file_path", "")
                                if file_path:
                                    edited_files.append(file_path)
                                    tail_records.append(("edit", file_path))
                            elif tool_name == "Bash":
                                command = (tool_input.get("command", "") or "")[:120]
                                if command:
                                    bash_commands.append(command)
                                    tail_records.append(("bash", command))

                    if text_parts:
                        transcript_records.append(("assistant", " ".join(text_parts)[:500]))

            elif message_type == "tool_use":
                tool_name = record.get("name", "")
                tool_input = record.get("input", {}) or {}
                if tool_name in ("Edit", "Write", "NotebookEdit"):
                    file_path = tool_input.get("file_path", "")
                    if file_path:
                        edited_files.append(file_path)
                elif tool_name == "Bash":
                    command = (tool_input.get("command", "") or "")[:120]
                    if command:
                        bash_commands.append(command)
except Exception:
    pass

seen_files = set()
deduplicated_files = []
for file_path in edited_files:
    if file_path not in seen_files:
        seen_files.add(file_path)
        deduplicated_files.append(file_path)

user_messages = user_messages[:30]
deduplicated_files = deduplicated_files[:40]
bash_commands = bash_commands[-15:]

tail_count = max(20, int(len(tail_records) * 0.3))
tail = tail_records[-tail_count:][-50:]

if len(transcript_records) > 300:
    transcript_records = transcript_records[:100] + transcript_records[-200:]

summary_lines = []
summary_lines.append("## 사용자 요청 흐름")
for message in user_messages:
    summary_lines.append(f"- {message}")

if deduplicated_files:
    summary_lines.append("")
    summary_lines.append("## 수정된 파일")
    for file_path in deduplicated_files:
        summary_lines.append(f"- {file_path}")

if bash_commands:
    summary_lines.append("")
    summary_lines.append("## 주요 Bash 명령 (최근 15)")
    for command in bash_commands:
        summary_lines.append(f"- {command}")

summary_lines.append("")
summary_lines.append("## 세션 마지막 부분 흐름 (의도 추출용)")
for kind, value in tail:
    if kind == "user":
        summary_lines.append(f"[사용자] {value}")
    elif kind == "edit":
        summary_lines.append(f"[수정] {value}")
    elif kind == "bash":
        summary_lines.append(f"[Bash] {value}")

transcript_lines = ["## 대화 텍스트 (결정/학습 추출용)"]
for kind, value in transcript_records:
    if kind == "user":
        transcript_lines.append(f"[USER] {value}")
    else:
        transcript_lines.append(f"[ASSISTANT] {value}")

summary_text = "\n".join(summary_lines)
transcript_text = "\n".join(transcript_lines)

if len(summary_text) > 12000:
    summary_text = summary_text[:6000] + "\n...\n" + summary_text[-6000:]

transcript_budget = MAX_CHARS - len(summary_text) - 2
if transcript_budget < MIN_TRANSCRIPT_CHARS:
    summary_budget = MAX_CHARS - MIN_TRANSCRIPT_CHARS - 2
    if len(summary_text) > summary_budget:
        summary_text = summary_text[: summary_budget // 2] + "\n...\n" + summary_text[-summary_budget // 2 :]
    transcript_budget = MIN_TRANSCRIPT_CHARS

if len(transcript_text) > transcript_budget:
    transcript_text = transcript_text[-transcript_budget:]

print(f"{summary_text}\n\n{transcript_text}")
PYEOF
)

if [ -z "$EXTRACTED" ]; then
    {
        echo "# 세션 원재료 (jsonl 추출 없음)"
        echo ""
        echo "생성: $(/bin/date +%Y-%m-%d\ %H:%M:%S)"
        echo "소스: ${JSONL}"
    } > "$SUMMARY_FILE"
    exit 0
fi

PROMPT=$(printf '다음은 방금 끝난 Claude Code 세션의 핵심 기록이다. 네 개의 구분된 블록을 정확히 그대로 출력해라.\n\n=== 블록 A: 세션 요약 ===\n## 한 줄 요약\n<세션 전체를 한 줄로 (70자 이내)>\n\n## 주요 작업\n- <작업 1>\n- <작업 2>\n- <작업 3>\n\n## 수정 파일\n- <경로> — <변경 의도 한 줄>\n\n## 미완료/후속 조치\n- <끝까지 마무리 안 된 것, 없으면 "없음">\n\n=== 블록 B: 다음 세션 의도 ===\n마지막 목표: <이 세션에서 하려던 최종 목표 한 줄>\n마지막 시도: <실제 마지막으로 시도한 구체 작업 한 줄>\n중단 이유: <완료? 막힘? 사용자 중단? 한 줄 추정>\n다음 작업: <바로 이어서 할 구체 행동 한 줄>\n주의점: <이어서 할 때 놓치면 안 되는 맥락 한 줄>\n\n=== 블록 C: 결정 ===\ndecisions:\n  - topic: <한 줄 주제>\n    decision: <무엇을 결정했나, 1줄>\n    rationale: <왜 그렇게 결정했나, 1줄>\n    alternatives_rejected: <기각한 대안, 1줄 또는 "none">\n\n=== 블록 D: 학습 ===\nlearnings:\n  - topic: <한 줄 주제>\n    insight: <무엇을 배웠나, 1-2줄>\n    context: <어떤 상황에서 배웠나, 1줄>\n    follow_up: <후속 학습 필요한 것, 1줄 또는 "none">\n\n=== 끝 ===\n\n규칙:\n- 세션 기록 근거만 사용. 추측 금지.\n- 완결된 세션이면 블록 B 모든 줄을 "없음"으로 표시.\n- 결정이 없으면 블록 C는 정확히 "decisions: []" 만 출력.\n- 학습 거리가 없으면 블록 D는 정확히 "learnings: []" 만 출력.\n- 블록 C와 D에는 마크다운 코드펜스나 설명을 넣지 말고 YAML만 출력.\n- 최대 결정 5개, 학습 5개.\n- 장식/이모지/인사/설명 금지. 위 네 블록만 출력.\n- 블록 구분선 "=== 블록 A: 세션 요약 ===", "=== 블록 B: 다음 세션 의도 ===", "=== 블록 C: 결정 ===", "=== 블록 D: 학습 ===", "=== 끝 ===" 그대로 포함.\n\n세션 기록:\n%s' "$EXTRACTED")

RESULT=$(printf '%s\n' "$PROMPT" | "$QWEN" -p - --profile writer --num-ctx 8192 --quiet 2>/dev/null)
INI_EXIT=$?

if [ "$INI_EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    {
        echo "# 세션 원재료 (ini writer 통합 호출 실패)"
        echo ""
        echo "생성: $(/bin/date +%Y-%m-%d\ %H:%M:%S)"
        echo "소스: ${JSONL}"
        echo "엔진: ini (unified / qwen3.5:9b)"
        echo ""
        echo "$EXTRACTED"
    } > "$SUMMARY_FILE"
    exit 0
fi

extract_block() {
    local start="$1"
    local end="$2"
    /usr/bin/python3 - "$start" "$end" <<'PYEOF'
import os
import re
import sys

text = os.environ.get("RESULT_TEXT", "")
start = re.escape(sys.argv[1])
end = re.escape(sys.argv[2])
pattern = r"^\s*" + start + r"\s*(.*?)^\s*" + end
match = re.search(pattern, text, re.DOTALL | re.MULTILINE)
if match:
    print(match.group(1).strip())
PYEOF
}

export RESULT_TEXT="$RESULT"
SUMMARY_PART=$(extract_block "=== 블록 A: 세션 요약 ===" "=== 블록 B: 다음 세션 의도 ===")
INTENT_PART=$(extract_block "=== 블록 B: 다음 세션 의도 ===" "=== 블록 C: 결정 ===")
DECISION_PART=$(extract_block "=== 블록 C: 결정 ===" "=== 블록 D: 학습 ===")
LEARNING_PART=$(extract_block "=== 블록 D: 학습 ===" "=== 끝 ===")

[ -z "$SUMMARY_PART" ] && SUMMARY_PART="$RESULT"

{
    echo "# 세션 요약: ${SESSION_ID}"
    echo ""
    echo "생성: $(/bin/date +%Y-%m-%d\ %H:%M:%S)"
    echo "소스: ${JSONL}"
    echo "엔진: ini (writer / qwen3.5:9b) [통합본]"
    echo ""
    echo "$SUMMARY_PART"
    echo ""
    echo "---"
    echo "## 원재료"
    echo ""
    echo "$EXTRACTED"
} > "$SUMMARY_FILE"

if [ -n "$PROJECT" ] && [ -n "$INTENT_PART" ]; then
    PROJECT_DIR="$INTENT_DIR/$PROJECT"
    /bin/mkdir -p "$PROJECT_DIR" 2>/dev/null
    TODAY=$(/bin/date +%Y-%m-%d)
    HHMM=$(/bin/date +%H%M)
    INTENT_FILE="$PROJECT_DIR/${TODAY}-${HHMM}.md"
    {
        echo "# 의도 기록 — $PROJECT"
        echo ""
        echo "세션: $SESSION_ID"
        echo "종료: $(/bin/date +%Y-%m-%d\ %H:%M:%S)"
        echo "엔진: ini (writer / qwen3.5:9b) [통합본]"
        echo ""
        echo "$INTENT_PART"
    } > "$INTENT_FILE"

    /bin/rm -f "$PROJECT_DIR/latest.md"
    /bin/ln -s "$(/usr/bin/basename "$INTENT_FILE")" "$PROJECT_DIR/latest.md"
    /bin/rm -f "$INTENT_DIR/latest.md"
    /bin/ln -s "$PROJECT/$(/usr/bin/basename "$INTENT_FILE")" "$INTENT_DIR/latest.md" 2>/dev/null

    /bin/ls -t "$PROJECT_DIR"/[0-9]*.md 2>/dev/null | /usr/bin/tail -n +11 | while read f; do
        /bin/rm -f "$f"
    done
fi

DECISION_CHECK=$(printf '%s' "$DECISION_PART" | /usr/bin/python3 -c '
import re
import sys

text = sys.stdin.read()
if re.search(r"decisions:\s*\[\s*\]", text) or not re.search(r"(?m)^\s*-\s*topic\s*:", text):
    print("EMPTY")
else:
    print("HAS")
' 2>/dev/null)

if [ "$DECISION_CHECK" = "HAS" ]; then
    /bin/mkdir -p "$DECISIONS_DIR" 2>/dev/null
    TODAY=$(/bin/date +%Y-%m-%d)
    HHMM=$(/bin/date +%H%M)
    SHORT_ID=$(printf '%s' "$SESSION_ID" | /usr/bin/head -c 8)
    DECISION_FILE="$DECISIONS_DIR/${TODAY}-${HHMM}-${SHORT_ID}.md"

    if [ -f "$DECISION_FILE" ]; then
        DECISION_FILE="$DECISIONS_DIR/${TODAY}-${HHMM}-${SHORT_ID}-2.md"
    fi

    DATE_FULL=$(/bin/date +"%Y-%m-%d %H:%M:%S")

    {
        echo "---"
        echo "title: \"결정 기록 — ${DECISION_PROJECT} (${TODAY} ${HHMM})\""
        echo "date: ${TODAY}"
        echo "time: $(/bin/date +%H:%M)"
        echo "session_id: ${SESSION_ID}"
        echo "project: ${DECISION_PROJECT}"
        echo "type: decision"
        echo "source: qwen-decision-capture"
        echo "engine: ini (unified / qwen3.5:9b)"
        echo "tags: [decision, auto-capture, ${DECISION_PROJECT}]"
        echo "---"
        echo ""
        echo "# 결정 기록 — ${DECISION_PROJECT}"
        echo ""
        echo "- 세션: \`${SESSION_ID}\`"
        echo "- 종료: ${DATE_FULL}"
        echo "- 소스 jsonl: \`${JSONL}\`"
        echo ""
        echo "## 추출된 결정"
        echo ""
        echo '```yaml'
        echo "$DECISION_PART"
        echo '```'
    } > "$DECISION_FILE"
fi

LEARNING_CHECK=$(printf '%s' "$LEARNING_PART" | /usr/bin/python3 -c '
import re
import sys

text = sys.stdin.read()
if re.search(r"learnings:\s*\[\s*\]", text) or not re.search(r"(?m)^\s*-\s*topic\s*:", text):
    print("EMPTY")
else:
    print("HAS")
' 2>/dev/null)

if [ "$LEARNING_CHECK" = "HAS" ]; then
    /bin/mkdir -p "$LEARNING_DIR" 2>/dev/null
    TODAY=$(/bin/date +%Y-%m-%d)
    TIME_NOW=$(/bin/date +%H:%M)
    SHORT_SESSION=$(printf '%s' "$SESSION_ID" | /usr/bin/cut -c1-8)
    LEARNING_FILE="$LEARNING_DIR/${TODAY}.md"

    if [ ! -f "$LEARNING_FILE" ]; then
        {
            echo "---"
            echo "date: $TODAY"
            echo "type: learning"
            echo "auto_generated: true"
            echo "source: qwen-learning-capture"
            echo "---"
            echo ""
            echo "# 학습 추출 — $TODAY"
            echo ""
        } > "$LEARNING_FILE"
    fi

    {
        echo ""
        echo "## 세션 $SHORT_SESSION ($TIME_NOW)"
        echo ""
        echo "엔진: ini (unified / qwen3.5:9b)"
        echo ""
        echo "\`\`\`yaml"
        echo "$LEARNING_PART"
        echo "\`\`\`"
        echo ""
    } >> "$LEARNING_FILE"
fi

exit 0
