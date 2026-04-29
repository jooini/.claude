#!/bin/zsh
# Knowledge 인덱스 + 카탈로그 + 에이전트 재빌드 원클릭
# 사용: ~/.claude/scripts/gemma-knowledge-refresh.sh
# knowledge md 파일 추가/수정 후 실행

: "${HOME:?}"
SCRIPTS="$HOME/.claude/scripts"

echo "=== Knowledge Refresh — 4단계 ==="
echo ""

# 1단계: 인덱싱 (증분)
echo "1/4 인덱스 업데이트 (변경된 파일만)..."
python3 "$SCRIPTS/gemma-knowledge-index.py" 2>&1 | /usr/bin/tail -5
echo ""

# 2단계: 실패 재시도 (있을 때만)
echo "2/4 실패 항목 재시도..."
python3 "$SCRIPTS/gemma-knowledge-retry-v2.py" 2>&1 | /usr/bin/tail -3
echo ""

# 3단계: 카탈로그 재생성
echo "3/4 카탈로그 재생성..."
python3 "$SCRIPTS/gemma-catalog-upgrade.py" 2>&1 | /usr/bin/tail -5
echo ""

# 4단계: 에이전트 재빌드
echo "4/4 에이전트 재빌드..."
if [ -x "$HOME/.claude/agents/build-agents.sh" ]; then
    cd "$HOME/.claude/agents" && ./build-agents.sh 2>&1 | /usr/bin/tail -5
else
    echo "  ⚠️ build-agents.sh 없음 — 수동 빌드 필요"
fi
echo ""

echo "✅ Refresh 완료"
echo ""
echo "확인:"
python3 -c "
import json
try:
    d = json.load(open('$HOME/.claude/cache/knowledge-index.json'))
    total = len(d)
    valid = sum(1 for e in d.values() if e.get('title') and e.get('summary'))
    print(f'  인덱스: {valid}/{total} 유효 ({valid/total*100:.0f}%)')
except Exception as e:
    print(f'  ERR: {e}')
"
echo "  카탈로그: $(/usr/bin/wc -l < $HOME/.claude/agents/knowledge/knowledge-catalog.md | /usr/bin/tr -d ' ')줄"
