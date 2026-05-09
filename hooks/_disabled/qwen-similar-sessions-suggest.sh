#!/bin/zsh
# UserPromptSubmit: 첫 프롬프트가 작업 키워드 포함 시 Obsidian Sessions/ 안 유사 과거 세션 grep 후 stdout 출력
#
# 목적: 새 작업 시작 직후 과거 같은 키워드/프로젝트 세션 노트 상위 3개 노출 → 컨텍스트 회수
# 효과: claude-mem/local-rag 호출 전에도 세션 노트 단계에서 1차 회수, 같은 작업 반복 방지
#
# 동작 조건:
#   1. 프롬프트 길이 >= 50자
#   2. 작업 키워드 정규식 매칭 (구현/만들어/추가/디버그/버그/에러/만들/작성/배포/마이그레이션)
#   3. 세션당 1회만 (~/.claude/cache/similar-suggested/{session_id}.done 마커)
#   4. ~/Workspace/weaversbrain 디렉토리 존재 시에만
#
# 주의:
#   - Ollama 호출 안 함 (grep만)
#   - 매칭 0건이면 조용히 종료

: "${HOME:?}"

VAULT_DIR="$HOME/Workspace/weaversbrain/weaversbrain"
SESSIONS_DIR="$VAULT_DIR/Sessions"
CACHE_DIR="$HOME/.claude/cache/similar-suggested"

# Vault 없으면 종료
[ -d "$SESSIONS_DIR" ] || exit 0

INPUT=$(cat)

# session_id 추출 (마커용)
SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown-$(date +%s)"

# 마커 있으면 skip (세션당 1회)
mkdir -p "$CACHE_DIR" 2>/dev/null
MARKER="$CACHE_DIR/${SESSION_ID}.done"
[ -f "$MARKER" ] && exit 0

# prompt 추출
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 4000)

# 길이 < 50자면 종료
PROMPT_LEN=${#PROMPT}
[ "$PROMPT_LEN" -lt 50 ] && exit 0

# 작업 키워드 매칭 안 되면 종료
if ! echo "$PROMPT" | grep -qE '(구현|만들어|추가|디버그|버그|에러|만들|작성|배포|마이그레이션)'; then
    exit 0
fi

# cwd 추출 → 프로젝트명 추정 (마지막 path segment)
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
PROJECT_NAME=""
if [ -n "$CWD" ]; then
    PROJECT_NAME=$(basename "$CWD")
fi

# 검색 키워드: 프롬프트에서 한글/영문 4글자+ 토큰 상위 3개 추출
KEYWORDS=$(echo "$PROMPT" | grep -oE '[가-힣A-Za-z][가-힣A-Za-z0-9_-]{3,}' | head -5 | tr '\n' '|' | sed 's/|$//')

# 검색 키워드 비면 종료
[ -z "$KEYWORDS" ] && exit 0

# 매칭 grep — 파일명+본문 모두 검색 (Sessions 하위 모든 .md 재귀)
# 파일명에 프로젝트명 포함되면 가중치 우선 정렬, 그 외는 최신순
TMP_RESULT=$(mktemp)
TMP_FILELIST=$(mktemp)
trap "rm -f $TMP_RESULT $TMP_FILELIST" EXIT

# 모든 .md 파일 목록 (재귀)
find "$SESSIONS_DIR" -type f -name "*.md" 2>/dev/null > "$TMP_FILELIST"

# 1단계: 프로젝트명 매칭 파일 우선
if [ -n "$PROJECT_NAME" ]; then
    grep -i "$PROJECT_NAME" "$TMP_FILELIST" | sort -r | head -10 >> "$TMP_RESULT"
fi

# 2단계: 키워드 매칭 (파일 본문 grep, 파일 목록을 xargs로 전달)
if [ -s "$TMP_FILELIST" ]; then
    xargs -I{} grep -lE "$KEYWORDS" "{}" < "$TMP_FILELIST" 2>/dev/null | sort -r | head -20 >> "$TMP_RESULT"
fi

# 중복 제거 후 상위 3개
MATCHED=$(awk '!seen[$0]++' "$TMP_RESULT" | head -3)

# 매칭 0건이면 조용히 종료
[ -z "$MATCHED" ] && { touch "$MARKER"; exit 0; }

# stdout 출력 (Claude 컨텍스트 주입)
echo "💡 유사한 과거 세션 발견 (참고 가능):"
echo "$MATCHED" | while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    BASENAME=$(basename "$FILE" .md)
    # 파일명에서 날짜+제목 추출 (YYYY-MM-DD-... 패턴 가정)
    DATE_PART=$(echo "$BASENAME" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
    TITLE_PART=$(echo "$BASENAME" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')
    # 본문 첫 헤딩(# ...) 1줄 추출 (요약 대용)
    FIRST_HEADING=$(grep -m1 -E '^#[^#]' "$FILE" 2>/dev/null | sed 's/^#[[:space:]]*//' | head -c 60)
    if [ -n "$FIRST_HEADING" ]; then
        echo "  • ${DATE_PART:-?} — ${TITLE_PART}: ${FIRST_HEADING}"
    else
        echo "  • ${DATE_PART:-?} — ${TITLE_PART}"
    fi
done
echo ""
echo "\`Read <경로>\`로 확인 가능. (경로 prefix: $SESSIONS_DIR/)"

# 마커 생성
touch "$MARKER"
exit 0
