#!/usr/bin/env bash
# Claude Code ↔ Antigravity 설정 동기화 스크립트
# 사용법: ~/.claude/scripts/sync-antigravity.sh [--dry-run]
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

CLAUDE_SKILLS="$HOME/.claude/skills"
AGENTS_SKILLS="$HOME/.agents/skills"
GEMINI_DIR="$HOME/.gemini"
GEMINI_SKILLS="$GEMINI_DIR/skills"

# 프로젝트 목록 (CLAUDE.md가 있는 프로젝트)
PROJECTS=(
    "$HOME/Workspace/identity-hub"
    "$HOME/Workspace/identity-keycloak"
    "$HOME/Workspace/maxai-b2c-backend"
    "$HOME/Workspace/ai-agentic-workflow"
    "$HOME/Workspace/maxai"
    "$HOME/Workspace/meeting-minutes"
    "$HOME/Workspace/schedule-app"
    "$HOME/Workspace/identity-hub-frontend"
    "$HOME/Workspace/identity-hub-python-sdk"
    "$HOME/Workspace/keycloak-kakao-social-provider"
    "$HOME/Workspace/sso-fallback-monitor"
    "$HOME/Workspace/maxai-docker"
    "$HOME/Workspace/identity-platform-docker"
)

log() { echo "[sync] $*"; }
run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        eval "$@"
    fi
}

# ─── 1. 글로벌 GEMINI.md 생성 ───────────────────────────────
log "1/4 글로벌 GEMINI.md 생성..."

GEMINI_MD="$GEMINI_DIR/GEMINI.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

if $DRY_RUN; then
    echo "[dry-run] GEMINI.md 생성: $GEMINI_MD"
else
    mkdir -p "$GEMINI_DIR"
    cat > "$GEMINI_MD" << 'RULES'
# Antigravity 글로벌 규칙

## 역할
Antigravity의 Gemini 에이전트는 병렬 구현 담당. 깊은 추론/리뷰는 Claude Code가 처리.

## 커밋 규칙
- 커밋 메시지는 한글로 작성
- Co-Authored-By 포함하지 않음

## 코딩 컨벤션
- 들여쓰기: 공백 4칸 (Makefile/Go 제외)
- 파일 상단 수정이력 주석 금지
- FastAPI: Depends() 직접 사용 금지 → Annotated 앨리어스
- 클래스 리네이밍 시 파일명도 변경
- 약어/줄임 네이밍 금지 → 풀네임

## 응답 스타일
- 묻지 말고 알아서 진행
- 중간 확인/상태 업데이트 금지

## 프로젝트 공통
- Kotlin Spring Boot 우선 (백엔드 신규)
- PostgreSQL (관계형), Redis (캐시/세션)
- 알 수 없는 비즈니스 요구사항을 만들어내지 말 것

## SSO 핵심 정책
- 계정 중복 허용: 전화번호/이메일 중복 허용 (레거시 유지)
- SSO 폴백: identity-nginx에서 502/503/504 시 레거시 폴백
- BFF 패턴: client_secret은 Identity Hub만 보유
- Keycloak: getUserByUsername에 반드시 exact=True
RULES
    log "  → $GEMINI_MD 생성 완료"
fi

# ─── 2. 스킬 심링크 ─────────────────────────────────────────
log "2/4 스킬 심링크..."

mkdir -p "$GEMINI_SKILLS" 2>/dev/null || true

# 커뮤니티 스킬 (.agents/skills → .gemini/skills)
LINKED=0
SKIPPED=0
if [[ -d "$AGENTS_SKILLS" ]]; then
    for skill_dir in "$AGENTS_SKILLS"/*/; do
        skill_name=$(basename "$skill_dir")
        target="$GEMINI_SKILLS/$skill_name"
        if [[ ! -e "$target" ]]; then
            run "ln -s '$skill_dir' '$target'"
            ((LINKED++))
        else
            ((SKIPPED++))
        fi
    done
fi

# 커스텀 스킬 (.claude/skills 중 실제 디렉토리인 것)
for skill_dir in "$CLAUDE_SKILLS"/*/; do
    [[ ! -d "$skill_dir" ]] && continue
    # 심링크가 아닌 실제 디렉토리만 (커스텀 스킬)
    if [[ ! -L "${skill_dir%/}" ]]; then
        skill_name=$(basename "$skill_dir")
        target="$GEMINI_SKILLS/$skill_name"
        if [[ ! -e "$target" ]]; then
            run "ln -s '${skill_dir%/}' '$target'"
            ((LINKED++))
        else
            ((SKIPPED++))
        fi
    fi
done

log "  → 심링크 생성: ${LINKED}개, 이미 존재: ${SKIPPED}개"

# ─── 3. 프로젝트별 AGENTS.md 생성 ───────────────────────────
log "3/4 프로젝트 AGENTS.md 동기화..."

SYNCED=0
for project in "${PROJECTS[@]}"; do
    claude_md="$project/CLAUDE.md"
    agents_md="$project/AGENTS.md"

    [[ ! -f "$claude_md" ]] && continue

    # CLAUDE.md가 더 새로우면 AGENTS.md 갱신
    if [[ ! -f "$agents_md" ]] || [[ "$claude_md" -nt "$agents_md" ]]; then
        if $DRY_RUN; then
            echo "[dry-run] cp $claude_md → $agents_md"
        else
            cp "$claude_md" "$agents_md"
            log "  → $(basename "$project")/AGENTS.md 갱신"
        fi
        ((SYNCED++))
    fi
done

log "  → ${SYNCED}개 프로젝트 동기화"

# ─── 4. 상태 요약 ───────────────────────────────────────────
log "4/4 동기화 완료"
echo ""
echo "=== 동기화 결과 ==="
echo "  GEMINI.md:  $GEMINI_MD"
echo "  스킬 경로:  $GEMINI_SKILLS ($(ls -d "$GEMINI_SKILLS"/*/ 2>/dev/null | wc -l | tr -d ' ')개)"
echo "  AGENTS.md:  ${SYNCED}개 프로젝트 갱신"
echo ""
echo "Antigravity에서 사용:"
echo "  1. Antigravity 열기"
echo "  2. 터미널(Cmd+\`) → claude 실행"
echo "  3. Agent Manager(Cmd+Shift+M)로 병렬 작업"
