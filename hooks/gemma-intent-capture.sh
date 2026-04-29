#!/bin/zsh
# Stop hook: 세션 종료 시 "다음에 이어서 할 일" 추출
# 기존 gemma-session-summarize와 다른 점: 요약이 아니라 **미완료 의도** 중심
# 출력: ~/.claude/intent/{project}/{YYYY-MM-DD}.md (프로젝트별 최신만 유지)
# 페르소나: writer (qwen3.5:9b 자동 적용)

: "${HOME:?}"

QWEN="$HOME/.local/bin/qwen-cli"
INTENT_DIR="$HOME/.claude/intent"
mkdir -p "$INTENT_DIR"

# qwen-cli 미설치 시 즉시 스킵
[ -x "$QWEN" ] || exit 0

# 회사 LAN 외부에서 호출 시 즉시 skip (TCP 1초 캐시 5분)
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

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# jsonl 찾기 + 프로젝트 추정
JSONL=""
PROJECT=""
for dir in "$HOME/.claude/projects"/*/; do
    candidate="${dir}${SESSION_ID}.jsonl"
    if [ -f "$candidate" ]; then
        JSONL="$candidate"
        # 디렉토리 이름에서 프로젝트 추출
        PROJECT=$(basename "$dir" | /usr/bin/sed 's/^-Users-leonard-Workspace-//;s/^-Users-leonard//' | /usr/bin/tr -d '-' | /usr/bin/head -c 40)
        break
    fi
done

if [ -z "$JSONL" ] || [ ! -f "$JSONL" ]; then
    exit 0
fi

# 프로젝트명 추출 실패 시 capture 생략
# (홈 디렉토리 /Users/leonard 작업은 주제가 뒤섞이므로 "general" 버킷 오염 방지)
if [ -z "$PROJECT" ]; then
    exit 0
fi

# 세션의 마지막 30% 구간만 추출 (의도는 끝부분에 있음)
export JSONL_PATH="$JSONL"
LAST_CONTEXT=$(python3 <<'PYEOF'
import json, os

path = os.environ["JSONL_PATH"]
records = []
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
                if text and len(text) > 5 and not text.startswith('<'):
                    records.append(('user', text[:300]))
            elif mtype == 'assistant':
                msg = r.get('message', {})
                content = msg.get('content', [])
                if isinstance(content, list):
                    for c in content:
                        if c.get('type') == 'tool_use':
                            tool = c.get('name', '')
                            inp = c.get('input', {}) or {}
                            if tool in ('Edit', 'Write'):
                                fp = inp.get('file_path', '')
                                if fp:
                                    records.append(('edit', fp))
                            elif tool == 'Bash':
                                cmd = (inp.get('command', '') or '')[:120]
                                if cmd:
                                    records.append(('bash', cmd))
        except Exception:
            continue

# 마지막 30% 또는 최소 20건
tail_count = max(20, int(len(records) * 0.3))
tail = records[-tail_count:]

parts = []
parts.append("## 세션 마지막 부분 흐름")
for kind, val in tail[-50:]:
    if kind == 'user':
        parts.append(f"[사용자] {val}")
    elif kind == 'edit':
        parts.append(f"[수정] {val}")
    elif kind == 'bash':
        parts.append(f"[Bash] {val}")

print('\n'.join(parts))
PYEOF
)

if [ -z "$LAST_CONTEXT" ]; then
    exit 0
fi

# 너무 길면 앞부분 자름 (토큰 한계)
LAST_CONTEXT=$(echo "$LAST_CONTEXT" | /usr/bin/tail -c 3000)

# 프롬프트 구성
PROMPT=$(printf '다음은 방금 끝난 Claude Code 세션의 마지막 부분이다.\n"다음 세션에서 이어서 할 일"을 추출해라.\n\n세션 프로젝트: %s\n\n세션 기록 (마지막 부분):\n%s\n\n출력 형식 (정확히 5줄, 한국어):\n마지막 목표: <이 세션에서 하려던 최종 목표 한 줄>\n마지막 시도: <실제 마지막으로 시도한 구체 작업 한 줄>\n중단 이유: <완료? 막힘? 사용자 중단? 한 줄 추정>\n다음 작업: <바로 이어서 할 구체 행동 한 줄>\n주의점: <이어서 할 때 놓치면 안 되는 맥락 한 줄>\n\n규칙:\n- 세션 기록 근거만 사용. 추측 금지.\n- 완결된 세션이면 "없음"으로 표시.\n- 장식/이모지 금지.\n' "$PROJECT" "$LAST_CONTEXT")

# qwen-cli stdin 호출 — writer 페르소나 (qwen3.5:9b 자동 적용)
RESULT=$(echo "$PROMPT" | "$QWEN" -p - --profile writer --num-ctx 8192 2>/dev/null)
EXIT=$?

if [ "$EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    exit 0
fi

# 프로젝트별 디렉토리 + 최신 intent 유지
PROJECT_DIR="$INTENT_DIR/$PROJECT"
mkdir -p "$PROJECT_DIR"

TODAY=$(date +%Y-%m-%d)
HHMM=$(date +%H%M)
OUTPUT_FILE="$PROJECT_DIR/${TODAY}-${HHMM}.md"
LATEST_LINK="$PROJECT_DIR/latest.md"

{
    echo "# 의도 기록 — $PROJECT"
    echo ""
    echo "세션: $SESSION_ID"
    echo "종료: $(date +%Y-%m-%d\ %H:%M:%S)"
    echo "엔진: qwen-cli (writer / qwen3.5:9b)"
    echo ""
    echo "$RESULT"
} > "$OUTPUT_FILE"

# latest.md 심볼릭 링크 갱신
/bin/rm -f "$LATEST_LINK"
/bin/ln -s "$(basename "$OUTPUT_FILE")" "$LATEST_LINK"

# 전역 latest.md도 갱신 (프로젝트 무관 최신)
/bin/rm -f "$INTENT_DIR/latest.md"
/bin/ln -s "$PROJECT/$(basename "$OUTPUT_FILE")" "$INTENT_DIR/latest.md" 2>/dev/null

# 오래된 기록 정리 (프로젝트당 최근 10개 유지)
ls -t "$PROJECT_DIR"/[0-9]*.md 2>/dev/null | /usr/bin/tail -n +11 | while read f; do
    /bin/rm -f "$f"
done

exit 0
