#!/bin/zsh
# UserPromptSubmit: 사용자 프롬프트에서 파이프라인 키워드 감지 시
# git diff로 변경 파일 수 카운트 → S/M/L 자동 판정 → additionalContext 주입
#
# 판정 기준 (workflows/pipeline.md):
#   S: 1~2 files
#   M: 3~5 files
#   L: 6+ files OR 아키텍처 키워드 포함
#
# 사용자가 "L 규모로", "M으로" 명시하면 그 판정이 우선

: "${HOME:?}"

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 2000)

# 사용자가 이미 규모 명시하면 스킵
if echo "$PROMPT" | grep -qiE '(L 규모|M 규모|S 규모|large 규모|규모: ?[SML])'; then
    exit 0
fi

# 파이프라인 트리거 키워드 없으면 스킵
if ! echo "$PROMPT" | grep -qiE '(backend|백엔드|frontend|프론트|fullstack|풀스택|구현|리팩터|마이그레이션|@dev)'; then
    exit 0
fi

CWD=$(pwd)
cd "$CWD" 2>/dev/null || exit 0

# git 저장소 아니면 스킵
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# unstaged + staged + untracked 변경 파일 수
CHANGED=$(git status --porcelain 2>/dev/null | grep -cE '\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb|swift|vue|svelte)$')

# 0이면 미수정 상태 — diff HEAD~1 시도 (브랜치 작업 중일 수 있음)
if [ "$CHANGED" -eq 0 ]; then
    BASE=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null || echo "")
    if [ -n "$BASE" ]; then
        CHANGED=$(git diff --name-only "$BASE"..HEAD 2>/dev/null | grep -cE '\.(py|ts|tsx|js|jsx|kt|java|php|go|rs|rb|swift|vue|svelte)$')
    fi
fi

# 아키텍처 키워드 → 무조건 L
ARCH=""
if echo "$PROMPT" | grep -qiE '(아키텍처|architecture|모듈 분리|패키지 재구성|breaking change|API 인터페이스 변경)'; then
    ARCH="(아키텍처 변경 키워드 감지)"
    SCALE="L"
elif [ "$CHANGED" -ge 6 ]; then
    SCALE="L"
elif [ "$CHANGED" -ge 3 ]; then
    SCALE="M"
elif [ "$CHANGED" -ge 1 ]; then
    SCALE="S"
else
    # 변경 없음 — 신규 작업으로 간주, 기본 S
    SCALE="S(추정)"
fi

cat <<EOF
[규모 자동 판별] $SCALE — 변경 파일 ${CHANGED}개 ${ARCH}
파이프라인 적용:
  S: Gemini 스캔 → developer (researcher·planner 생략)
  M: Gemini 스캔 → researcher → 병렬 구현
  L: Gemini 스캔 → researcher + planner → 병렬 구현
명시 변경: "S 규모로" / "M 규모로" / "L 규모로" 프롬프트에 포함
EOF

exit 0
