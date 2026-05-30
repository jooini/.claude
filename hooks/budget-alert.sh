#!/bin/zsh
# Stop hook: 매 응답 끝에 오늘 누적 비용 체크. 임계 넘으면 stderr에 경고 + osascript 알림
# 임계는 환경변수로 조정 (기본 $50)
#
# 비용 목표: <300ms (캐시 활용 + stale-while-revalidate)
#
# 변경 이력:
#   2026-05-09: stale-while-revalidate 패턴 + mtime 필터 도입
#     - 캐시 만료 시 stale 값 즉시 반환 + 백그라운드 갱신 (사용자 체감 0ms)
#     - JSONL 풀스캔 → 오늘 mtime 만 필터 (8285개 → 수십개)
#     - TTL 5분 → 30분

: "${HOME:?}"

# 임계 (USD)
WARN_THRESHOLD="${BUDGET_WARN:-50}"
CRIT_THRESHOLD="${BUDGET_CRIT:-100}"

# 캐시 — 30분 TTL
CACHE_FILE="$HOME/.claude/cache/budget-today.json"
CACHE_TTL="${BUDGET_CACHE_TTL:-1800}"
LOCK_FILE="$HOME/.claude/cache/budget-today.lock"

# 오늘 날짜
TODAY=$(date +%Y-%m-%d)

# 풀 계산 함수 (백그라운드 또는 폴백 동기 호출)
_recalc_budget() {
    /usr/bin/python3 << PYEOF 2>/dev/null
import json, glob, os, time
from collections import defaultdict

# llm-usage.py의 PRICING/cost_for 가져오기 위해 import
import importlib.util
spec = importlib.util.spec_from_file_location("llm_usage", os.path.expanduser("~/.claude/scripts/llm-usage.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

today = "$TODAY"
total_cost = 0.0

# 오늘 0시 epoch (mtime 필터용)
today_start = time.mktime(time.strptime(today, "%Y-%m-%d"))

# JSONL 풀스캔 → mtime 필터로 오늘 수정된 파일만
for path in glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True):
    try:
        if os.path.getmtime(path) < today_start:
            continue  # 오늘 수정 안 된 파일은 스킵
        with open(path) as f:
            for line in f:
                try:
                    obj = json.loads(line)
                    if today not in obj.get('timestamp', ''):
                        continue
                    msg = obj.get('message', {})
                    usage = msg.get('usage') if isinstance(msg, dict) else None
                    if not usage: continue
                    inp = usage.get('input_tokens', 0) or 0
                    out = usage.get('output_tokens', 0) or 0
                    cr = usage.get('cache_read_input_tokens', 0) or 0
                    cc = usage.get('cache_creation_input_tokens', 0) or 0
                    model = (msg.get('model') if isinstance(msg, dict) else None) or 'claude-opus-4-7'
                    model_key = model
                    for k in mod.PRICING:
                        if model.startswith(k):
                            model_key = k; break
                    total_cost += mod.cost_for(model_key, inp, out, cr, cc)
                except: pass
    except: pass

# Codex 추가 (오늘만)
import sqlite3
try:
    conn = sqlite3.connect(f"file:{os.path.expanduser('~/.codex/state_5.sqlite')}?mode=ro", uri=True, timeout=2)
    cur = conn.cursor()
    cur.execute("""
        SELECT COALESCE(model,''), SUM(tokens_used)
        FROM threads
        WHERE date(created_at,'unixepoch','localtime') = ?
        GROUP BY model
    """, (today,))
    for model, tokens in cur.fetchall():
        tokens = tokens or 0
        inp = int(tokens * mod.CODEX_INPUT_RATIO)
        out = tokens - inp
        total_cost += mod.cost_for(model, inp, out)
    conn.close()
except: pass

# 캐시 저장 (atomic: tmp 후 rename)
tmp = "$CACHE_FILE.tmp.$$"
try:
    with open(tmp, 'w') as f:
        json.dump({'cost': total_cost, 'date': today}, f)
    os.rename(tmp, "$CACHE_FILE")
except:
    try: os.unlink(tmp)
    except: pass

print(f"{total_cost:.2f}")
PYEOF
}

# 캐시 신선도 판정
CACHE_FRESH=false
TODAY_COST=""

if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))

    # 캐시 항상 읽음 (stale 이라도 즉시 반환용)
    TODAY_COST=$(/usr/bin/python3 -c "
import json
try:
    d = json.load(open('$CACHE_FILE'))
    if d.get('date') == '$TODAY':
        print(d.get('cost', 0))
    else:
        print('')  # 다른 날짜 → 무효
except: print('')
" 2>/dev/null)

    if [ -n "$TODAY_COST" ] && [ "$CACHE_AGE" -lt "$CACHE_TTL" ]; then
        CACHE_FRESH=true
    fi
fi

# 캐시 stale 또는 없음 → 백그라운드 갱신 (이중 실행 방지 lock)
if [ "$CACHE_FRESH" = false ]; then
    if mkdir "$LOCK_FILE" 2>/dev/null; then
        # lock 획득 → 백그라운드 갱신
        (
            _recalc_budget > /dev/null 2>&1
            rmdir "$LOCK_FILE" 2>/dev/null
        ) &
        disown 2>/dev/null
    fi

    # stale 캐시도 없으면 (오늘 첫 호출) — 동기 폴백 1회만
    if [ -z "$TODAY_COST" ]; then
        TODAY_COST=$(_recalc_budget)
    fi
fi

# 숫자 정상화 + 소수점 2자리
TODAY_COST="${TODAY_COST:-0}"
TODAY_COST=$(awk -v c="$TODAY_COST" 'BEGIN { printf "%.2f", c+0 }')

# 비교 — bash 정수 비교 안 되니 awk
LEVEL=$(awk -v c="$TODAY_COST" -v w="$WARN_THRESHOLD" -v cr="$CRIT_THRESHOLD" '
BEGIN {
    if (c+0 >= cr+0) print "crit"
    else if (c+0 >= w+0) print "warn"
    else print "ok"
}')

case "$LEVEL" in
    crit)
        # 알림 (1회만 — 마커 파일로 중복 방지)
        MARKER="$HOME/.claude/cache/budget-alerted-${TODAY}-crit"
        if [ ! -f "$MARKER" ]; then
            osascript -e "display notification \"오늘 누적 비용 \$${TODAY_COST} (임계 \$${CRIT_THRESHOLD}+ 초과)\" with title \"💸 LLM 예산 경고\" sound name \"Basso\"" 2>/dev/null &
            touch "$MARKER"
        fi
        echo "[budget-alert] 🔴 오늘 비용 \$${TODAY_COST} — 임계 \$${CRIT_THRESHOLD} 초과" >&2
        ;;
    warn)
        MARKER="$HOME/.claude/cache/budget-alerted-${TODAY}-warn"
        if [ ! -f "$MARKER" ]; then
            osascript -e "display notification \"오늘 누적 비용 \$${TODAY_COST}\" with title \"⚠️ LLM 예산 알림\"" 2>/dev/null &
            touch "$MARKER"
        fi
        echo "[budget-alert] 🟡 오늘 비용 \$${TODAY_COST} (임계 \$${WARN_THRESHOLD})" >&2
        ;;
    *)
        # 정상 — 출력 없음
        ;;
esac

exit 0
