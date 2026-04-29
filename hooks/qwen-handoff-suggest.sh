#!/bin/zsh
# Stop hook: 세션 종료 시점에 핸드오프 가치를 평가하여 사용자에게 /handoff 제안 출력
# 비차단 — 조건 미충족이면 stdout 비움. Ollama/qwen-cli 호출 없음(정규식만)
# 조건 (모두 AND):
#   1) jsonl 라인 수 >= 100
#   2) 미커밋 변경 또는 마지막 50건 user 메시지에 "내일/다음에/이어서" 등 미완료 신호
#   3) 같은 날 동일 세션에 마커 없음

: "${HOME:?}"

MIN_LINES=100
TAIL_USER_LIMIT=50
MARKER_DIR="$HOME/.claude/cache/handoff-suggested"

INPUT=$(cat 2>/dev/null)

# 빈 입력이면 즉시 종료
if [ -z "$INPUT" ]; then
    exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# 중복 방지 마커 (날짜 포함 — 같은 날 한 세션 1회만)
mkdir -p "$MARKER_DIR" 2>/dev/null
TODAY=$(date +%Y-%m-%d)
MARKER="$MARKER_DIR/${TODAY}-${SESSION_ID}.done"
if [ -f "$MARKER" ]; then
    exit 0
fi

# session_id로 jsonl 찾기
JSONL=""
PROJECT_DIR=""
for dir in "$HOME/.claude/projects"/*/; do
    candidate="${dir}${SESSION_ID}.jsonl"
    if [ -f "$candidate" ]; then
        JSONL="$candidate"
        PROJECT_DIR="$dir"
        break
    fi
done

# 가짜 session_id 또는 jsonl 없음 -> 조용히 종료 (마커 남기지 않음)
if [ -z "$JSONL" ] || [ ! -f "$JSONL" ]; then
    exit 0
fi

# 라인 수 체크
LINE_COUNT=$(/usr/bin/wc -l < "$JSONL" 2>/dev/null | /usr/bin/tr -d ' ')
if [ -z "$LINE_COUNT" ]; then
    LINE_COUNT=0
fi

if [ "$LINE_COUNT" -lt "$MIN_LINES" ]; then
    # 작업량 부족 — 마커 남기지 않음 (다음 Stop에서 다시 평가)
    exit 0
fi

# 미완료 신호 1: 미커밋 변경 (프로젝트 cwd 추정 후 git status)
# project 디렉토리명 -> 실제 경로 복원
HAS_UNCOMMITTED=0
if [ -n "$PROJECT_DIR" ]; then
    # 디렉토리명 형식: -Users-leonard-Workspace-foo -> /Users/leonard/Workspace/foo
    DIR_NAME=$(basename "$PROJECT_DIR")
    REAL_PATH=$(printf '%s' "$DIR_NAME" | /usr/bin/sed 's/^-/\//;s/-/\//g')
    if [ -d "$REAL_PATH/.git" ] || [ -f "$REAL_PATH/.git" ]; then
        if /usr/bin/git -C "$REAL_PATH" status --porcelain 2>/dev/null | /usr/bin/grep -q .; then
            HAS_UNCOMMITTED=1
        fi
    fi
fi

# 미완료 신호 2: 마지막 N건 user 메시지에 키워드
export JSONL_PATH="$JSONL"
export TAIL_LIMIT="$TAIL_USER_LIMIT"
HAS_KEYWORD=$(/usr/bin/python3 <<'PYEOF'
import json, os, re

path = os.environ["JSONL_PATH"]
limit = int(os.environ.get("TAIL_LIMIT", "50"))

# 미완료 흔적 키워드 — 한국어 + 영어 일반 표현
patterns = [
    r"내일",
    r"다음\s*에",
    r"다음\s*세션",
    r"이어서",
    r"이어\s*하기",
    r"나중에",
    r"이따가",
    r"잠시\s*후",
    r"일단\s*(여기|중단|멈)",
    r"퇴근",
    r"to\s*be\s*continued",
    r"todo\s*:",
    r"미완(료|성)",
    r"중단(하|함|할)",
    r"보류",
    r"인계",
    r"핸드오프",
    r"handoff",
]

regex = re.compile("|".join(f"({p})" for p in patterns), re.IGNORECASE)

user_msgs = []
try:
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec.get("type") != "user":
                continue
            content = rec.get("message", {}).get("content", "")
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = " ".join(
                    c.get("text", "") for c in content
                    if isinstance(c, dict) and c.get("type") == "text"
                )
            else:
                text = ""
            text = (text or "").strip()
            # 시스템 reminder/tool result 같은 메타 메시지 배제
            if not text or text.startswith("<") or len(text) < 3:
                continue
            user_msgs.append(text)
except Exception:
    print("0")
    raise SystemExit

tail = user_msgs[-limit:] if len(user_msgs) > limit else user_msgs
for msg in tail:
    if regex.search(msg):
        print("1")
        break
else:
    print("0")
PYEOF
)

HAS_KEYWORD=${HAS_KEYWORD:-0}

# 두 신호 중 하나라도 있어야 트리거
if [ "$HAS_UNCOMMITTED" -eq 0 ] && [ "$HAS_KEYWORD" -ne 1 ]; then
    # 미완료 흔적 없음 — 마커 남겨 같은 날 재평가 방지
    /usr/bin/touch "$MARKER" 2>/dev/null
    exit 0
fi

# 핸드오프 출력 경로 예시
TODAY_MONTH=$(date +%Y-%m)
EXPECTED_PATH="$HOME/Workspace/weaversbrain/weaversbrain/Sessions/${TODAY_MONTH}/$(date +%Y-%m-%d-%H%M)-{session-name}.md"

# 트리거 사유
REASONS=""
if [ "$HAS_UNCOMMITTED" -eq 1 ]; then
    REASONS="${REASONS}미커밋 변경"
fi
if [ "$HAS_KEYWORD" -eq 1 ]; then
    if [ -n "$REASONS" ]; then
        REASONS="${REASONS} + "
    fi
    REASONS="${REASONS}미완료 신호 키워드"
fi

# 사용자에게 제안
cat <<EOF

핸드오프 제안
  이번 세션에 작업량이 많고 미완료 흔적이 있습니다.
  - 라인 수: ${LINE_COUNT}
  - 트리거: ${REASONS}
  다음 세션을 위해 /handoff 또는 /session-handoff 실행 권장.
  예상 출력: ${EXPECTED_PATH}

EOF

# 마커 (당일 1회)
/usr/bin/touch "$MARKER" 2>/dev/null

exit 0
