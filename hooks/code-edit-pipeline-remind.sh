#!/bin/zsh
# PreToolUse: Edit/Write로 코드 파일 수정 시 파이프라인 리마인더
# exit 0 + stdout = 비차단 리마인더

: "${HOME:?}"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

case "$FILE_PATH" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.kt|*.java|*.php|*.go|*.rs|*.rb|*.swift|*.vue|*.svelte)
    if echo "$FILE_PATH" | grep -qE '(\.claude/|node_modules/|__pycache__|\.git/|test_|_test\.|spec\.)'; then
      exit 0
    fi

    # 프로젝트명 추출
    PROJECT_NAME=$(echo "$FILE_PATH" | sed -n 's|.*/Workspace/\([^/]*\)/.*|\1|p')

    MSG="코드 파일 수정 감지: $FILE_PATH — 파이프라인 규칙 확인 (developer → 병렬(code-reviewer + codex:review) → tester)"

    # 캐시된 Gemini 스캔 결과 안내
    if [ -n "$PROJECT_NAME" ]; then
      GEMINI_SCAN="$HOME/.claude/cache/gemini/${PROJECT_NAME}-scan.md"
      if [ -f "$GEMINI_SCAN" ]; then
        FILE_AGE=$(( $(date +%s) - $(stat -f %m "$GEMINI_SCAN" 2>/dev/null || echo 0) ))
        if [ "$FILE_AGE" -lt 3600 ]; then
          MSG="${MSG}\n[Gemini 컨텍스트] 최근 스캔 결과: cat ${GEMINI_SCAN}"
        fi
      fi
    fi

    echo "$MSG"
    ;;
esac

exit 0
