#!/bin/zsh
# SessionStart: 자주 쓰는 긴 명령을 alias 후보로 제안 (주 1회)
#
# 동작:
#   1. 캐시 mtime 7일 이내면 skip
#   2. ~/.zsh_history (extended) + ~/.bash_history 합쳐서 마지막 5000줄
#   3. 명령 빈도 카운트
#   4. 이미 alias 등록된 명령 제외
#   5. 빈도 20+ AND 길이 30+ 만 후보
#   6. 상위 10개 한국어 출력
#   7. last-run touch
#
# 한계:
#   - Ollama 호출 안 함 (단순 통계)
#   - alias 이름은 단어 두 개 합성 추측 — 사용자가 직접 수정 권장
#   - zsh extended history 형식 가정 (": <ts>:<elapsed>;<cmd>")
#   - bash_history 는 한 줄 = 한 명령으로 가정

: "${HOME:?}"

INPUT=$(cat)

# matcher: startup 만 처리
MATCHER=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('matcher', ''))
except Exception:
    pass
" 2>/dev/null)

if [ "$MATCHER" != "startup" ]; then
    exit 0
fi

CACHE_DIR="$HOME/.claude/cache/qwen-alias-suggest"
LAST_RUN="$CACHE_DIR/last-run"
mkdir -p "$CACHE_DIR"

# 7일 이내면 skip (mtime 검사)
if [ -f "$LAST_RUN" ]; then
    if /usr/bin/find "$LAST_RUN" -mtime -7 -print 2>/dev/null | grep -q .; then
        exit 0
    fi
fi

ZSH_HIST="$HOME/.zsh_history"
BASH_HIST="$HOME/.bash_history"

# 양쪽 다 없으면 의미 없음
if [ ! -f "$ZSH_HIST" ] && [ ! -f "$BASH_HIST" ]; then
    exit 0
fi

# 명령 추출 (마지막 5000줄)
TMP_CMDS=$(/usr/bin/mktemp -t qwen-alias-cmds.XXXXXX) || exit 0
trap '/bin/rm -f "$TMP_CMDS" "$TMP_ALIAS_NAMES"' EXIT

# macOS BSD awk 가 multibyte 약함 → LC_ALL=C 로 바이트 모드 처리
export LC_ALL=C

# zsh_history: extended 형식 ": <ts>:<elapsed>;<cmd>" — ; 이후가 명령
if [ -f "$ZSH_HIST" ]; then
    /usr/bin/tail -n 5000 "$ZSH_HIST" 2>/dev/null \
        | /usr/bin/awk -F';' 'NF>=2 { sub(/^[^;]*;/, ""); print }' \
        >> "$TMP_CMDS"
fi

# bash_history: 한 줄 = 한 명령
if [ -f "$BASH_HIST" ]; then
    /usr/bin/tail -n 5000 "$BASH_HIST" 2>/dev/null >> "$TMP_CMDS"
fi

# 비어 있으면 종료
if [ ! -s "$TMP_CMDS" ]; then
    /usr/bin/touch "$LAST_RUN"
    exit 0
fi

# 이미 등록된 alias 이름 수집 (zsh -ic 로 모든 alias 가져옴)
TMP_ALIAS_NAMES=$(/usr/bin/mktemp -t qwen-alias-names.XXXXXX) || exit 0
zsh -ic 'alias' 2>/dev/null \
    | /usr/bin/awk -F= '{print $1}' \
    | /usr/bin/sed 's/^alias //' \
    | /usr/bin/awk 'NF==1 {print}' \
    > "$TMP_ALIAS_NAMES"

# alias 우회: alias 정의된 첫 단어 명령은 제외
# 명령의 "첫 토큰" 이 alias 이름과 일치하면 후보 제외
# (예: 'cd -' 이 alias 면 'cd' 로 시작하는 명령은 모두 alias 우회로 간주)

CANDIDATES=$(
    /usr/bin/awk '
        # 앞뒤 공백 제거
        { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
        # 빈 줄 / 너무 짧음 제외
        length($0) >= 30 { print }
    ' "$TMP_CMDS" \
    | /usr/bin/sort \
    | /usr/bin/uniq -c \
    | /usr/bin/sort -rn \
    | /usr/bin/awk '$1 >= 20'
)

if [ -z "$CANDIDATES" ]; then
    /usr/bin/touch "$LAST_RUN"
    exit 0
fi

# alias 이름 필터: 첫 토큰이 alias 면 skip
FILTERED=$(echo "$CANDIDATES" | /usr/bin/awk -v alias_file="$TMP_ALIAS_NAMES" '
    BEGIN {
        while ((getline line < alias_file) > 0) {
            gsub(/[[:space:]]/, "", line)
            if (line != "") aliases[line] = 1
        }
        close(alias_file)
    }
    {
        # $1 = count, 나머지 = command
        count = $1
        $1 = ""
        sub(/^[[:space:]]+/, "")
        cmd = $0
        # 첫 토큰
        first = cmd
        sub(/[[:space:]].*$/, "", first)
        if (first in aliases) next
        printf "%6d|%s\n", count, cmd
    }
' | /usr/bin/head -10)

if [ -z "$FILTERED" ]; then
    /usr/bin/touch "$LAST_RUN"
    exit 0
fi

# 출력 — alias 이름은 첫 두 토큰 합성으로 추측
echo ""
echo "📊 자주 쓰는 명령 alias 후보 (지난 5000줄 기준):"
echo ""

echo "$FILTERED" | /usr/bin/awk -F'|' '
    {
        count = $1; sub(/^[[:space:]]+/, "", count)
        cmd = $2
        # alias 이름 후보: 첫 두 토큰 + "-" 으로 연결, 영숫자만
        n = split(cmd, parts, /[[:space:]]+/)
        name = ""
        if (n >= 2) {
            t1 = parts[1]; gsub(/[^a-zA-Z0-9]/, "", t1)
            t2 = parts[2]; gsub(/[^a-zA-Z0-9]/, "", t2)
            if (t1 != "" && t2 != "") name = t1 "-" t2
            else if (t1 != "") name = t1 "-cmd"
            else name = "my-cmd"
        } else {
            name = parts[1]; gsub(/[^a-zA-Z0-9]/, "", name)
            if (name == "") name = "my-cmd"
            name = name "-cmd"
        }
        printf "  %s회: %s\n", count, cmd
        printf "    → alias %s='\''%s'\''\n\n", tolower(name), cmd
    }
'

echo "추가 원하면 ~/.zshrc 에 직접 등록 (이름은 취향대로 수정)"
echo ""

/usr/bin/touch "$LAST_RUN"
exit 0
