#!/bin/zsh
# Stop hook: 세션 종료 시 jsonl을 Gemma에 넘겨 한 줄 요약 + 수정 파일 + 미완료 TODO 추출
# 출력 저장 경로: ~/.claude/cache/session-summary/{session_id}.md
# /done, /handoff, /save-history 스킬이 읽어 재사용할 공통 빌딩블록
# 실패/서버다운 시 즉시 스킵 (세션 종료 블로킹 없음)

: "${HOME:?}"

OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"
CACHE_DIR="$HOME/.claude/cache/session-summary"
mkdir -p "$CACHE_DIR"

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

OUTPUT_FILE="$CACHE_DIR/${SESSION_ID}.md"

# 이미 처리된 세션은 스킵 (중복 호출 방지)
if [ -f "$OUTPUT_FILE" ]; then
    exit 0
fi

# jsonl 파일 찾기 (워크스페이스별 프로젝트 디렉토리 전체 훑기)
JSONL=""
for dir in "$HOME/.claude/projects"/*/; do
    candidate="${dir}${SESSION_ID}.jsonl"
    if [ -f "$candidate" ]; then
        JSONL="$candidate"
        break
    fi
done

if [ -z "$JSONL" ] || [ ! -f "$JSONL" ]; then
    exit 0
fi

# jsonl에서 핵심 정보만 추출: user 메시지 첫줄들 + 수정된 파일 경로
export JSONL_PATH="$JSONL"
EXTRACTED=$(python3 <<'PYEOF'
import json, os
path = os.environ["JSONL_PATH"]
user_msgs = []
edited_files = set()
bash_cmds = []
try:
    with open(path, encoding='utf-8') as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            mtype = rec.get('type')
            if mtype == 'user':
                content = rec.get('message', {}).get('content', '')
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    text = ' '.join(
                        c.get('text', '') for c in content if c.get('type') == 'text'
                    )
                else:
                    text = ''
                text = text.strip()
                # 너무 짧거나 시스템 메시지는 스킵
                if text and len(text) > 5 and not text.startswith('<'):
                    user_msgs.append(text[:300])
            elif mtype == 'tool_use':
                tool = rec.get('name', '')
                inp = rec.get('input', {})
                if tool in ('Edit', 'Write', 'NotebookEdit'):
                    fp = inp.get('file_path', '')
                    if fp:
                        edited_files.add(fp)
                elif tool == 'Bash':
                    cmd = inp.get('command', '')[:120]
                    if cmd:
                        bash_cmds.append(cmd)
except Exception as e:
    pass

# 너무 많으면 컷
user_msgs = user_msgs[:30]
edited_files = list(edited_files)[:40]
bash_cmds = bash_cmds[-15:]

parts = []
if user_msgs:
    parts.append("## 사용자 요청 흐름")
    for m in user_msgs:
        parts.append(f"- {m}")
if edited_files:
    parts.append("\n## 수정된 파일")
    for f in edited_files:
        parts.append(f"- {f}")
if bash_cmds:
    parts.append("\n## 주요 Bash 명령 (최근 15)")
    for c in bash_cmds:
        parts.append(f"- {c}")

print('\n'.join(parts))
PYEOF
)

if [ -z "$EXTRACTED" ]; then
    exit 0
fi

# Ollama 확인
if ! curl -s --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    # 서버 다운이라도 원재료는 저장 (나중에 다른 도구로 요약 가능)
    printf '# 세션 원재료 (Gemma 서버 접근 불가)\n\n%s\n' "$EXTRACTED" > "$OUTPUT_FILE"
    exit 0
fi

export EXTRACTED

PAYLOAD=$(python3 <<'PYEOF'
import json, os
data = os.environ["EXTRACTED"]
prompt = f"""다음은 Claude Code 세션의 핵심 기록이다. 한국어로 구조화된 세션 요약을 작성해줘.

출력 형식 (정확히 이 구조):

## 한 줄 요약
<세션 전체를 한 줄로 (70자 이내)>

## 주요 작업
- <작업 1>
- <작업 2>
- <작업 3>

## 수정 파일
- <경로> — <변경 의도 한 줄>
- ...

## 미완료/후속 조치
- <끝까지 마무리 안 된 것, 없으면 "없음">

규칙:
- 사용자 요청 흐름 + 수정 파일 + Bash 명령을 근거로만 작성
- 없는 내용 추측 금지
- 이모지/장식 금지

세션 기록:
{data}
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "한국어로 구조화된 세션 요약만 출력. 인사/설명 금지."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m"
}))
PYEOF
)

if [ -z "$PAYLOAD" ]; then
    exit 0
fi

RESULT=$(curl -s --max-time 45 "http://${OLLAMA_HOST}/api/chat" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('message', {}).get('content', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -n "$RESULT" ]; then
    {
        echo "# 세션 요약: ${SESSION_ID}"
        echo ""
        echo "생성: $(date +%Y-%m-%d\ %H:%M:%S)"
        echo "소스: ${JSONL}"
        echo ""
        echo "$RESULT"
        echo ""
        echo "---"
        echo "## 원재료"
        echo ""
        echo "$EXTRACTED"
    } > "$OUTPUT_FILE"
fi

exit 0
