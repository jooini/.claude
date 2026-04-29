#!/bin/zsh
# package.sh — 공유용 Claude Code 설정 패키지 생성
#
# 사용법:
#   cd ~/.claude && ./package.sh
#   → claude-config-YYYYMMDD.zip 생성

set -euo pipefail

CLAUDE_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(cat "$CLAUDE_DIR/VERSION" 2>/dev/null | tr -d '\n')
DATE=$(date +%Y%m%d)
OUTPUT="$CLAUDE_DIR/claude-config-v${VERSION}-${DATE}.zip"

echo ""
echo "========================================="
echo "  Claude Code 설정 패키지 생성"
echo "========================================="
echo ""

cd "$CLAUDE_DIR"

# 기존 zip 삭제 (stale 파일 방지)
rm -f "$OUTPUT"

zip -r "$OUTPUT" \
    VERSION \
    CLAUDE.md.template \
    AGENTS.md \
    README.md \
    settings.json.example \
    settings.local.json.example \
    docs-config.yaml.example \
    setup.sh \
    package.sh \
    statusline-agent.sh \
    antigravity-workspace.json \
    agents/src/ \
    agents/knowledge/ \
    agents/docs/ \
    agents/build-agents.sh \
    agents/README.md \
    hooks/*.sh \
    hooks/sounds/ \
    workflows/ \
    commands/ \
    skills/ \
    scripts/ \
    -x "*.DS_Store" "*.swp" "*__pycache__*" "*.log" "*.jtl" "*.jmx" \
    2>/dev/null

SIZE=$(du -sh "$OUTPUT" | awk '{print $1}')

echo ""
echo "  버전: v$VERSION"
echo "  생성: $OUTPUT ($SIZE)"
echo ""
echo "  사용법 (받는 사람):"
echo "    mkdir -p ~/.claude"
echo "    unzip claude-config-${DATE}.zip -d ~/.claude/"
echo "    cd ~/.claude && chmod +x setup.sh && ./setup.sh"
echo ""
