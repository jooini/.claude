#!/bin/zsh
# setup.sh — Claude Code 설정 패키지 초기 설정
#
# 사용법:
#   git clone <repo> ~/.claude
#   cd ~/.claude && ./setup.sh
#
# 또는 기존 설정 위에 덮어쓸 때:
#   cd ~/.claude && ./setup.sh --force
#
# 비대화형 모드 (CI/스크립트용):
#   MODULES="gemini,codex,gitlab,rag" ./setup.sh
#   MODULES="none" ./setup.sh          # 코어만 설치
#   MODULES="all" ./setup.sh           # 전부 설치

set -euo pipefail

CLAUDE_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo "${GREEN}[✓]${NC} $1" }
warn() { echo "${YELLOW}[!]${NC} $1" }
err()  { echo "${RED}[✗]${NC} $1" }
info() { echo "${CYAN}[i]${NC} $1" }
ask()  { echo -n "${BOLD}[?]${NC} $1" }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

VERSION=$(cat "$CLAUDE_DIR/VERSION" 2>/dev/null | tr -d '\n' || echo "unknown")

echo ""
echo "========================================="
echo "  Claude Code 환경 설정  v$VERSION"
echo "========================================="
echo ""
info "Claude 디렉토리: $CLAUDE_DIR"
info "홈 디렉토리: $HOME_DIR"
info "사용자: $(whoami)"
info "플랫폼: $(uname -s)"
echo ""

# ─────────────────────────────────────────────
# 0. 선택적 모듈 정의 및 선택
# ─────────────────────────────────────────────
# 모듈 목록: gemini, codex, gitlab, rag, playwright, obsidian
typeset -A MODULE_DESC=(
    gemini     "Gemini CLI 연동 (Phase 0 스캔, 자동 리뷰)"
    codex      "OpenAI Codex 연동 (병렬 구현, rescue, 리뷰)"
    gitlab     "GitLab MCP 서버"
    rag        "Local RAG MCP 서버 (의미론적 검색)"
    playwright "Playwright 브라우저 자동화"
    obsidian   "Obsidian 문서 관리 (문서 작성 규칙, 스킬 연동)"
)

# 모듈별 관련 훅 (settings.json에서 제거할 훅 파일명)
# 주의: gemini-auto-scan / gemini-test-failure-analyze 는 bash-postproc-sync.sh 에 통합됨 (2026-05-14)
#       gemini 모듈 OFF 시에는 bash-postproc-sync.sh 내부에서 gemini 명령 부재 분기로 자동 noop
typeset -A MODULE_HOOKS=(
    gemini     "gemini-review-prescan.sh"
    codex      "codex-session-notify.sh codex-prompt-notify.sh error-codex-remind.sh pr-create-codex-remind.sh"
    gitlab     ""
    rag        ""
    playwright ""
    obsidian   ""
)

# 모듈별 settings.json 플러그인 키
typeset -A MODULE_PLUGINS=(
    gemini     ""
    codex      "codex@openai-codex"
    gitlab     "gitlab@claude-plugins-official"
    rag        ""
    playwright "playwright@claude-plugins-official"
    obsidian   ""
)

# 모듈별 settings.json MCP 서버 키
typeset -A MODULE_MCP=(
    gemini     ""
    codex      ""
    gitlab     "gitlab"
    rag        "local-rag"
    playwright ""
    obsidian   ""
)

# 모듈별 autoApprove 패턴
typeset -A MODULE_AUTOAPPROVE=(
    gemini     'Bash(gemini *)'
    codex      'Bash(codex *)'
    gitlab     'mcp__gitlab__*'
    rag        'mcp__local-rag__*'
    playwright ""
    obsidian   ""
)

# 모듈별 extraKnownMarketplaces 키
typeset -A MODULE_MARKETPLACE=(
    gemini     ""
    codex      "openai-codex"
    gitlab     ""
    rag        ""
    playwright ""
    obsidian   ""
)

ALL_MODULES=(gemini codex gitlab rag playwright obsidian)

# 선택된 모듈 저장
typeset -A SELECTED=()
for mod in "${ALL_MODULES[@]}"; do
    SELECTED[$mod]=false
done

if [[ -n "${MODULES:-}" ]]; then
    # 환경변수로 지정된 경우 (비대화형)
    if [[ "$MODULES" == "all" ]]; then
        for mod in "${ALL_MODULES[@]}"; do SELECTED[$mod]=true; done
        info "전체 모듈 설치 (MODULES=all)"
    elif [[ "$MODULES" == "none" ]]; then
        info "코어만 설치 (MODULES=none)"
    else
        IFS=',' read -rA requested <<< "$MODULES"
        for mod in "${requested[@]}"; do
            mod="${mod// /}"  # 공백 제거
            if (( ${+MODULE_DESC[$mod]} )); then
                SELECTED[$mod]=true
            else
                warn "알 수 없는 모듈: $mod (무시)"
            fi
        done
        info "선택된 모듈: $MODULES"
    fi
else
    # 대화형 모듈 선택
    echo "${BOLD}── 선택적 모듈 설치 ──${NC}"
    echo ""
    echo "  코어 기능은 항상 설치됩니다."
    echo "  아래 모듈을 선택적으로 설치할 수 있습니다."
    echo "  ${DIM}(y/n으로 응답, Enter = 기본값)${NC}"
    echo ""

    for mod in "${ALL_MODULES[@]}"; do
        # 이미 설치된 CLI가 있으면 기본값 Y
        default="n"
        case "$mod" in
            gemini)  command -v gemini &>/dev/null && default="y" ;;
            codex)   command -v codex &>/dev/null && default="y" ;;
            *)       default="n" ;;
        esac

        if [[ "$default" == "y" ]]; then
            ask "$mod — ${MODULE_DESC[$mod]} [Y/n]: "
        else
            ask "$mod — ${MODULE_DESC[$mod]} [y/N]: "
        fi
        read -r answer
        answer="${answer:-$default}"

        if [[ "$answer" =~ ^[Yy] ]]; then
            SELECTED[$mod]=true
            log "$mod 활성화"
        else
            info "$mod 건너뜀"
        fi
    done
fi

echo ""

# ─────────────────────────────────────────────
# 1. CLAUDE.md 생성 (template에서 복사)
# ─────────────────────────────────────────────
if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ] || [ "$FORCE" = true ]; then
    if [ -f "$CLAUDE_DIR/CLAUDE.md.template" ]; then
        log "CLAUDE.md.template → CLAUDE.md 생성"
        cp "$CLAUDE_DIR/CLAUDE.md.template" "$CLAUDE_DIR/CLAUDE.md"

        # Gemini/Codex 비활성화 시 CLAUDE.md 조정 (python3 — trailing 콤마/마침표 정리)
        if [[ "${SELECTED[gemini]}" != "true" ]] || [[ "${SELECTED[codex]}" != "true" ]]; then
            info "  CLAUDE.md에서 Gemini/Codex 관련 지시 조정 중..."
            python3 -c "
import re, sys

gemini = sys.argv[2] == 'true'
codex = sys.argv[3] == 'true'

with open(sys.argv[1], 'r') as f:
    lines = f.readlines()

out = []
skip_line = False
for line in lines:
    s = line

    # === Gemini 비활성화 ===
    if not gemini:
        # 트리거 규칙: 'Gemini 스캔 → developer' → 'developer'
        s = s.replace('최소 Gemini 스캔 → developer', 'developer')
        # 2-pass 분석 라인 삭제
        if '2-pass 분석 (필수)' in s:
            continue
        if 'Phase 0에서 Gemini CLI' in s:
            continue
        # 도구 역할 분담에서 Gemini 제거
        s = re.sub(r'\s*\*\*Gemini\*\*: Phase 0 스캔\(1M토큰\)\+테스트 생성\+3중 리뷰\+최종 통합 검증\.', '', s)

    # === Codex 비활성화 ===
    if not codex:
        # 파이프라인: codex:review 제거
        s = s.replace(' → 병렬(code-reviewer + codex:review)', '→ code-reviewer')
        # codex 관련 라인 삭제
        if 'codex-review 스킬은' in s:
            continue
        if 'codex:adversarial-review' in s:
            continue
        if 'codex:parallel-impl' in s:
            continue
        if re.search(r'codex:codex-rescue는.*구현/수정 전용', s):
            continue
        # codex:rescue → 사용자 에스컬레이션
        s = s.replace('codex:codex-rescue **foreground**로 에스컬레이션', '사용자에게 에스컬레이션')
        s = s.replace('3회 실패 시 \`codex:codex-rescue\` foreground 에스컬레이션', '3회 실패 시 사용자에게 에스컬레이션')
        # 도구 역할 분담에서 Codex 제거
        s = re.sub(r'\s*\*\*Codex\*\*: 병렬 구현\+검증\(rescue foreground only\)\.', '', s)

    # === 자동 트리거 섹션 처리 ===
    if not gemini and not codex:
        # 둘 다 없으면 섹션 전체 제거 (다음 ## 헤딩까지)
        if '### Gemini/Codex 자동 트리거' in s:
            skip_line = True
            continue
        if skip_line:
            if s.startswith('## '):
                skip_line = False
                out.append(s)
            continue
    else:
        # 자동 트리거 내 개별 항목 제거
        if not gemini:
            s = re.sub(r'의존성 변경→Gemini 분석, ', '', s)
            s = re.sub(r'프로젝트 전환→Gemini 스캔', '', s)
            s = re.sub(r'코드 구조 질문→Gemini 스캔, ', '', s)
            s = re.sub(r'업그레이드→Gemini 영향 스캔, ', '', s)
        if not codex:
            s = re.sub(r'테스트 3회 실패→Codex rescue, ', '', s)
            s = re.sub(r'PR 생성→Codex 요약, ', '', s)
            s = re.sub(r'버그→Codex 재현, ', '', s)
            s = re.sub(r'설계 판단\(3파일\+\)→Codex 세컨드 오피니언', '', s)

        # trailing 콤마+마침표 정리: ', .' → '.' / ', \n' → '.\n'
        s = re.sub(r',\s*\.', '.', s)
        # trailing 콤마+줄끝 정리
        s = re.sub(r',\s*$', '.\n', s)
        # 'hooks가 자동 처리: .' → 빈 내용이면 라인 삭제
        if re.match(r'^.*자동 처리:\s*\.\s*$', s):
            continue
        if re.match(r'^.*자동 트리거:\s*\.\s*$', s):
            continue

    # 도구 역할 분담 줄 마무리 정리
    # '. .' → '.' / trailing '. ' → '.'
    s = re.sub(r'\.\s+\.', '.', s)
    s = re.sub(r'\.\s+$', '.\n', s)
    # '의사결정. .' → '의사결정.'
    s = re.sub(r'\.\s*\.\s*$', '.\n', s)

    out.append(s)

with open(sys.argv[1], 'w') as f:
    f.writelines(out)
" "$CLAUDE_DIR/CLAUDE.md" "${SELECTED[gemini]}" "${SELECTED[codex]}"
        fi

        # RAG 비활성화 시 검색 우선순위 조정
        if [[ "${SELECTED[rag]}" != "true" ]]; then
            info "  CLAUDE.md에서 RAG 검색 우선순위 조정 중..."
            sed -i '' 's/1순위: `mcp__local-rag__query_documents` (의미론적 + 키워드)/1순위: `Grep` (정확한 패턴)/' "$CLAUDE_DIR/CLAUDE.md"
            sed -i '' 's/2순위: `Grep` (정확한 패턴)/2순위: `Glob` (파일명\/경로)/' "$CLAUDE_DIR/CLAUDE.md"
            sed -i '' 's/3순위: `Glob` (파일명\/경로)/3순위: `Read` (위 결과에서 확인된 파일)/' "$CLAUDE_DIR/CLAUDE.md"
            sed -i '' '/4순위: `Read`/d' "$CLAUDE_DIR/CLAUDE.md"
            sed -i '' '/RAG 없이 바로/d' "$CLAUDE_DIR/CLAUDE.md"
            sed -i '' '/ingest_file.*RAG/d' "$CLAUDE_DIR/CLAUDE.md"
        fi

        # Obsidian 비활성화 시 문서 작성 규칙 섹션 제거
        if [[ "${SELECTED[obsidian]}" != "true" ]]; then
            info "  CLAUDE.md에서 Obsidian 문서 규칙 제거 중..."
            # python으로 섹션 제거 (sed 한글 호환 문제 회피)
            python3 -c "
import re, sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
# '## 문서 작성 규칙' ~ 다음 '##' 직전까지 제거
content = re.sub(r'## 문서 작성 규칙\n.*?(?=## )', '', content, flags=re.DOTALL)
# Obsidian 문서 디렉토리 블록 제거
content = re.sub(r'Obsidian 문서 디렉토리:.*?(?=\n\n|\Z)', '', content, flags=re.DOTALL)
# TODO Obsidian 라인 제거
content = re.sub(r'.*TODO.*Obsidian.*\n?', '', content)
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$CLAUDE_DIR/CLAUDE.md"
        fi

        info "  CLAUDE.md의 TODO 항목을 자신의 환경에 맞게 수정하세요"
    else
        err "CLAUDE.md.template 없음"
        exit 1
    fi
else
    info "CLAUDE.md 이미 존재 — 건너뜀 (덮어쓰려면 --force)"
fi

# ─────────────────────────────────────────────
# 2. settings.json 생성 (example에서 복사 + 모듈별 조정)
# ─────────────────────────────────────────────
if [ ! -f "$SETTINGS_FILE" ] || [ "$FORCE" = true ]; then
    if [ -f "$CLAUDE_DIR/settings.json.example" ]; then
        log "settings.json.example → settings.json 생성"
        cp "$CLAUDE_DIR/settings.json.example" "$SETTINGS_FILE"
    else
        err "settings.json.example 없음 — 수동으로 settings.json 생성 필요"
        exit 1
    fi
else
    info "settings.json 이미 존재 — 건너뜀 (덮어쓰려면 --force)"
fi

# settings.local.json 생성 (개인 퍼미션 오버라이드)
if [ ! -f "$CLAUDE_DIR/settings.local.json" ] || [ "$FORCE" = true ]; then
    if [ -f "$CLAUDE_DIR/settings.local.json.example" ]; then
        log "settings.local.json.example → settings.local.json 생성"
        cp "$CLAUDE_DIR/settings.local.json.example" "$CLAUDE_DIR/settings.local.json"
    fi
else
    info "settings.local.json 이미 존재 — 건너뜀"
fi

# docs-config.yaml 생성 (obsidian 모듈 활성화 시)
if [[ "${SELECTED[obsidian]}" == "true" ]]; then
    if [ ! -f "$CLAUDE_DIR/docs-config.yaml" ] || [ "$FORCE" = true ]; then
        if [ -f "$CLAUDE_DIR/docs-config.yaml.example" ]; then
            log "docs-config.yaml.example → docs-config.yaml 생성"
            cp "$CLAUDE_DIR/docs-config.yaml.example" "$CLAUDE_DIR/docs-config.yaml"
            info "  docs-config.yaml를 자신의 프로젝트에 맞게 수정하세요"
        fi
    else
        info "docs-config.yaml 이미 존재 — 건너뜀"
    fi
fi

# 비활성 모듈의 설정 제거 (jq 필요)
if command -v jq &>/dev/null; then
    for mod in "${ALL_MODULES[@]}"; do
        if [[ "${SELECTED[$mod]}" == "true" ]]; then
            continue
        fi

        info "  $mod 모듈 설정 제거 중..."

        # 훅 제거
        for hook_file in ${(s: :)MODULE_HOOKS[$mod]}; do
            if [[ -n "$hook_file" ]]; then
                # settings.json에서 해당 훅 파일 참조 제거
                jq --arg hook "$hook_file" '
                    .hooks |= with_entries(
                        .value |= map(
                            if .hooks then
                                .hooks |= map(select(.command | contains($hook) | not))
                            else . end
                        )
                    )
                ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            fi
        done

        # 플러그인 제거
        plugin="${MODULE_PLUGINS[$mod]}"
        if [[ -n "$plugin" ]]; then
            jq --arg p "$plugin" 'del(.enabledPlugins[$p])' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        fi

        # MCP 서버 제거
        mcp="${MODULE_MCP[$mod]}"
        if [[ -n "$mcp" ]]; then
            jq --arg m "$mcp" 'del(.mcpServers[$m])' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        fi

        # autoApprove 제거
        approve="${MODULE_AUTOAPPROVE[$mod]}"
        if [[ -n "$approve" ]]; then
            jq --arg a "$approve" '.autoApprove |= map(select(. != $a))' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        fi

        # extraKnownMarketplaces 제거
        market="${MODULE_MARKETPLACE[$mod]}"
        if [[ -n "$market" ]]; then
            jq --arg m "$market" 'del(.extraKnownMarketplaces[$m])' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        fi
    done

    # 빈 hooks 배열 정리
    jq '
        .hooks |= with_entries(
            .value |= map(select(
                if .hooks then (.hooks | length) > 0 else true end
            ))
        ) |
        .hooks |= with_entries(select(.value | length > 0))
    ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

else
    warn "jq 미설치 — 모듈별 settings.json 조정 건너뜀"
    warn "  brew install jq 후 다시 실행하거나 수동으로 편집하세요"
fi

# ─────────────────────────────────────────────
# 3. 경로 치환 ($HOME → 실제 경로)
# ─────────────────────────────────────────────
log "경로 치환 중..."

# settings.json: $HOME → 실제 홈 경로
sed -i '' "s|\\\$HOME|$HOME_DIR|g" "$SETTINGS_FILE"
# 혹시 이전 사용자 경로가 남아있으면 치환
sed -i '' "s|/Users/[^/\"]*/\.claude/|$CLAUDE_DIR/|g" "$SETTINGS_FILE"

# settings.local.json
if [ -f "$CLAUDE_DIR/settings.local.json" ]; then
    sed -i '' "s|\\\$HOME|$HOME_DIR|g" "$CLAUDE_DIR/settings.local.json"
    sed -i '' "s|/Users/[^/\"]*/\.claude/|$CLAUDE_DIR/|g" "$CLAUDE_DIR/settings.local.json"
fi

# antigravity-workspace.json
if [ -f "$CLAUDE_DIR/antigravity-workspace.json" ]; then
    sed -i '' "s|\\\$HOME|$HOME_DIR|g" "$CLAUDE_DIR/antigravity-workspace.json"
fi

info "  settings.json 및 관련 파일 경로 치환 완료"

# ─────────────────────────────────────────────
# 4. 시크릿 입력 (활성화된 MCP만)
# ─────────────────────────────────────────────
echo ""
echo "${BOLD}── MCP 서버 설정 ──${NC}"
echo ""

# GitLab URL (gitlab 모듈 활성화 시만)
if [[ "${SELECTED[gitlab]}" == "true" ]]; then
    CURRENT_GITLAB=$(grep -o '"GITLAB_API_URL": "[^"]*"' "$SETTINGS_FILE" 2>/dev/null | head -1 | sed 's/.*": "//;s/"//')
    if [[ "$CURRENT_GITLAB" == "<YOUR_GITLAB_API_URL>" ]] || [[ -z "$CURRENT_GITLAB" ]]; then
        ask "GitLab API URL (예: https://gitlab.com/api/v4, 없으면 Enter): "
        read -r GITLAB_URL
        if [[ -n "$GITLAB_URL" ]]; then
            sed -i '' "s|<YOUR_GITLAB_API_URL>|$GITLAB_URL|g" "$SETTINGS_FILE"
            log "GitLab URL 설정 완료"
        else
            warn "GitLab URL 미설정 — 나중에 settings.json에서 직접 수정"
        fi
    else
        info "GitLab URL 이미 설정됨"
    fi
else
    info "GitLab — 비활성화됨"
fi

# Obsidian Vault 경로 설정 (obsidian 모듈 활성화 시)
if [[ "${SELECTED[obsidian]}" == "true" ]]; then
    CURRENT_VAULT=$(grep -o 'Obsidian Vault: `[^`]*`' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null | sed 's/.*`//;s/`.*//')
    if [[ "$CURRENT_VAULT" == *"TODO"* ]] || [[ -z "$CURRENT_VAULT" ]]; then
        ask "Obsidian Vault 경로 (예: ~/Workspace/my-vault, 없으면 Enter): "
        read -r VAULT_PATH
        if [[ -n "$VAULT_PATH" ]]; then
            sed -i '' "s|<!-- TODO: Obsidian Vault 경로 설정 -->|$VAULT_PATH|" "$CLAUDE_DIR/CLAUDE.md"
            log "Obsidian Vault 경로 설정 완료: $VAULT_PATH"
        else
            warn "Obsidian Vault 미설정 — 나중에 CLAUDE.md에서 직접 수정"
        fi
    else
        info "Obsidian Vault 이미 설정됨: $CURRENT_VAULT"
    fi
else
    info "Obsidian — 비활성화됨"
fi

# ─────────────────────────────────────────────
# 5. 비활성 모듈 스킬 제거
# ─────────────────────────────────────────────
# 모듈별 관련 스킬 디렉토리
typeset -A MODULE_SKILLS=(
    gemini     "ask-gemini gemini-test"
    codex      "ask-codex codex-impl"
    gitlab     "create-mr"
    rag        "index-rag"
    playwright ""
    obsidian   "save-doc docs-update"
)

for mod in "${ALL_MODULES[@]}"; do
    if [[ "${SELECTED[$mod]}" == "true" ]]; then
        continue
    fi
    for skill_dir in ${(s: :)MODULE_SKILLS[$mod]}; do
        if [[ -n "$skill_dir" ]] && [[ -d "$CLAUDE_DIR/skills/$skill_dir" ]]; then
            rm -rf "$CLAUDE_DIR/skills/$skill_dir"
            info "  스킬 제거: skills/$skill_dir ($mod 비활성)"
        fi
    done
done

# ─────────────────────────────────────────────
# 6. 실행 권한 설정
# ─────────────────────────────────────────────
echo ""
log "실행 권한 설정 중..."
chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true
chmod +x "$CLAUDE_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$CLAUDE_DIR/statusline-agent.sh" 2>/dev/null || true
chmod +x "$CLAUDE_DIR/setup.sh" 2>/dev/null || true
chmod +x "$CLAUDE_DIR/agents/build-agents.sh" 2>/dev/null || true
info "  hooks/, scripts/, statusline-agent.sh, agents/build-agents.sh"

# ─────────────────────────────────────────────
# 7. 에이전트 빌드
# ─────────────────────────────────────────────
echo ""
if [ -f "$CLAUDE_DIR/agents/build-agents.sh" ]; then
    log "에이전트 빌드 실행 중..."
    (cd "$CLAUDE_DIR/agents" && ./build-agents.sh)
    log "에이전트 빌드 완료"
else
    warn "agents/build-agents.sh 없음 — 에이전트 빌드 건너뜀"
fi

# ─────────────────────────────────────────────
# 8. 런타임 디렉토리 생성
# ─────────────────────────────────────────────
log "런타임 디렉토리 생성..."
mkdir -p "$CLAUDE_DIR/projects"
mkdir -p "$CLAUDE_DIR/session-env"
mkdir -p "$CLAUDE_DIR/cache"
mkdir -p "$CLAUDE_DIR/paste-cache"

# ─────────────────────────────────────────────
# 9. 의존성 확인
# ─────────────────────────────────────────────
echo ""
echo "${BOLD}── 의존성 확인 ──${NC}"
echo ""

check_dep() {
    local name="$1"
    local install_hint="$2"
    if command -v "$name" &>/dev/null; then
        log "$name: $(command -v $name)"
    else
        warn "$name: 미설치 — $install_hint"
    fi
}

check_dep "jq"     "brew install jq (statusline용)"
check_dep "node"   "https://nodejs.org/ (MCP 서버용)"
check_dep "npx"    "npm install -g npx"

# 선택된 모듈의 의존성만 확인
[[ "${SELECTED[gemini]}" == "true" ]] && check_dep "gemini" "npm install -g @google/gemini-cli"
[[ "${SELECTED[codex]}" == "true" ]] && check_dep "codex"  "npm install -g @openai/codex"

# ─────────────────────────────────────────────
# 10. 플랫폼별 안내
# ─────────────────────────────────────────────
echo ""
if [[ "$(uname)" == "Darwin" ]]; then
    info "macOS — say/afplay 알림 사용 가능"
else
    warn "macOS 아님 — hooks의 say/afplay 명령이 동작하지 않습니다"
    warn "  hooks/*.sh에서 say/afplay 줄을 주석 처리하세요"
fi

# ─────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "${GREEN}  설정 완료! (v$VERSION)${NC}"
echo "========================================="
echo ""

# 설치된 모듈 요약
echo "  ${BOLD}설치된 모듈:${NC}"
echo -n "    코어"
for mod in "${ALL_MODULES[@]}"; do
    [[ "${SELECTED[$mod]}" == "true" ]] && echo -n ", $mod"
done
echo ""
echo ""

echo "  다음 단계:"
echo "    1. CLAUDE.md에서 TODO 항목을 자신의 환경에 맞게 수정"
echo "       - 프로젝트 목록/경로"
echo "       - Obsidian Vault 경로"
echo "       - 문서 디렉토리"
echo "    2. Claude Code 재시작"
echo "    3. 플러그인 설치: Claude Code에서 /install-plugin으로 설치"
echo ""

# 필요 플러그인 목록 (선택된 모듈 기반)
echo "  필요 플러그인:"
echo "    - superpowers, frontend-design, code-review-graph"
echo -n "    - claude-mem"
[[ "${SELECTED[codex]}" == "true" ]] && echo -n ", codex"
[[ "${SELECTED[gitlab]}" == "true" ]] && echo -n ", gitlab"
[[ "${SELECTED[playwright]}" == "true" ]] && echo -n ", playwright"
echo ""
echo "    - pr-review-toolkit, security-guidance, claude-md-management"
echo ""

# 나중에 모듈 추가/제거 안내
echo "  ${DIM}모듈을 나중에 변경하려면: ./setup.sh --force${NC}"
echo ""
