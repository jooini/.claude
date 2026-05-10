#!/usr/bin/env bash
# Workspace Quick Clean Helper - 2026-05-07
# 상위 Dirty 프로젝트들의 상태를 점검하고 정리를 돕습니다.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECTS=(
    "docs"
    "maxai-admin-refactor"
    "speakingmax-study-insight"
    "dashboard-viewer"
)

echo -e "${BLUE}=== 워크스페이스 정리 가이드 (Recovery Mode) ===${NC}"
echo "오늘 분석된 상위 4대 프로젝트의 상태입니다."
echo ""

for proj in "${PROJECTS[@]}"; do
    path="$HOME/Workspace/$proj"
    if [ -d "$path" ]; then
        cd "$path"
        dirty_count=$(git status --porcelain | wc -l | tr -d " ")
        if [ "$dirty_count" -gt 0 ]; then
            echo -e "[${RED}DIRTY${NC}] $proj: ${dirty_count}개 파일 변경됨"
            echo "      -> 권장: git status 확인 후 논리적 단위로 커밋"
        else
            echo -e "[${GREEN}CLEAN${NC}] $proj: 정리 완료"
        fi
    fi
done

echo ""
echo -e "${BLUE}추천 명령어:${NC}"
echo "1. docs 정리: cd ~/Workspace/docs && git add . && git commit -m 'docs: 2026 Q1-Q2 logs and plans updates'"
echo "2. 분석 가이드 보기: cat ~/.claude/cache/triage-dirty/2026-05-07.md"
echo ""
echo "준비가 되셨다면 위 순서대로 정리를 시작해 보세요."
