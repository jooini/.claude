#!/usr/bin/env bash
# Claude Code 설정을 다른 Mac으로 복사
#
# 사용법:
#   copy-to-other-mac.sh <대상호스트>                     # rsync 실행
#   copy-to-other-mac.sh <대상호스트> --dry-run           # 시뮬레이션
#   copy-to-other-mac.sh <대상호스트> --port 2222         # SSH 포트 변경
#   copy-to-other-mac.sh <대상호스트>:<원격경로>          # 대상 경로 명시 (기본: ~/.claude/)
#   copy-to-other-mac.sh <대상호스트> --delete            # 원격에 없는 파일은 그대로 두지 않고 삭제 (위험)
#
# 예시:
#   copy-to-other-mac.sh leonard-air
#   copy-to-other-mac.sh leonard-air --dry-run
#   copy-to-other-mac.sh leonard-air:/Users/leonard/.claude/
#
# 제외:
#   - 캐시/로그 (projects, plugins, cache, file-history, telemetry, debug 등)
#   - 머신별 상태 (session-env, transcripts, todos, tasks, intent, statsig, sessions 등)
#   - 백업 파일 (*.bak, *.bak-*, backups/)
#   - 머신 ID 포함 파일 (security_warnings_state_*, antigravity-workspace.json)
#
# 결과: 약 3.8G → 약 7MB

set -eo pipefail

# ─── 색상 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${CYAN}▸${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
err()   { echo -e "${RED}✗${NC} $1" >&2; }
header() { echo -e "\n${BOLD}═══ $1 ═══${NC}\n"; }

# ─── 옵션 파싱 ───
DRY_RUN=false
DELETE=false
SSH_PORT=""
TARGET=""

usage() {
    cat <<'EOF'
사용법:
  copy-to-other-mac.sh <대상호스트>                     # rsync 실행
  copy-to-other-mac.sh <대상호스트> --dry-run           # 시뮬레이션
  copy-to-other-mac.sh <대상호스트> --port 2222         # SSH 포트
  copy-to-other-mac.sh <대상호스트>:<경로>              # 원격 경로 명시
  copy-to-other-mac.sh <대상호스트> --delete            # 원격 미존재 파일 삭제 (위험)

옵션:
  --dry-run     실제 전송 없이 어떤 파일이 옮겨질지만 출력
  --delete      대상에서 소스에 없는 파일 삭제 (sync 모드)
  --port N      SSH 포트
  -h, --help    도움말

기본 대상 경로: ~/.claude/
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true; shift ;;
        --delete)   DELETE=true; shift ;;
        --port)     SSH_PORT="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        -*)         err "알 수 없는 옵션: $1"; usage; exit 1 ;;
        *)
            if [[ -z "$TARGET" ]]; then
                TARGET="$1"
            else
                err "대상 호스트는 한 번만 지정"; exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    err "대상 호스트 지정 필요"
    usage
    exit 1
fi

# 대상 경로 처리: host 또는 host:path
if [[ "$TARGET" == *:* ]]; then
    REMOTE_DEST="$TARGET"
else
    REMOTE_DEST="${TARGET}:~/.claude/"
fi

# ─── 제외 패턴 ───
# 머신별 상태 / 캐시 / 로그 / 백업 — 다른 Mac에서 무의미하거나 충돌 가능
EXCLUDES=(
    # 대용량 캐시 (자동 재생성)
    "projects/"
    "plugins/"
    "cache/"
    "file-history/"
    "telemetry/"
    "debug/"
    "transcripts/"
    "shell-snapshots/"

    # 머신/세션 별 상태 (이 Mac 전용)
    "session-env/"
    "paste-cache/"
    "todos/"
    "tasks/"
    "intent/"
    "lancedb/"
    "ide/"
    "statsig/"
    "sessions/"
    "plans/"
    "workspace-root/"

    # 우리가 만든 작업 백업 (새 Mac엔 불필요)
    "backups/"

    # 단일 파일 (개인 데이터/머신 ID/캐시)
    "history.jsonl"
    "antigravity-workspace.json"
    "stats-cache.json"
    "mcp-needs-auth-cache.json"
    "policy-limits.json"
    "security_warnings_state_*"

    # 백업 파일들
    "*.bak"
    "*.bak-*"

    # 머신별 로컬 설정 (머신 ID 등 포함)
    "settings.local.json"
    "identity-hub/settings.local.json"

    # macOS 메타파일
    ".DS_Store"

    # IDE/git 메타 (선택적)
    ".idea/"
    ".obsidian/"
)

# ─── rsync 옵션 빌드 ───
RSYNC_OPTS=(
    -avh         # archive + verbose + human-readable
    --progress   # 진행률 표시
    --partial    # 중단 시 재개 가능
)

if $DRY_RUN; then
    RSYNC_OPTS+=(--dry-run --itemize-changes)
fi

if $DELETE; then
    RSYNC_OPTS+=(--delete)
fi

# SSH 포트
if [[ -n "$SSH_PORT" ]]; then
    RSYNC_OPTS+=(-e "ssh -p $SSH_PORT")
fi

# 제외 패턴 추가
for pat in "${EXCLUDES[@]}"; do
    RSYNC_OPTS+=(--exclude="$pat")
done

# ─── 실행 ───
header "Claude 설정 복사: ~/.claude/ → $REMOTE_DEST"

info "대상: $REMOTE_DEST"
info "모드: $($DRY_RUN && echo 'dry-run (시뮬레이션)' || echo '실제 전송')"
info "삭제 동기화: $($DELETE && echo '활성 (--delete)' || echo '비활성')"
[[ -n "$SSH_PORT" ]] && info "SSH 포트: $SSH_PORT"
echo ""
info "예상 효과: 약 3.8G (전체) → 약 7MB (실제 설정만)"
echo ""

if ! $DRY_RUN; then
    warn "원격 ${REMOTE_DEST} 에 덮어씁니다. 5초 후 시작 (Ctrl+C로 취소)"
    sleep 5
fi

echo ""
header "rsync 실행"

rsync "${RSYNC_OPTS[@]}" \
    "$HOME/.claude/" \
    "$REMOTE_DEST"

echo ""
ok "완료"

if $DRY_RUN; then
    echo ""
    info "실제 전송하려면 --dry-run 빼고 다시 실행:"
    info "  $0 $TARGET"
fi

# ─── 마무리 안내 ───
if ! $DRY_RUN; then
    cat <<EOF

${BOLD}새 Mac에서 추가 작업 필요:${NC}

1. 플러그인 재설치 (필요한 경우):
   ${DIM}claude /plugin install <name>${NC}

2. settings.local.json 신규 생성 (머신별 고유):
   ${DIM}cp ~/.claude/settings.local.json.example ~/.claude/settings.local.json${NC}
   필요 시 권한·환경 추가

3. RAG/캐시는 자동 재생성됨

4. macOS 키체인/SSH 키는 별도 복사 필요 (이 스크립트는 ~/.claude만 복사)
EOF
fi
