#!/bin/zsh
# Stop hook: 세션 종료 시 jsonl을 ini decisions 페르소나에 넘겨 의사결정 추출
# 결정 발견 시 Obsidian Vault Decisions 디렉토리에 yaml 본문 그대로 저장
# 비차단 — ini 미설치/실패/짧은 세션이면 즉시 스킵
# 페르소나: decisions (qwen3.5:9b, ~/Library/Application Support/com.weaversmind.ini/profiles/decisions.md)

: "${HOME:?}"

QWEN="$HOME/.local/bin/ini"
PROCESSED_DIR="$HOME/.claude/cache/qwen-decision-processed"
DECISIONS_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Decisions"
MIN_RECORDS=10
MAX_RECORDS=300

# ini 미설치 시 즉시 스킵
[ -x "$QWEN" ] || exit 0

# 회사 LAN 외부에서 호출 시 즉시 skip (TCP 1초 캐시 5분)
source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# 중복 처리 방지 마커
mkdir -p "$PROCESSED_DIR"
MARKER="$PROCESSED_DIR/${SESSION_ID}.done"
if [ -f "$MARKER" ]; then
    exit 0
fi

# jsonl 찾기 + 프로젝트 추정
JSONL=""
PROJECT=""
for dir in "$HOME/.claude/projects"/*/; do
    candidate="${dir}${SESSION_ID}.jsonl"
    if [ -f "$candidate" ]; then
        JSONL="$candidate"
        PROJECT=$(basename "$dir" | /usr/bin/sed 's/^-Users-leonard-Workspace-//;s/^-Users-leonard-Work-//;s/^-Users-leonard//' | /usr/bin/tr -d '-' | /usr/bin/head -c 40)
        break
    fi
done

if [ -z "$JSONL" ] || [ ! -f "$JSONL" ]; then
    exit 0
fi

[ -z "$PROJECT" ] && PROJECT="general"

# jsonl 길이 체크 (최소 메시지 수)
LINE_COUNT=$(/usr/bin/wc -l < "$JSONL" | /usr/bin/tr -d ' ')
if [ "$LINE_COUNT" -lt "$MIN_RECORDS" ]; then
    /usr/bin/touch "$MARKER"
    exit 0
fi

# user 메시지 + assistant 텍스트 추출 (최대 300건)
export JSONL_PATH="$JSONL"
export MAX_RECORDS_ENV="$MAX_RECORDS"
EXTRACTED=$(/usr/bin/python3 <<'PYEOF'
import json, os

path = os.environ["JSONL_PATH"]
cap = int(os.environ.get("MAX_RECORDS_ENV", "300"))
records = []

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
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    text = ' '.join(
                        c.get('text', '') for c in content
                        if isinstance(c, dict) and c.get('type') == 'text'
                    )
                else:
                    text = ''
                text = text.strip()
                if text and len(text) > 5 and not text.startswith('<'):
                    records.append(('user', text[:500]))
            elif mtype == 'assistant':
                msg = rec.get('message', {})
                content = msg.get('content', [])
                if isinstance(content, list):
                    parts = []
                    for c in content:
                        if isinstance(c, dict) and c.get('type') == 'text':
                            t = (c.get('text', '') or '').strip()
                            if t:
                                parts.append(t)
                    if parts:
                        joined = ' '.join(parts)[:500]
                        records.append(('assistant', joined))
except Exception:
    pass

if len(records) > cap:
    # 앞쪽보다 뒤쪽 결정이 중요하므로 끝에서 cap건 유지
    records = records[-cap:]

lines = []
for kind, val in records:
    if kind == 'user':
        lines.append(f"[USER] {val}")
    else:
        lines.append(f"[ASSISTANT] {val}")

print('\n'.join(lines))
PYEOF
)

if [ -z "$EXTRACTED" ]; then
    /usr/bin/touch "$MARKER"
    exit 0
fi

# ini decisions 페르소나 호출 (--quiet 로 배너 차단)
RESULT=$(printf '%s\n' "$EXTRACTED" | "$QWEN" -p - --profile decisions --num-ctx 8192 --quiet 2>/dev/null)
EXIT=$?

# 호출 실패는 마커 남기지 않음 (다음 세션 또는 재시도 가능)
if [ "$EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    exit 0
fi

# 빈 decisions 면 마커만 남기고 종료
TRIMMED=$(printf '%s' "$RESULT" | /usr/bin/tr -d '[:space:]')
case "$TRIMMED" in
    *"decisions:[]"*|"decisions:[]")
        /usr/bin/touch "$MARKER"
        exit 0
        ;;
esac

# 결정 항목이 실제 존재하는지 확인 (- topic: 패턴)
if ! printf '%s' "$RESULT" | /usr/bin/grep -q '^[[:space:]]*-[[:space:]]*topic:'; then
    /usr/bin/touch "$MARKER"
    exit 0
fi

# Obsidian 디렉토리 보장
mkdir -p "$DECISIONS_DIR"

TODAY=$(date +%Y-%m-%d)
HHMM=$(date +%H%M)
SHORT_ID=$(printf '%s' "$SESSION_ID" | /usr/bin/head -c 8)
OUTPUT_FILE="$DECISIONS_DIR/${TODAY}-${HHMM}-${SHORT_ID}.md"

# 동일 분 충돌 방지 (희박하지만)
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="$DECISIONS_DIR/${TODAY}-${HHMM}-${SHORT_ID}-2.md"
fi

DATE_FULL=$(date +"%Y-%m-%d %H:%M:%S")

{
    echo "---"
    echo "title: \"결정 기록 — ${PROJECT} (${TODAY} ${HHMM})\""
    echo "date: ${TODAY}"
    echo "time: $(date +%H:%M)"
    echo "session_id: ${SESSION_ID}"
    echo "project: ${PROJECT}"
    echo "type: decision"
    echo "source: qwen-decision-capture"
    echo "engine: ini (decisions / qwen3.5:9b)"
    echo "tags: [decision, auto-capture, ${PROJECT}]"
    echo "---"
    echo ""
    echo "# 결정 기록 — ${PROJECT}"
    echo ""
    echo "- 세션: \`${SESSION_ID}\`"
    echo "- 종료: ${DATE_FULL}"
    echo "- 소스 jsonl: \`${JSONL}\`"
    echo ""
    echo "## 추출된 결정"
    echo ""
    echo '```yaml'
    echo "$RESULT"
    echo '```'
} > "$OUTPUT_FILE"

/usr/bin/touch "$MARKER"

exit 0
