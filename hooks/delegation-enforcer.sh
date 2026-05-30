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

    # 30줄 미만: 통과
    if [ "$LINE_COUNT" -lt 30 ]; then
      exit 0
    fi

    # 30~49줄: 권고만 (stdout, 비차단)
    if [ "$LINE_COUNT" -lt 50 ]; then
      cat <<EOF
[위임 권장] $FILE_PATH 에 ${LINE_COUNT}줄 변경 감지

대량 코드 작성은 Codex에 위임이 더 효율적:
  - Codex 호출: Skill(ask-codex) 또는 codex exec (CLI — MCP는 미사용)
  - 대량 구현/리팩터: codex:rescue (write 모드)
  - Gemini 1M 컨텍스트: Skill(ask-gemini) — 코드베이스 영향도/대량 스캔
  - Claude는 판단/리뷰/통합에 집중
EOF
      exit 0
    fi

    # 50줄+: 차단 (exit 2 → Claude에게 차단 사유 전달)
    # 우회: 사용자가 "직접 구현해" 명시했거나, 자동 생성/마이그레이션 등 정당한 사유면
    #       Claude가 stderr 메시지를 보고 다음 턴에서 사용자 확인 받아야 함
    cat >&2 <<EOF
[BLOCKED] $FILE_PATH 에 ${LINE_COUNT}줄 직접 작성 시도 차단됨

50줄+ 코드 작성은 토큰 비효율 — 다음 중 하나 필요:
  1. Codex 위임:    Skill(ask-codex) / codex exec (분석) / codex:rescue (대량 구현)
  2. Gemini 위임:   Skill(ask-gemini)  (대량 보일러플레이트/스캔)
  3. 사용자 명시:   "직접 구현해" / "직접 작성해" 발화 시 우회 가능
  4. 분할 작성:    50줄 미만 Edit 여러 번으로 나누기

직접 구현이 명확히 더 나은 경우(긴급/단순 패치)만 사용자 확인 후 진행.
EOF
    exit 2

    ;;
esac

exit 0
