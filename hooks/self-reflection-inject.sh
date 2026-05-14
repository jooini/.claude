#!/usr/bin/env bash
# UserPromptSubmit 훅: 현재 프로젝트의 Self-Model 체크리스트를 stderr로 주입.
# 파일이 없거나 오래되면 조용히 종료.

set -u

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
SELF_MODEL_DIR="$HOME/.claude/self-model"

# 프로젝트 이름 추출 (~/Workspace/identity-hub → identity-hub)
PROJECT_NAME=""
case "$CWD" in
    "$HOME/Workspace"/*)
        PROJECT_NAME="${CWD#$HOME/Workspace/}"
        PROJECT_NAME="${PROJECT_NAME%%/*}"
        ;;
    "$HOME"/*)
        PROJECT_NAME="${CWD#$HOME/}"
        PROJECT_NAME="${PROJECT_NAME%%/*}"
        ;;
esac

[ -z "$PROJECT_NAME" ] && exit 0

MODEL_FILE="$SELF_MODEL_DIR/$PROJECT_NAME.md"
[ ! -f "$MODEL_FILE" ] && exit 0

# 30일 초과면 경고만
if [ "$(find "$MODEL_FILE" -mtime +30 -print 2>/dev/null)" ]; then
    echo "[self-model] $PROJECT_NAME 의 Self-Model이 30일+ 됨. /self-model rebuild 권장" >&2
fi

# 체크리스트 섹션만 추출 (다음 ## 또는 EOF까지)
CHECKLIST=$(awk '
/^## 답변 전 자기 점검 체크리스트/ {found=1; next}
found && /^## / {exit}
found && /^- \[ \]/ {print}
' "$MODEL_FILE" | head -6)

[ -z "$CHECKLIST" ] && exit 0

cat >&2 <<EOF
[Claude Self-Reflection — $PROJECT_NAME]
이 프로젝트에서 자주 틀린 패턴이 있습니다. 답변 전에 다음을 점검:
$CHECKLIST
EOF

exit 0
