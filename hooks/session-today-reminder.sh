#!/bin/zsh
# SessionStart: 하루 첫 세션이면 오늘 할 일 알림 주입
#
# 조건:
#   - 오늘 날짜 마커 파일 없을 때만 (하루에 한 번)
#   - startup 매처 (resume/clear/compact 시 안 뜸)

: "${HOME:?}"

INPUT=$(cat)

# matcher 추출
MATCHER=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('matcher', ''))
except Exception:
    pass
" 2>/dev/null)

# startup만 처리
if [ "$MATCHER" != "startup" ]; then
    exit 0
fi

# 하루 마커 디렉토리
MARKER_DIR="$HOME/.claude/cache/session-markers"
mkdir -p "$MARKER_DIR"

TODAY=$(date +%Y-%m-%d)
MARKER="$MARKER_DIR/today-${TODAY}.marker"

# 오늘 이미 알림 보냈으면 스킵
if [ -f "$MARKER" ]; then
    exit 0
fi

# 마커 생성
touch "$MARKER"

# 어제 마커 정리 (3일 이상된 것만)
/usr/bin/find "$MARKER_DIR" -name "today-*.marker" -mtime +3 -delete 2>/dev/null

# 백로그 카운트 (캐시된 데이터 활용 — 빠른 응답)
BACKLOG_COUNT=0
HIGH_COUNT=0
if [ -f "$HOME/.claude/scripts/backlog-dashboard.py" ]; then
    BACKLOG_DATA=$(/usr/bin/python3 "$HOME/.claude/scripts/backlog-dashboard.py" 2>/dev/null | grep -E "합계" | head -1)
    if [ -n "$BACKLOG_DATA" ]; then
        # "| 합계 | High | Med | Low | Active | ..." 형태에서 High 추출
        HIGH_COUNT=$(echo "$BACKLOG_DATA" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
        BACKLOG_TOTAL=$(echo "$BACKLOG_DATA" | awk -F'|' '
        {
            gsub(/ /,"",$3); gsub(/ /,"",$4); gsub(/ /,"",$5);
            print $3+$4+$5
        }')
    fi
fi

# 캘린더/PR 등은 빠르게 안 가져옴 → 안내만

cat <<EOF
[오늘 첫 세션 — $TODAY]

📋 백로그: 총 ${BACKLOG_TOTAL:-?}건 (High ${HIGH_COUNT:-?}건)

🌅 일과 흐름
  /morning      → 종합 시작 (today + backlog + 서버 + git)
  /start        → 작업 선택 + 브랜치
  /go           → 작업 완료 검증
  /debug        → 막힘 자동 진단
  /done         → 퇴근 마무리

🚀 작업 타입 키워드 (CLAUDE.md 자동 라우팅)
  "기능 추가" → TYPE-A (TDD + 3중 리뷰)
  "버그/에러" → TYPE-B (/debug)
  "리팩터" (3파일+) → TYPE-C (Gemini Phase 0 + worktree)
  "배포" → TYPE-F (🔴 사람 승인)
  "PRD/문서" → TYPE-G (po/prompt-engineer)

🤖 에이전트 호출 (한글)
  "백엔드/프론트/리뷰어/테스터/큐에이/디자이너/피오/데이터/옵스/프롬프트" → 자동 매핑
  복수 동시 호출 → 병렬 실행

⚡ 통합 명령
  /sso-flow      → SSO 4프로젝트 통합
  /safe-deploy   → 배포 전 4단계 안전 체크
  /morning       → 아침 종합

🔍 작업 시작 전 의무 (검색)
  "이전에 X 한 적 있나?" → claude-mem 자동
  "X 코드 어디?" → local-rag 자동

💪 배수 효과 패턴
  "X 백그라운드로 동시 처리" → 시간 압축
  "X 3중 리뷰 병렬" → 동시 검증
  /loop 5m /check-server → 모니터링

📚 모든 명령 한눈에: \`~/.claude/CHEATSHEET.md\`

🤖 자동 동작 (의식 안 해도 됨)
  매일 14시: Gemma cron | 월 03시: 백업 정리 | 금 17시: /retro 7

활용 3대 원칙:
  1. 외우지 말고 보고 써 (이 알림이 매일 자동)
  2. 혼자 하지 말고 위임 (백그라운드/병렬/에이전트)
  3. 자동 트리거 무시하지 말 것
EOF

exit 0
