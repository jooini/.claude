#!/bin/zsh
# PreToolUse(Bash): git commit 감지 → staged diff를 ini에 넘겨 커밋 메시지 초안 생성
# exit 0 + stdout = 비차단 힌트 (사용자/Claude가 최종 결정)
# 실패/서버다운/타임아웃 시 즉시 스킵 (원본 커밋 흐름 블로킹 없음)

: "${HOME:?}"

QWEN="$HOME/.local/bin/ini"
CACHE_DIR="$HOME/.claude/cache/gemma"
mkdir -p "$CACHE_DIR"

# ini 미설치 시 즉시 스킵
[ -x "$QWEN" ] || exit 0

# 회사 LAN 외부에서 호출 시 즉시 skip (TCP 1초 캐시 5분)
source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')

# git commit 명령인지 확인
if ! echo "$COMMAND" | grep -q 'git commit'; then
    exit 0
fi

# 이미 -m "메시지"가 있는 경우 = 실제 커밋 실행 단계 → 스킵 (검증 훅이 처리)
if echo "$COMMAND" | grep -qE '\-m[[:space:]]+(\\?["'"'"'])'; then
    exit 0
fi

# heredoc 커밋도 이미 메시지 있음 → 스킵
if echo "$COMMAND" | grep -q '<<.*EOF'; then
    exit 0
fi

# git repo 확인
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# staged 변경 확인
STAGED=$(git diff --cached --name-only 2>/dev/null)
if [ -z "$STAGED" ]; then
    exit 0
fi

# 민감 파일 스테이징 감지 시 호출 스킵 (유출 위험)
if echo "$STAGED" | grep -qE '(\.env$|\.env\.|credentials|\.pem$|\.key$|secrets?\.(json|yaml|yml))'; then
    echo "[커밋 초안 스킵] 민감 파일 스테이징 감지 — ini 호출 안 함"
    exit 0
fi

PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-commit-draft.md"

# 1분 이내 캐시 재사용 (같은 diff 반복 방지)
DIFF_HASH=$(git diff --cached 2>/dev/null | md5 -q 2>/dev/null || git diff --cached 2>/dev/null | md5sum 2>/dev/null | awk '{print $1}')
CACHED_HASH_FILE="$CACHE_DIR/${PROJECT_NAME}-commit-draft.hash"

if [ -f "$OUTPUT_FILE" ] && [ -f "$CACHED_HASH_FILE" ]; then
    CACHED_HASH=$(cat "$CACHED_HASH_FILE" 2>/dev/null)
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
    if [ "$CACHED_HASH" = "$DIFF_HASH" ] && [ "$FILE_AGE" -lt 60 ]; then
        echo "[커밋 메시지 초안 (ini 캐시)]"
        echo "---"
        cat "$OUTPUT_FILE"
        echo "---"
        echo "위 초안 참고하되 최종 메시지는 직접 결정."
        exit 0
    fi
fi

# staged diff + 파일 목록 수집 (500줄 컷)
DIFF_TRUNCATED=$(git diff --cached 2>/dev/null | head -500)
STAT=$(git diff --cached --stat 2>/dev/null)

if [ -z "$DIFF_TRUNCATED" ]; then
    exit 0
fi

echo "[ini 커밋 초안 생성 중] 최대 15초..."

# ini stdin pipe — commit 페르소나가 모델/시스템 프롬프트 자동 적용
PROMPT=$(printf '변경 파일 통계:\n%s\n\n변경 내용:\n%s' "$STAT" "$DIFF_TRUNCATED")

RESULT=$(echo "$PROMPT" | "$QWEN" -p - --profile commit --num-ctx 8192 2>/dev/null)
EXIT=$?

if [ "$EXIT" -eq 0 ] && [ -n "$RESULT" ]; then
    echo "$RESULT" > "$OUTPUT_FILE"
    echo "$DIFF_HASH" > "$CACHED_HASH_FILE"
    echo "[커밋 메시지 초안 (ini)]"
    echo "---"
    echo "$RESULT"
    echo "---"
    echo "위 초안 참고하되 최종 메시지는 직접 결정."
fi

exit 0
