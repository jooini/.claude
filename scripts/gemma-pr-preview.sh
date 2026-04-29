#!/bin/bash
# PR 올리기 전 셀프 Q&A — Gemma가 리뷰어 입장에서 까칠한 질문 10개 생성
#
# 사용법:
#   cd <프로젝트>
#   ~/.claude/scripts/gemma-pr-preview.sh
#   ~/.claude/scripts/gemma-pr-preview.sh main  # base 브랜치 지정
#   ~/.claude/scripts/gemma-pr-preview.sh --staged  # staged만
#
# 출력: 10개 질문 + 난이도 + 카테고리

set -euo pipefail

OLLAMA="${OLLAMA_HOST_LAN:-leonard.local:11434}"
MODEL="${GEMMA_MODEL:-gemma4:e4b}"
LOGGER="$HOME/.claude/scripts/gemma-logger.sh"

# git 리포 확인
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "❌ git 리포가 아님" >&2
    exit 1
fi

MODE="branch"
BASE_BRANCH=""

# 인자 파싱
if [ $# -ge 1 ]; then
    case "$1" in
        --staged)
            MODE="staged"
            ;;
        --help|-h)
            echo "사용: $0 [base_branch|--staged]"
            echo "  기본: 현재 브랜치와 origin/main(또는 master) diff"
            echo "  --staged: staged 변경만"
            echo "  <브랜치명>: 지정한 base와 diff"
            exit 0
            ;;
        *)
            BASE_BRANCH="$1"
            ;;
    esac
fi

# base 자동 감지
if [ -z "$BASE_BRANCH" ] && [ "$MODE" = "branch" ]; then
    for b in main master develop; do
        if git rev-parse --verify "origin/$b" >/dev/null 2>&1; then
            BASE_BRANCH="origin/$b"
            break
        fi
    done
    if [ -z "$BASE_BRANCH" ]; then
        echo "❌ base 브랜치 자동 감지 실패. 인자로 지정 필요." >&2
        exit 1
    fi
fi

CURRENT_BRANCH=$(git branch --show-current)
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")

echo "🔍 프로젝트: $PROJECT_NAME"
if [ "$MODE" = "staged" ]; then
    echo "📋 모드: staged 변경"
    DIFF=$(git diff --staged)
    COMMITS=""
    CHANGED_FILES=$(git diff --staged --name-only)
else
    echo "📋 모드: $CURRENT_BRANCH vs $BASE_BRANCH"
    DIFF=$(git diff "$BASE_BRANCH"...HEAD)
    COMMITS=$(git log "$BASE_BRANCH"..HEAD --oneline)
    CHANGED_FILES=$(git diff "$BASE_BRANCH"...HEAD --name-only)
fi

if [ -z "$DIFF" ]; then
    echo "❌ diff 비어있음" >&2
    exit 1
fi

FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c . || echo 0)
LINE_COUNT=$(echo "$DIFF" | wc -l | tr -d ' ')

echo "   파일: ${FILE_COUNT}개, diff 라인: ${LINE_COUNT}"
echo ""

# 큰 diff는 잘라냄 (프롬프트 한도)
MAX_DIFF_LINES=800
if [ "$LINE_COUNT" -gt "$MAX_DIFF_LINES" ]; then
    echo "⚠️  diff가 ${LINE_COUNT}줄. 앞 ${MAX_DIFF_LINES}줄만 사용" >&2
    DIFF=$(echo "$DIFF" | head -n "$MAX_DIFF_LINES")
fi

# 프롬프트 조립
PROMPT="너는 까칠한 시니어 개발자다. 아래 PR을 리뷰하기 전에, 작성자가 스스로 답해야 할 질문을 던져야 한다.

# 프로젝트: $PROJECT_NAME
# 브랜치: $CURRENT_BRANCH

## 변경된 파일 (${FILE_COUNT}개)
$CHANGED_FILES

## 커밋 히스토리
$COMMITS

## Diff
\`\`\`diff
$DIFF
\`\`\`

---

위 변경사항을 보고 다음을 수행해라:

**10개의 날카로운 질문을 생성해라.** 질문은 다음 카테고리를 섞어서:

1. **설계 의도** (2개) — 왜 이렇게 만들었는지, 다른 대안은 검토했는지
2. **엣지 케이스** (3개) — 빠뜨린 상황 (null, 빈 배열, 동시성, 네트워크 실패 등)
3. **테스트** (2개) — 테스트 커버리지, 테스트 하나 제시
4. **보안/성능** (1개) — 주입 공격, N+1, 메모리 누수 등
5. **유지보수** (1개) — 이 코드 6개월 뒤 너 말고 누가 읽어도 이해되나
6. **제거 가능성** (1개) — 안 필요한 코드 있나

형식:
\`\`\`
## Q1. [카테고리] 질문 내용
   난이도: ★★★ (별 1~3개)
   힌트: 답할 때 확인해야 할 것

## Q2. ...
\`\`\`

톤: 공격적이지 말고 실용적으로. 진짜 리뷰어가 물어볼 법한 것만. 교과서 질문 금지.
한글로 작성."

echo "🤖 Gemma에게 리뷰어 역할 시키는 중..." >&2
echo ""

# 로거 경유
"$LOGGER" "pr-preview" "$MODEL" "$PROMPT" 2500 0.5
