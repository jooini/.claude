#!/bin/zsh
# SessionStart: 최근 7일간 dormant hook 발견 시 경고 주입
#
# dormant 정의: 호출 100회+ 발생했으나 output(side==output) 0회
# - 정상 noop 카테고리 (데이터 수집/가드)는 화이트리스트로 제외
# - 알림성 hook이 1주 무 발동 → 정리 후보
#
# 결과 캐시: ~/.claude/cache/hook-dormant-warn.cache (24시간 TTL)
# matcher: startup 만 (resume/clear 시 스킵)

: "${HOME:?}"

INPUT=$(cat)
MATCHER=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('matcher', ''))
except: pass
" 2>/dev/null)

[ "$MATCHER" != "startup" ] && exit 0

# 24시간 캐시
CACHE="$HOME/.claude/cache/hook-dormant-warn.cache"
if [ -f "$CACHE" ]; then
    AGE=$(( $(date +%s) - $(/usr/bin/stat -f "%m" "$CACHE" 2>/dev/null || echo 0) ))
    if [ "$AGE" -lt 86400 ]; then
        [ -s "$CACHE" ] && cat "$CACHE"
        exit 0
    fi
fi

# 실측 분석
ANALYSIS=$(/usr/bin/python3 << 'PYEOF'
import json
import os
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict

home = Path(os.environ['HOME'])
trace_dir = home / '.claude' / 'cache' / 'hook-trace'

# 정상 noop 화이트리스트 (데이터 수집/가드 — output 0이 정상)
WHITELIST = {
    # 데이터 수집
    'bash-postproc-async', 'bash-postproc-sync',  # 2026-05-14 통합본 (구 tool-trace/tool-usage-log/branch-switch-detect/cwd-change-detect/gemini-auto-scan/gemini-test-failure-analyze)
    'md-read-trace', 'agent-trace', 'agent-usage-log',
    'pipeline-metrics-log', 'learning-note-auto-ingest', 'decision-capture',
    'knowledge-change-rebuild', 'rag-auto-index', 'turn-marker',
    # 가드 (위험 패턴 검출 안 되면 noop)
    'bash-codegen-block', 'danger-keyword-detect', 'dangerous-command-detect',
    'closure-gate-stop', 'closure-gate-session-start',
    # 시스템성
    'session-turn-counter', 'self-reflection-inject', 'qq-realtime-warning',
    'workflow-md-inject', 'simple-query-ollama-route',
}

cutoff = datetime.now() - timedelta(days=7)
counts = defaultdict(lambda: {'total': 0, 'output': 0})
for f in trace_dir.glob('*.jsonl'):
    try:
        d = datetime.strptime(f.stem, '%Y-%m-%d')
        if d < cutoff:
            continue
    except ValueError:
        continue
    try:
        for line in f.open():
            try:
                r = json.loads(line)
                h = r.get('hook', '')
                if not h or h in WHITELIST:
                    continue
                counts[h]['total'] += 1
                if r.get('side') == 'output':
                    counts[h]['output'] += 1
            except json.JSONDecodeError:
                pass
    except OSError:
        pass

# dormant 후보: 호출 100+ & output 0
dormant = sorted(
    [(h, c) for h, c in counts.items() if c['total'] >= 100 and c['output'] == 0],
    key=lambda x: -x[1]['total'],
)

if not dormant:
    print('')  # 정상 — 알림 없음
else:
    print(f"[Hook 헬스 — 7일 dormant 발견 ({len(dormant)}개)]")
    print()
    print("다음 hook들이 1주 동안 호출만 되고 output 0회:")
    print()
    for h, c in dormant[:8]:
        print(f"  - {h:40} 호출 {c['total']:>5}회 / output 0")
    if len(dormant) > 8:
        print(f"  ... (총 {len(dormant)}개)")
    print()
    print("정리 검토:")
    print("  python3 ~/.claude/scripts/hook-dormant-cleanup.py 7  (분석)")
    print("  python3 ~/.claude/scripts/hook-dormant-cleanup.py 7 --apply  (자동 비활성)")
PYEOF
)

if [ -n "$ANALYSIS" ]; then
    echo "$ANALYSIS" | tee "$CACHE"
else
    > "$CACHE"
fi

exit 0
