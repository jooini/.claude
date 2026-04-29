#!/bin/zsh
# PreToolUse: Edit/Write로 코드 파일 수정 시 Codex/Gemini 위임 강제 안내
# 직접 구현 시 토큰 비효율 → 가능하면 Codex MCP에 위임
# stdout 비차단 경고 (사용자가 명시적으로 "직접 구현" 요청 시 무시)

: "${HOME:?}"

# stdin → 임시 파일 (echo/printf 백슬래시 해석 회피)
INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

PARSED=$(python3 - "$INPUT_FILE" <<'PYEOF'
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    inp = data.get("tool_input", {})
    fp = inp.get("file_path", "") or ""
    content = inp.get("content") or inp.get("new_string") or ""
    lines = len(content.splitlines()) if content else 0
    print(f"{fp}\t{lines}")
except Exception:
    print("\t0")
PYEOF
)

FILE_PATH="${PARSED%	*}"
LINE_COUNT="${PARSED##*	}"
LINE_COUNT=${LINE_COUNT:-0}

[ -z "$FILE_PATH" ] && exit 0

# 코드 파일만 검사
case "$FILE_PATH" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.kt|*.java|*.php|*.go|*.rs|*.rb|*.swift|*.vue|*.svelte|*.scala|*.cs)
    # 예외 경로 (설정/테스트/문서 등)
    if echo "$FILE_PATH" | grep -qE '(\.claude/|node_modules/|__pycache__|\.git/|test_|_test\.|spec\.|\.test\.|\.spec\.|/tests?/|/__tests__/)'; then
      exit 0
    fi

    # 30줄 미만 변경: 작은 수정이라 위임 비효율 → 통과
    if [ "$LINE_COUNT" -lt 30 ]; then
      exit 0
    fi

    cat <<EOF
[위임 권장] $FILE_PATH 에 ${LINE_COUNT}줄 변경 감지

대량 코드 작성은 Codex MCP에 위임이 더 효율적:
  - Codex 호출: mcp__codex-cli__codex 또는 Skill(ask-codex)
  - 병렬 구현 + 토큰 분산
  - Claude는 판단/리뷰/통합에 집중

직접 구현이 명확히 더 나은 경우(소규모/긴급/단순 패치)만 진행하고,
그 외는 Codex/codex-rescue 에이전트 호출 검토.
EOF

    ;;
esac

exit 0
