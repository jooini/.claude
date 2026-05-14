#!/bin/zsh
# Stop hook: Claude의 마지막 응답에서 "닫기 부재" 패턴 감지하여 카운터 증가 + 사용자 알림
#
# 감지 패턴:
#   1. 단언 — "완성", "100%", "다 됐", "끝났", "정상 동작", "검증 통과"
#   2. 추정 — "~인 듯", "아마", "추정", "추측" (사실 질문 직후일 때 가중)
#   3. 자의적 결정 — "축소", "정리", "폐기", "삭제" + 숫자(N개)
#
# 동작:
#   - 위반 감지 시 ~/.claude/cache/closure-violations.jsonl에 기록
#   - 일일 위반 횟수가 임계치 초과하면 stderr로 사용자에게 경고 표시
#   - 다음 SessionStart에서 어제 위반 건수가 노출됨

: "${HOME:?}"

CACHE_DIR="$HOME/.claude/cache"
mkdir -p "$CACHE_DIR"
LOG_FILE="$CACHE_DIR/closure-violations.jsonl"
DAILY_THRESHOLD=3

# Stop hook은 stdin으로 transcript 경로를 받음
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# 마지막 assistant 메시지의 텍스트만 추출
LAST_TEXT=$(python3 - "$TRANSCRIPT_PATH" <<'PY' 2>/dev/null
import json, sys
path = sys.argv[1]
try:
    last = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('type') == 'assistant':
                last = m
    if not last:
        sys.exit(0)
    msg = last.get('message', {})
    parts = []
    for block in msg.get('content', []):
        if isinstance(block, dict) and block.get('type') == 'text':
            parts.append(block.get('text', ''))
    print('\n'.join(parts))
except Exception:
    pass
PY
)

if [ -z "$LAST_TEXT" ]; then
    exit 0
fi

VIOLATIONS=()

# 1. 단언 패턴 — 검증 증거 없는 완료 선언
if echo "$LAST_TEXT" | grep -qE '(완성도 100%|완성도100%|✅ 완료|✅완료|완벽하게|완벽히|모든.{0,8}성공|전부.{0,8}통과)'; then
    if ! echo "$LAST_TEXT" | grep -qE '(grep|Grep|Bash|실행 결과|실측|stdout|exit 0|테스트 통과|✓ ?[0-9]+|passed)'; then
        VIOLATIONS+=("assertion_no_evidence")
    fi
fi

# 2. 추정 마커 — 검증 표시 없이 단정에 가까운 어조
if echo "$LAST_TEXT" | grep -qE '(아마.{0,20}일 ?것|~?인 ?듯|추정 ?됩니다|추측 ?됩니다|것으로 ?보입니다|것 ?같습니다)' ; then
    if ! echo "$LAST_TEXT" | grep -qE '(검증 필요|확인 필요|⚠️|❓|TODO|미검증)'; then
        VIOLATIONS+=("guess_without_marker")
    fi
fi

# 3. 자의적 대량 결정 — 수치 + 축소/삭제/정리 동사
if echo "$LAST_TEXT" | grep -qE '([0-9]{2,}개?.{0,10}(축소|삭제|정리|폐기|archive|아카이브)|(축소|삭제|정리|폐기).{0,10}[0-9]{2,}개)'; then
    if ! echo "$LAST_TEXT" | grep -qE '(승인|동의|확인 ?후|검토 ?후|괜찮|진행 할까|진행할까|해도 ?될까|괜찮을까)'; then
        VIOLATIONS+=("autonomous_bulk_decision")
    fi
fi

# 4. stale 감지 — 같은 토픽을 다시 만든다는 흔적
if echo "$LAST_TEXT" | grep -qE '(다시 ?(만들|생성|작성)|새로 ?(만들|작성)|재작성)'; then
    if ! echo "$LAST_TEXT" | grep -qE '(superseded|기존.{0,10}(폐기|삭제|archive|stale)|이전.{0,10}(폐기|삭제))'; then
        VIOLATIONS+=("rewrite_without_retire")
    fi
fi

if [ ${#VIOLATIONS[@]} -eq 0 ]; then
    exit 0
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date +%Y-%m-%d)
SESSION_ID=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

for V in "${VIOLATIONS[@]}"; do
    printf '{"ts":"%s","date":"%s","session":"%s","kind":"%s"}\n' \
        "$TS" "$TODAY" "$SESSION_ID" "$V" >> "$LOG_FILE"
done

TODAY_COUNT=$(grep -c "\"date\":\"$TODAY\"" "$LOG_FILE" 2>/dev/null | tr -d ' \n' || true)
[ -z "$TODAY_COUNT" ] && TODAY_COUNT=0

if [ "$TODAY_COUNT" -ge "$DAILY_THRESHOLD" ]; then
    {
        echo ""
        echo "[CLOSURE-GATE] 오늘 닫기 부재 패턴 ${TODAY_COUNT}회 감지 (임계 ${DAILY_THRESHOLD})"
        echo "  최근 위반: ${VIOLATIONS[*]}"
        echo "  /done 또는 증거 보강 필요 — ~/.claude/cache/closure-violations.jsonl 참조"
        echo ""
    } >&2
fi

exit 0
