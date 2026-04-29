#!/bin/zsh
# Claude Code 설정 내보내기/공유 스크립트
#
# 사용법:
#   export-claude-config.sh                    # Claude 설정만 내보냄
#   export-claude-config.sh --dry-run          # 파일 목록만 출력
#   export-claude-config.sh -o ~/Desktop       # 출력 경로 지정
#   export-claude-config.sh --force            # 최종 감사 경고 무시하고 진행
#
# 주의: Gemini/Codex/Gemma(로컬 Ollama) 관련 설정은 개인 전용이므로 자동 제외됨

set -eo pipefail
setopt null_glob 2>/dev/null || true

# ─── 색상 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo "${CYAN}▸${NC} $1" }
ok()    { echo "${GREEN}✓${NC} $1" }
warn()  { echo "${YELLOW}!${NC} $1" }
err()   { echo "${RED}✗${NC} $1" >&2 }
header() { echo "\n${BOLD}═══ $1 ═══${NC}\n" }

# ─── 옵션 파싱 ───
DRY_RUN=false
FORCE=false
OUT_DIR="$HOME/Desktop"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=true; shift ;;
        --force)        FORCE=true; shift ;;
        -o|--output)    OUT_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "사용법: export-claude-config.sh [옵션]"
            echo ""
            echo "옵션:"
            echo "  --dry-run        내보낼 파일 목록만 출력"
            echo "  --force          최종 감사 경고 무시하고 진행"
            echo "  -o, --output     출력 디렉토리 (기본: ~/Desktop)"
            echo "  -h, --help       도움말"
            echo ""
            echo "Gemini/Codex/Gemma 관련 파일은 개인 전용이므로 자동 제외됨"
            exit 0
            ;;
        *) err "알 수 없는 옵션: $1"; exit 1 ;;
    esac
done

# ─── 민감 파일 패턴 ───
SENSITIVE_PATTERNS=(
    "*.backup*"
    ".claude.json"
    "settings.local.json"
    "security_warnings_state_*"
    "mcp-needs-auth-cache.json"
    "stats-cache.json"
    "antigravity-workspace.json"
    "statsig/*"
    "telemetry/*"
    "transcripts/*"
    "sessions/*"
    "session-env/*"
    "cache/*"
    "paste-cache/*"
    "backups/*"
    "debug/*"
    "todos/*"
    "tasks/*"
    "plans/*"
    "file-history/*"
    "shell-snapshots/*"
    "lancedb/*"
    "ide/*"
    "workspace-root/*"
    ".obsidian/*"
    ".idea/*"
    "plugins/cache/*"
    "projects/*/memory/*"
)

# ─── 수집 대상 ───
CLAUDE_DIR="$HOME/.claude"

# 개인 전용 키워드 (Gemma 로컬 Ollama, Codex/Gemini 외부 CLI 보조 파일)
# 파일명/경로에 이 키워드가 포함되면 수집 단계에서 제외
# 대소문자 무시
PERSONAL_KEYWORDS=("gemma" "gemini" "codex")

is_personal() {
    local name="${1:l}"   # lowercase (zsh)
    for k in "${PERSONAL_KEYWORDS[@]}"; do
        [[ "$name" == *"$k"* ]] && return 0
    done
    return 1
}

collect_claude_files() {
    local files=()

    # 핵심 설정 (최상위 단일 파일)
    local top_files=(
        "CLAUDE.md"
        "AGENTS.md"
        "README.md"
        "CHEATSHEET.md"
        "VERSION"
        "settings.json"
        "settings.json.example"
        "settings.local.json.example"
        "docs-config.yaml"
        "docs-config.yaml.example"
        "setup.sh"
        "package.sh"
        "statusline-agent.sh"
    )
    for f in "${top_files[@]}"; do
        [[ -f "$CLAUDE_DIR/$f" ]] && files+=("$f")
    done

    # 에이전트 (재귀: 하위 knowledge/, docs/, builds/, src/ 모두 포함)
    # 단 파일명 기준 is_personal 적용 (디렉토리 이름은 매칭 안 함)
    if [[ -d "$CLAUDE_DIR/agents" ]]; then
        while IFS= read -r f; do
            local rel="${f#$CLAUDE_DIR/}"
            local base=$(basename "$f")
            is_personal "$base" && continue
            # 백업/임시 파일 제외
            [[ "$base" == .DS_Store ]] && continue
            [[ "$base" == *.bak ]] && continue
            [[ "$base" == *.bak.* ]] && continue
            [[ "$rel" == *".last-build"* ]] && continue
            files+=("$rel")
        done < <(find "$CLAUDE_DIR/agents" -type f \( -name "*.md" -o -name "*.json" -o -name "*.sh" \) 2>/dev/null)
    fi

    # 스킬 (ask-gemma/ask-gemini/ask-codex 디렉토리 제외 — 디렉토리명에 키워드 매칭)
    if [[ -d "$CLAUDE_DIR/skills" ]]; then
        for f in "$CLAUDE_DIR"/skills/*.md; do
            [[ -f "$f" ]] || continue
            local base=$(basename "$f")
            is_personal "$base" && continue
            files+=("skills/$base")
        done
        for d in "$CLAUDE_DIR"/skills/*/; do
            [[ -d "$d" ]] || continue
            local dname=$(basename "$d")
            is_personal "$dname" && continue
            while IFS= read -r f; do
                local rel="${f#$CLAUDE_DIR/}"
                local fbase=$(basename "$f")
                [[ "$fbase" == .DS_Store ]] && continue
                files+=("$rel")
            done < <(find "$d" -type f \( -name "*.md" -o -name "*.sh" -o -name "*.json" \) 2>/dev/null)
        done
    fi

    # 커맨드
    if [[ -d "$CLAUDE_DIR/commands" ]]; then
        for f in "$CLAUDE_DIR"/commands/*.md; do
            [[ -f "$f" ]] || continue
            local base=$(basename "$f")
            is_personal "$base" && continue
            files+=("commands/$base")
        done
    fi

    # 워크플로우
    if [[ -d "$CLAUDE_DIR/workflows" ]]; then
        for f in "$CLAUDE_DIR"/workflows/*.md; do
            [[ -f "$f" ]] || continue
            local base=$(basename "$f")
            is_personal "$base" && continue
            files+=("workflows/$base")
        done
    fi

    # 디버깅 가이드
    if [[ -d "$CLAUDE_DIR/debugging-guides" ]]; then
        for f in "$CLAUDE_DIR"/debugging-guides/*.md; do
            [[ -f "$f" ]] || continue
            local base=$(basename "$f")
            is_personal "$base" && continue
            files+=("debugging-guides/$base")
        done
    fi

    # 스크립트 (gemma-*, gemini-*, codex-* 제외)
    if [[ -d "$CLAUDE_DIR/scripts" ]]; then
        for f in "$CLAUDE_DIR"/scripts/*.sh; do
            [[ -f "$f" ]] || continue
            local base=$(basename "$f")
            is_personal "$base" && continue
            files+=("scripts/$base")
        done
        # python 스크립트도 포함
        for f in "$CLAUDE_DIR"/scripts/*.py; do
            [[ -f "$f" ]] || continue
            local base=$(basename "$f")
            is_personal "$base" && continue
            files+=("scripts/$base")
        done
    fi

    # 훅 (gemma-*, codex-*, gemini-* 제외, _disabled/ 도 제외 — 비활성화된 파일)
    if [[ -d "$CLAUDE_DIR/hooks" ]]; then
        for f in "$CLAUDE_DIR"/hooks/*.sh; do
            [[ -f "$f" ]] || continue
            local base=$(basename "$f")
            is_personal "$base" && continue
            files+=("hooks/$base")
        done
    fi

    # 문서 (docs/ 는 공유 가능한 공식 문서. is_personal 필터 미적용)
    # 단 파일 단위 시크릿 마스킹은 scrub_sensitive 가 처리
    if [[ -d "$CLAUDE_DIR/docs" ]]; then
        while IFS= read -r f; do
            local rel="${f#$CLAUDE_DIR/}"
            local base=$(basename "$f")
            [[ "$base" == .DS_Store ]] && continue
            files+=("$rel")
        done < <(find "$CLAUDE_DIR/docs" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) 2>/dev/null)
    fi

    # identity-hub 설정 (사내 공유 — settings.local.json 만 제외)
    if [[ -d "$CLAUDE_DIR/identity-hub" ]]; then
        while IFS= read -r f; do
            local rel="${f#$CLAUDE_DIR/}"
            local base=$(basename "$f")
            [[ "$base" == settings.local.json ]] && continue
            [[ "$base" == .DS_Store ]] && continue
            files+=("$rel")
        done < <(find "$CLAUDE_DIR/identity-hub" -type f \( -name "*.md" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)
    fi

    # 프로젝트별 CLAUDE.md (메모리 제외)
    if [[ -d "$CLAUDE_DIR/projects" ]]; then
        while IFS= read -r f; do
            local rel="${f#$CLAUDE_DIR/}"
            files+=("$rel")
        done < <(find "$CLAUDE_DIR/projects" -name "CLAUDE.md" -not -path "*/memory/*" 2>/dev/null)
    fi

    # 프로젝트별 설정 (settings.json만, settings.local.json 제외)
    if [[ -d "$CLAUDE_DIR/projects" ]]; then
        while IFS= read -r f; do
            local rel="${f#$CLAUDE_DIR/}"
            files+=("$rel")
        done < <(find "$CLAUDE_DIR/projects" -name "settings.json" 2>/dev/null)
    fi

    # 플러그인 목록 (캐시 제외, 설정만)
    if [[ -d "$CLAUDE_DIR/plugins" ]]; then
        for f in "$CLAUDE_DIR"/plugins/*.json; do
            [[ -f "$f" ]] && files+=("plugins/$(basename "$f")")
        done
    fi

    # 팀 설정 (사내 공유 — 개인 키워드 inbox만 제외)
    if [[ -d "$CLAUDE_DIR/teams" ]]; then
        while IFS= read -r f; do
            local rel="${f#$CLAUDE_DIR/}"
            is_personal "$rel" && continue
            files+=("$rel")
        done < <(find "$CLAUDE_DIR/teams" -type f 2>/dev/null)
    fi

    printf '%s\n' "${files[@]}"
}

# ─── 민감 정보 스크러빙 ───
# 모든 텍스트 파일(.json/.md/.sh/.yaml/.yml/.env)에 적용
# 바이너리 파일은 그대로 복사
scrub_sensitive() {
    local file="$1"
    local base="$(basename "$file")"
    local ext="${base##*.}"

    # 텍스트 파일 판정
    case "$ext" in
        json|md|sh|yaml|yml|env|toml|conf|ini|txt)
            # 키-값 형태 비밀 마스킹
            #   JSON/YAML:  "field": "value"  →  "field": "REDACTED"
            #   ENV/SHELL:  FIELD=value        →  FIELD=REDACTED
            # 대상 필드: api_key, apikey, api-key, token, access_token, refresh_token,
            #            auth_token, bearer, secret, client_secret, private_key,
            #            access_key, password, passwd, passphrase, webhook_secret,
            #            signing_secret, encryption_key, session_token
            # 고엔트로피 토큰 프리픽스: sk-, sk_, ghp_, gho_, ghs_, xox[baprs]-, AKIA
            sed -E \
                -e 's/(("|'\'')?(api[_-]?key|apikey|access[_-]?token|refresh[_-]?token|auth[_-]?token|session[_-]?token|bearer|client[_-]?secret|webhook[_-]?secret|signing[_-]?secret|encryption[_-]?key|private[_-]?key|access[_-]?key|secret|token|password|passwd|passphrase)("|'\'')?[[:space:]]*[:=][[:space:]]*)("|'\'')[^"'\'']{8,}("|'\'')/\1"REDACTED"/Ig' \
                -e 's/((^|[[:space:]]|export[[:space:]]+)(API[_-]?KEY|APIKEY|ACCESS[_-]?TOKEN|REFRESH[_-]?TOKEN|AUTH[_-]?TOKEN|SESSION[_-]?TOKEN|BEARER|CLIENT[_-]?SECRET|WEBHOOK[_-]?SECRET|SIGNING[_-]?SECRET|ENCRYPTION[_-]?KEY|PRIVATE[_-]?KEY|ACCESS[_-]?KEY|SECRET|TOKEN|PASSWORD|PASSWD|PASSPHRASE)[[:space:]]*=[[:space:]]*)[^[:space:]"'\'']{8,}/\1REDACTED/g' \
                -e 's/(sk-|sk_|ghp_|gho_|ghs_|ghu_|ghr_)[A-Za-z0-9_-]{20,}/\1REDACTED/g' \
                -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/xoxREDACTED/g' \
                -e 's/AKIA[0-9A-Z]{16}/AKIAREDACTED/g' \
                "$file"
            ;;
        *)
            cat "$file"
            ;;
    esac
}

# ─── 최종 감사: ZIP 직전 잔존 비밀 스캔 ───
audit_tmpdir() {
    local dir="$1"
    local findings_file="$dir/.audit_findings"
    : > "$findings_file"

    # 고신뢰 비밀 패턴 (REDACTED는 무시)
    local patterns=(
        '(sk-|sk_|ghp_|gho_|ghs_)[A-Za-z0-9_-]{20,}'
        'xox[baprs]-[A-Za-z0-9-]{10,}'
        'AKIA[0-9A-Z]{16}'
        '-----BEGIN[A-Z ]*PRIVATE KEY-----'
        'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
    )

    for pat in "${patterns[@]}"; do
        grep -rInE "$pat" "$dir" 2>/dev/null \
            | grep -v 'REDACTED' \
            | grep -v '.audit_findings' \
            >> "$findings_file" || true
    done

    # 중엔트로피: key=VALUE 형태에서 긴 영숫자 (예제 문자열 제외 위해 24자 이상)
    grep -rInE '(API[_-]?KEY|TOKEN|SECRET|PASSWORD)[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9+/_=-]{24,}' "$dir" 2>/dev/null \
        | grep -v 'REDACTED' \
        | grep -v '.audit_findings' \
        | grep -vE '(test|example|your[_-]?|changeme|xxx|dummy|fake|sample|placeholder)' \
        >> "$findings_file" || true

    if [[ -s "$findings_file" ]]; then
        warn "최종 감사: 잔존 가능성 있는 민감 문자열 감지"
        echo ""
        cat "$findings_file" | head -20
        echo ""
        local count=$(wc -l < "$findings_file" | tr -d ' ')
        warn "총 ${count}건 (상위 20건 표시)"
        rm -f "$findings_file"
        return 1
    fi
    rm -f "$findings_file"
    return 0
}

# ─── 메인 ───
header "Claude Code 설정 내보내기"

# Claude 파일 수집
claude_files=()
while IFS= read -r f; do
    [[ -n "$f" ]] && claude_files+=("$f")
done < <(collect_claude_files)

# 통계
local total=${#claude_files[@]}
info "Claude: ${#claude_files[@]}개 파일"
echo ""

# Dry run
if $DRY_RUN; then
    header "내보낼 파일 목록"

    echo "${BOLD}[Claude]${NC}"
    for f in "${claude_files[@]}"; do
        echo "  ${DIM}~/.claude/${NC}$f"
    done

    echo ""
    info "총 ${total}개 파일 (dry-run, 실제 내보내기 안 함)"
    info "Gemma/Gemini/Codex 보조 파일은 자동 제외됨"
    exit 0
fi

# ZIP 생성
TIMESTAMP=$(date +%Y%m%d-%H%M)
ZIP_NAME="claude-code-config-${TIMESTAMP}.zip"
ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"

# 임시 디렉토리
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

# Claude 파일 복사
for f in "${claude_files[@]}"; do
    local src="$CLAUDE_DIR/$f"
    local dst="$TMPDIR/claude/$f"
    mkdir -p "$(dirname "$dst")"
    scrub_sensitive "$src" > "$dst"
done

# ─── 최종 감사 ───
header "최종 감사"
if ! audit_tmpdir "$TMPDIR"; then
    if $FORCE; then
        warn "--force 지정: 감사 경고 무시하고 진행"
    else
        echo ""
        err "민감 문자열이 감지됨. 계속하려면 --force 재실행 또는 패턴 확인 후 원본 수정"
        exit 2
    fi
else
    ok "잔존 비밀 없음"
fi

# 매니페스트 생성
cat > "$TMPDIR/MANIFEST.md" <<MANIFEST
# Claude Code 설정 내보내기

- 내보낸 시각: $(date '+%Y-%m-%d %H:%M:%S')
- 호스트: $(hostname)
- Claude 파일: ${#claude_files[@]}개

## 적용 방법

\`\`\`bash
# 1. 압축 해제
unzip ${ZIP_NAME} -d ~/claude-config-import

# 2. Claude 설정 복사 (기존 설정 백업 권장)
cp -r ~/claude-config-import/claude/* ~/.claude/

# settings.local.json은 포함되지 않음 — 직접 생성 필요
# API 키/토큰은 REDACTED 처리됨 — 직접 입력 필요
\`\`\`

## 제외된 항목

- \`settings.local.json\` (로컬 전용)
- \`.claude.json\` (세션/인증)
- \`memory/\` (개인 메모리)
- \`transcripts/\`, \`sessions/\` (대화 기록)
- \`plugins/cache/\` (설치 캐시, 용량 큼)
- \`backups/\`, \`cache/\`, \`lancedb/\` (임시 데이터)
- 개인 전용 보조 파일 (이름에 \`gemma-\`, \`gemini-\`, \`codex-\`, \`ask-gemma\`, \`ask-gemini\`, \`ask-codex\` 포함):
  - 로컬 Ollama Gemma 훅/스크립트
  - Gemini/Codex CLI 보조 스킬·훅·문서

## 마스킹 처리

모든 텍스트 파일(.json/.md/.sh/.yaml/.env 등)에 스크러빙 적용:
- 키-값 필드: api_key, token, secret, password, bearer, client_secret, private_key, access_key, refresh_token, session_token, webhook_secret, signing_secret, encryption_key, passphrase
- 고엔트로피 프리픽스: sk-, ghp_, gho_, ghs_, xox[baprs]-, AKIA
- → 각각 REDACTED 또는 프리픽스+REDACTED로 치환

ZIP 생성 직전 최종 감사 수행. 잔존 비밀 발견 시 중단 (\`--force\`로 강제 진행 가능).
MANIFEST

# ZIP 압축
cd "$TMPDIR"
zip -rq "$ZIP_PATH" . -x "*.DS_Store"

# 결과
echo ""
ok "내보내기 완료: ${ZIP_PATH}"
info "크기: $(du -h "$ZIP_PATH" | cut -f1)"
info "파일 수: ${total}개"
echo ""
warn "settings.local.json, API 키, 메모리는 제외됨"
