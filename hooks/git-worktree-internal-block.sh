#!/bin/zsh
# PreToolUse(Bash): git worktree add 가 현재 working tree 내부 경로를 가리키면 차단
#
# 차단 이유:
#   부모 working tree 내부에 worktree 를 만들면 git add 시 gitlink(mode 160000)로
#   자동 등록되어 status 가 영구 오염된다 (2026-05-15 incident — speakingmax-study-admin).
#   안전한 경로는 저장소 외부 (예: /tmp/worktrees/, sibling 디렉토리).
#
# 결함 회피:
#   - `echo '...git worktree add...'` 같이 명령 안 인자 문자열은 무시
#   - shell sub-command 도 검사 (|, &&, ;, $() 등)
#   - 토큰의 첫 단어가 정확히 `git`, 둘째 `worktree`, 셋째 `add` 일 때만 차단
#
# exit 0 = 통과 / exit 2 = 차단 (stderr 메시지를 Claude 가 받아서 사용자에 전달)

: "${HOME:?}"

source "$HOME/.claude/hooks/_lib/outcome-log.sh" 2>/dev/null

INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

CMD=$(python3 - "$INPUT_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    pass
PYEOF
)

[ -z "$CMD" ] && exit 0

# 빠른 사전 필터 — 'worktree' 와 'add' 가 명령 어디에도 없으면 즉시 통과
echo "$CMD" | grep -q "worktree" || exit 0
echo "$CMD" | grep -q "add" || exit 0

# Python 으로 정밀 파싱 — shell sub-command 분해 + 토큰 첫 3 단어 매칭
RESULT=$(python3 - "$CMD" <<'PYEOF'
import sys, shlex, re

raw = sys.argv[1]

# shell separator 로 sub-command 분리. quote 안의 ; | && 는 건드리면 안 되므로
# 토큰화 후 separator 토큰 위치로 split 한다.
try:
    tokens = shlex.split(raw, posix=True, comments=False)
except Exception:
    # 파싱 실패 — 안전쪽으로 통과 (block 누락이 false block 보다 나음)
    sys.exit(0)

# shlex 는 ; | && 같은 메타를 separate token 으로 안 만든다 (quote 처리 후 데이터로 보관).
# 그래서 raw 문자열을 직접 segment 화 한다.
# 다만 quote 안의 separator 는 무시해야 함 — split_command 수동 구현.
def split_segments(s):
    """`;` `&&` `||` `|` 로 segment 분할, quote 안 무시."""
    segments = []
    buf = []
    i = 0
    in_single = False
    in_double = False
    while i < len(s):
        c = s[i]
        if c == "'" and not in_double:
            in_single = not in_single
            buf.append(c)
            i += 1
            continue
        if c == '"' and not in_single:
            in_double = not in_double
            buf.append(c)
            i += 1
            continue
        if not in_single and not in_double:
            # 2-char separators
            if s[i:i+2] in ("&&", "||"):
                segments.append("".join(buf).strip())
                buf = []
                i += 2
                continue
            if c in (";", "|", "\n"):
                segments.append("".join(buf).strip())
                buf = []
                i += 1
                continue
        buf.append(c)
        i += 1
    if buf:
        segments.append("".join(buf).strip())
    return [seg for seg in segments if seg]

# command substitution $(...) 와 `...` 도 안에서 git worktree add 가 있을 수 있으니 추출
def extract_substitutions(s):
    """$(...) 와 backtick 내부 추출."""
    out = []
    # $(...) — 중첩 무시 (단순)
    for m in re.finditer(r'\$\(([^()]*(?:\([^()]*\)[^()]*)*)\)', s):
        out.append(m.group(1))
    for m in re.finditer(r'`([^`]+)`', s):
        out.append(m.group(1))
    return out

candidates = []
for seg in split_segments(raw):
    candidates.append(seg)
    candidates.extend(extract_substitutions(seg))

# 각 candidate 에서 첫 3 단어가 `git worktree add` 인지 검사
for cmd in candidates:
    try:
        toks = shlex.split(cmd, posix=True, comments=False)
    except Exception:
        continue
    if len(toks) < 3:
        continue
    if toks[0] != "git" or toks[1] != "worktree" or toks[2] != "add":
        continue
    # path 추출 — opt 스킵
    opts_with_arg = {"-b", "-B", "--lock-reason", "--reason"}
    path = None
    i = 3
    while i < len(toks):
        t = toks[i]
        if t in opts_with_arg:
            i += 2
            continue
        if t.startswith("-"):
            i += 1
            continue
        path = t
        break
    if path:
        print(path)
        sys.exit(0)

# 매칭 없음
sys.exit(1)
PYEOF
)

if [ -z "$RESULT" ]; then
  outcome_log "git-worktree-internal-block" "pass" "" "no-match" 2>/dev/null
  exit 0
fi

WT_PATH="$RESULT"

# 절대경로 resolve (존재 안 해도 OK)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
if [[ "$WT_PATH" = /* ]]; then
  ABS_PATH="$WT_PATH"
else
  ABS_PATH="$PROJECT_DIR/$WT_PATH"
fi

ABS_PATH=$(python3 -c "import os, sys; print(os.path.normpath(sys.argv[1]))" "$ABS_PATH")
PROJECT_DIR=$(python3 -c "import os, sys; print(os.path.normpath(sys.argv[1]))" "$PROJECT_DIR")
PROJECT_BASE=$(basename "$PROJECT_DIR")
PROJECT_PARENT=$(dirname "$PROJECT_DIR")
WT_BASE=$(basename "$WT_PATH")

# PROJECT_DIR/ 로 시작하면 내부 = 차단
case "$ABS_PATH/" in
  "$PROJECT_DIR"/*)
    cat >&2 <<MSG
🚫 git worktree add 차단 — 부모 working tree 내부 경로

프로젝트: $PROJECT_BASE  ($PROJECT_DIR)
대상 경로: $ABS_PATH

이유:
  부모 working tree 안에 worktree 를 만들면 git add 시 gitlink(mode 160000)로
  자동 등록되어 status 가 영구 오염됩니다 (2026-05-15 incident).

권장 경로 (저장소 외부):
  - /tmp/worktrees/$WT_BASE
  - $PROJECT_PARENT/$PROJECT_BASE.wt-$WT_BASE
  - ~/.cache/claude-worktrees/$PROJECT_BASE/$WT_BASE

차단 우회가 정말 필요하면 사용자가 직접 명령 실행하세요.
MSG
    outcome_log "git-worktree-internal-block" "block" "$ABS_PATH" "internal-worktree" 2>/dev/null
    exit 2
    ;;
esac

outcome_log "git-worktree-internal-block" "pass" "" "external-worktree" 2>/dev/null
exit 0
