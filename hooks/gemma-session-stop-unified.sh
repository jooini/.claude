#!/bin/zsh
# Stop hook: 통합본 — gemma-session-summarize + gemma-intent-capture 머지
# ini 호출 1번으로 세션 요약 + 다음 작업 의도 둘 다 추출
# 출력 2곳:
#   1) ~/.claude/cache/session-summary/{session_id}.md  ← /done, /handoff, /save-history 소비
#   2) ~/.claude/intent/{project}/{YYYY-MM-DD-HHMM}.md  ← 다음 세션 이어서 (프로젝트 추정 가능 시만)
# 페르소나: writer (qwen3.5:9b)

: "${HOME:?}"

QWEN="$HOME/.local/bin/ini"
SUMMARY_DIR="$HOME/.claude/cache/session-summary"
INTENT_DIR="$HOME/.claude/intent"
mkdir -p "$SUMMARY_DIR" "$INTENT_DIR"

[ -x "$QWEN" ] || exit 0

source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0

SUMMARY_FILE="$SUMMARY_DIR/${SESSION_ID}.md"
[ -f "$SUMMARY_FILE" ] && exit 0

# jsonl + 프로젝트 추정
JSONL=""
PROJECT=""
for dir in "$HOME/.claude/projects"/*/; do
    candidate="${dir}${SESSION_ID}.jsonl"
    if [ -f "$candidate" ]; then
        JSONL="$candidate"
        PROJECT=$(basename "$dir" | /usr/bin/sed 's/^-Users-leonard-Workspace-//;s/^-Users-leonard//' | /usr/bin/tr -d '-' | /usr/bin/head -c 40)
        break
    fi
done

[ -z "$JSONL" ] || [ ! -f "$JSONL" ] && exit 0

# jsonl에서 전체 요약 + 마지막 30% 의도 동시 추출
export JSONL_PATH="$JSONL"
EXTRACTED=$(python3 <<'PYEOF'
import json, os

path = os.environ["JSONL_PATH"]
user_msgs = []
edited_files = []
bash_cmds = []
tail_records = []

try:
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            mtype = rec.get('type')
            if mtype == 'user':
                content = rec.get('message', {}).get('content', '')
                text = content if isinstance(content, str) else ' '.join(
                    c.get('text', '') for c in content if isinstance(c, dict) and c.get('type') == 'text'
                )
                text = text.strip()
                if text and len(text) > 5 and not text.startswith('<'):
                    user_msgs.append(text[:300])
                    tail_records.append(('user', text[:300]))
            elif mtype == 'assistant':
                msg = rec.get('message', {})
                content = msg.get('content', [])
                if isinstance(content, list):
                    for c in content:
                        if c.get('type') == 'tool_use':
                            tool = c.get('name', '')
                            inp = c.get('input', {}) or {}
                            if tool in ('Edit', 'Write', 'NotebookEdit'):
                                fp = inp.get('file_path', '')
                                if fp:
                                    edited_files.append(fp)
                                    tail_records.append(('edit', fp))
                            elif tool == 'Bash':
                                cmd = (inp.get('command', '') or '')[:120]
                                if cmd:
                                    bash_cmds.append(cmd)
                                    tail_records.append(('bash', cmd))
            elif mtype == 'tool_use':
                tool = rec.get('name', '')
                inp = rec.get('input', {}) or {}
                if tool in ('Edit', 'Write', 'NotebookEdit'):
                    fp = inp.get('file_path', '')
                    if fp:
                        edited_files.append(fp)
                elif tool == 'Bash':
                    cmd = (inp.get('command', '') or '')[:120]
                    if cmd:
                        bash_cmds.append(cmd)
except Exception:
    pass

# 중복 제거 유지순
seen = set()
deduped_files = []
for f in edited_files:
    if f not in seen:
        seen.add(f)
        deduped_files.append(f)

user_msgs = user_msgs[:30]
deduped_files = deduped_files[:40]
bash_cmds = bash_cmds[-15:]

tail_count = max(20, int(len(tail_records) * 0.3))
tail = tail_records[-tail_count:][-50:]

out = []
out.append("## 사용자 요청 흐름")
for m in user_msgs:
    out.append(f"- {m}")
if deduped_files:
    out.append("\n## 수정된 파일")
    for f in deduped_files:
        out.append(f"- {f}")
if bash_cmds:
    out.append("\n## 주요 Bash 명령 (최근 15)")
    for c in bash_cmds:
        out.append(f"- {c}")
out.append("\n## 세션 마지막 부분 흐름 (의도 추출용)")
for kind, val in tail:
    if kind == 'user':
        out.append(f"[사용자] {val}")
    elif kind == 'edit':
        out.append(f"[수정] {val}")
    elif kind == 'bash':
        out.append(f"[Bash] {val}")

print('\n'.join(out))
PYEOF
)

[ -z "$EXTRACTED" ] && exit 0

# 너무 길면 컷
EXTRACTED=$(echo "$EXTRACTED" | /usr/bin/tail -c 6000)

# 통합 프롬프트: 두 출력 블록 동시 요구
PROMPT=$(printf '다음은 방금 끝난 Claude Code 세션의 핵심 기록이다. 두 개의 구분된 블록을 정확히 그대로 출력해라.\n\n=== 블록 A: 세션 요약 ===\n## 한 줄 요약\n<세션 전체를 한 줄로 (70자 이내)>\n\n## 주요 작업\n- <작업 1>\n- <작업 2>\n- <작업 3>\n\n## 수정 파일\n- <경로> — <변경 의도 한 줄>\n\n## 미완료/후속 조치\n- <끝까지 마무리 안 된 것, 없으면 "없음">\n\n=== 블록 B: 다음 세션 의도 ===\n마지막 목표: <이 세션에서 하려던 최종 목표 한 줄>\n마지막 시도: <실제 마지막으로 시도한 구체 작업 한 줄>\n중단 이유: <완료? 막힘? 사용자 중단? 한 줄 추정>\n다음 작업: <바로 이어서 할 구체 행동 한 줄>\n주의점: <이어서 할 때 놓치면 안 되는 맥락 한 줄>\n\n=== 끝 ===\n\n규칙:\n- 세션 기록 근거만 사용. 추측 금지.\n- 완결된 세션이면 블록 B 모든 줄을 "없음"으로 표시.\n- 장식/이모지 금지. 인사/설명 금지. 위 두 블록만 출력.\n- 블록 구분선 "=== 블록 A: 세션 요약 ===", "=== 블록 B: 다음 세션 의도 ===", "=== 끝 ===" 그대로 포함.\n\n세션 기록:\n%s' "$EXTRACTED")

RESULT=$(echo "$PROMPT" | "$QWEN" -p - --profile writer --num-ctx 8192 2>/dev/null)
EXIT=$?

# qwen 실패 시 원재료라도 요약 위치에 저장
if [ "$EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    printf '# 세션 원재료 (ini writer 호출 실패)\n\n%s\n' "$EXTRACTED" > "$SUMMARY_FILE"
    exit 0
fi

# 결과를 블록 A / B 로 분할
export RESULT_TEXT="$RESULT"
SUMMARY_PART=$(python3 <<'PYEOF'
import os, re
text = os.environ["RESULT_TEXT"]
m = re.search(r'=== 블록 A: 세션 요약 ===\s*(.*?)\s*=== 블록 B:', text, re.DOTALL)
if m:
    print(m.group(1).strip())
else:
    print(text.strip())
PYEOF
)

INTENT_PART=$(python3 <<'PYEOF'
import os, re
text = os.environ["RESULT_TEXT"]
m = re.search(r'=== 블록 B: 다음 세션 의도 ===\s*(.*?)\s*=== 끝 ===', text, re.DOTALL)
if not m:
    m = re.search(r'=== 블록 B: 다음 세션 의도 ===\s*(.*)', text, re.DOTALL)
if m:
    print(m.group(1).strip())
PYEOF
)

# 출력 1: 세션 요약
{
    echo "# 세션 요약: ${SESSION_ID}"
    echo ""
    echo "생성: $(date +%Y-%m-%d\ %H:%M:%S)"
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

# 출력 2: 의도 기록 (프로젝트명 추정된 경우만 — 홈 디렉토리 작업은 "general" 오염 방지)
if [ -n "$PROJECT" ] && [ -n "$INTENT_PART" ]; then
    PROJECT_DIR="$INTENT_DIR/$PROJECT"
    mkdir -p "$PROJECT_DIR"
    TODAY=$(date +%Y-%m-%d)
    HHMM=$(date +%H%M)
    INTENT_FILE="$PROJECT_DIR/${TODAY}-${HHMM}.md"
    {
        echo "# 의도 기록 — $PROJECT"
        echo ""
        echo "세션: $SESSION_ID"
        echo "종료: $(date +%Y-%m-%d\ %H:%M:%S)"
        echo "엔진: ini (writer / qwen3.5:9b) [통합본]"
        echo ""
        echo "$INTENT_PART"
    } > "$INTENT_FILE"

    /bin/rm -f "$PROJECT_DIR/latest.md"
    /bin/ln -s "$(basename "$INTENT_FILE")" "$PROJECT_DIR/latest.md"
    /bin/rm -f "$INTENT_DIR/latest.md"
    /bin/ln -s "$PROJECT/$(basename "$INTENT_FILE")" "$INTENT_DIR/latest.md" 2>/dev/null

    ls -t "$PROJECT_DIR"/[0-9]*.md 2>/dev/null | /usr/bin/tail -n +11 | while read f; do
        /bin/rm -f "$f"
    done
fi

exit 0
