#!/bin/zsh
# Stop hook: 세션 종료 시 jsonl을 ini에 넘겨 한 줄 요약 + 수정 파일 + 미완료 TODO 추출
# 출력 저장 경로: ~/.claude/cache/session-summary/{session_id}.md
# /done, /handoff, /save-history 스킬이 읽어 재사용할 공통 빌딩블록
# 실패/서버다운 시 즉시 스킵 (세션 종료 블로킹 없음)
# 페르소나: writer (qwen3.5:9b)

: "${HOME:?}"

QWEN="$HOME/.local/bin/ini"
CACHE_DIR="$HOME/.claude/cache/session-summary"
mkdir -p "$CACHE_DIR"

# ini 미설치 시 즉시 스킵
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

# 프롬프트 구성: 추출 원재료 + 출력 형식 지시
PROMPT=$(printf '다음은 Claude Code 세션의 핵심 기록이다. 한국어로 구조화된 세션 요약을 작성해줘.\n\n출력 형식 (정확히 이 구조):\n\n## 한 줄 요약\n<세션 전체를 한 줄로 (70자 이내)>\n\n## 주요 작업\n- <작업 1>\n- <작업 2>\n- <작업 3>\n\n## 수정 파일\n- <경로> — <변경 의도 한 줄>\n- ...\n\n## 미완료/후속 조치\n- <끝까지 마무리 안 된 것, 없으면 "없음">\n\n규칙:\n- 사용자 요청 흐름 + 수정 파일 + Bash 명령을 근거로만 작성\n- 없는 내용 추측 금지\n- 이모지/장식 금지\n- 인사/설명 금지, 위 형식만 출력\n\n세션 기록:\n%s' "$EXTRACTED")

# ini stdin 호출 — writer 페르소나 (qwen3.5:9b 자동 적용), 45초 타임아웃
RESULT=$(echo "$PROMPT" | "$QWEN" -p - --profile writer --num-ctx 8192 2>/dev/null)
EXIT=$?

# ini 실패 시 원재료라도 저장 (나중에 다른 도구로 요약 가능)
if [ "$EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    printf '# 세션 원재료 (ini writer 호출 실패)\n\n%s\n' "$EXTRACTED" > "$OUTPUT_FILE"
    exit 0
fi

{
    echo "# 세션 요약: ${SESSION_ID}"
    echo ""
    echo "생성: $(date +%Y-%m-%d\ %H:%M:%S)"
    echo "소스: ${JSONL}"
    echo "엔진: ini (writer / qwen3.5:9b)"
    echo ""
    echo "$RESULT"
    echo ""
    echo "---"
    echo "## 원재료"
    echo ""
    echo "$EXTRACTED"
} > "$OUTPUT_FILE"

exit 0
