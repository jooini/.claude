#!/bin/zsh
# UserPromptSubmit: 세션 턴 카운트 후 200/300/500턴 도달 시 핸드오프 권유
#
# 목적: 1 태스크 = 1 세션 원칙 강제. 긴 세션은 컨텍스트 오염 → 핸드오프로 분할
# 효과: 세션 길어질수록 응답 느려지고 추정 늘어나는 것 방지
#
# 임계점 변경 이력:
#   2026-05-09: 50/100/150 → 200/300/500 (사용자 요청, 너무 자주 떴음)

: "${HOME:?}"

INPUT=$(cat)

# transcript_path 추출
TRANSCRIPT=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
fi

# 사용자 프롬프트 라인 수 = 턴 수 (대략)
TURN_COUNT=$(/usr/bin/grep -c '"role":"user"' "$TRANSCRIPT" 2>/dev/null || echo 0)

# 200/300/500턴 임계점 도달 감지
THRESHOLD=""
if [ "$TURN_COUNT" -ge 500 ]; then
    THRESHOLD="500"
    LEVEL="🚨 매우 긴 세션"
elif [ "$TURN_COUNT" -ge 300 ]; then
    THRESHOLD="300"
    LEVEL="⚠️ 긴 세션"
elif [ "$TURN_COUNT" -ge 200 ]; then
    THRESHOLD="200"
    LEVEL="📌 중간 길이"
else
    # 200턴 미만 — 알림 없음
    exit 0
fi

# 정확히 임계점 ±2 범위에서만 알림 (한 번씩)
# (200, 300, 500 부근에서 한 번씩만 — 매 턴 알림 방지)
DIFF_200=$((TURN_COUNT - 200))
DIFF_300=$((TURN_COUNT - 300))
DIFF_500=$((TURN_COUNT - 500))

SHOW=0
[ "$DIFF_200" -ge 0 ] && [ "$DIFF_200" -le 1 ] && SHOW=1
[ "$DIFF_300" -ge 0 ] && [ "$DIFF_300" -le 1 ] && SHOW=1
[ "$DIFF_500" -ge 0 ] && [ "$DIFF_500" -le 1 ] && SHOW=1

if [ "$SHOW" -eq 0 ]; then
    exit 0
fi

cat <<EOF
[세션 분할 권장] $LEVEL — 현재 턴 수: $TURN_COUNT (임계점: $THRESHOLD)

CLAUDE.md 룰: 1 태스크 = 1 세션 원칙. 긴 세션은 컨텍스트 오염으로 응답 품질 저하.

현재 작업 마무리 후:
1. \`/session-handoff\` 스킬 실행 → 핸드오프 문서 생성
2. 새 세션 시작 → 핸드오프 문서 기반으로 이어서 진행

핸드오프하지 않을 경우:
- 메인 컨텍스트가 길어져 추정/실수 증가
- 응답 시간 증가
- 같은 세션에서 새 태스크 시작 금지 권장

작업 종료 시점이면 \`/done\`으로 마무리.
EOF

exit 0
