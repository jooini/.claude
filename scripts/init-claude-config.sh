#!/bin/zsh
# Claude Code 프로젝트 설정 생성기
# wb-platform-backend 구조 기반 템플릿
#
# 사용법:
#   init-claude-config.sh [프로젝트경로]        # 대화형
#   init-claude-config.sh ~/Workspace/project   # 경로 지정
#   init-claude-config.sh --auto <경로>         # 완전 자동 (질문 없음)
#   init-claude-config.sh --rebuild <경로>       # 기존 설정 백업 후 전체 재생성
#   init-claude-config.sh --audit               # 전체 프로젝트 감사
#   init-claude-config.sh --batch dir1 dir2...  # 일괄 처리 (다중 자동)

set -eo pipefail
setopt null_glob 2>/dev/null || true

# ─── 자동 확인 모드 (batch에서 사용) ───
AUTO_CONFIRM=${AUTO_CONFIRM:-false}

# ─── 색상 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo "${CYAN}▸${NC} $1" }
ok()    { echo "${GREEN}✓${NC} $1" }
warn()  { echo "${YELLOW}!${NC} $1" }
err()   { echo "${RED}✗${NC} $1" >&2 }
skip()  { echo "${DIM}─${NC} $1" }
ask()   { echo -n "${BOLD}? ${NC}$1: " }
header() { echo "\n${BOLD}═══ $1 ═══${NC}\n" }
section() { echo "\n${BLUE}── $1 ──${NC}" }

# 자동 확인: AUTO_CONFIRM=true면 default_yes 기준 자동 응답
# confirm_yes "메시지" → 기본 Y (Y/n)
# confirm_no "메시지"  → 기본 N (y/N)
confirm_yes() {
    if $AUTO_CONFIRM; then
        info "(자동 확인) $1 → Y"
        return 0
    fi
    ask "$1 (Y/n)"
    read CONFIRM
    [[ "$CONFIRM" != "n" && "$CONFIRM" != "N" ]]
}
confirm_no() {
    if $AUTO_CONFIRM; then
        info "(자동 확인) $1 → Y"
        return 0
    fi
    ask "$1 (y/N)"
    read CONFIRM
    [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]
}

# ─── 필수 파일 목록 ───
REQUIRED_FILES=(
    ".claude/CLAUDE.md"
    ".claude/agents/dev.md"
    ".claude/agents/team.md"
    ".claude/settings.local.json"
    "docs/backlog.md"
    "docs/README.md"
    "docs/decisions.md"
)

# ─── 필수 섹션 (CLAUDE.md) ───
REQUIRED_SECTIONS_CLAUDE=(
    "프로젝트 개요"
    "문서 맵\|디렉토리 구조"
    "빌드/실행"
    "아키텍처 규칙"
    "Claude Code 규칙"
)

# ─── 필수 섹션 (dev.md) ───
REQUIRED_SECTIONS_DEV=(
    "세션 시작 프로토콜"
    "프로젝트 특성"
    "태스크 라우팅"
    "에스컬레이션"
    "컨텍스트 패싱"
    "워크플로우"
    "태스크 관리"
)

# ═══════════════════════════════════════════
# 감사 함수: 프로젝트 설정 상태 진단
# ═══════════════════════════════════════════
audit_project() {
    local dir="$1"
    local name=$(basename "$dir")
    local score=0
    local max_score=0
    local issues=()
    local missing_files=()

    # 파일 존재 여부
    for f in "${REQUIRED_FILES[@]}"; do
        max_score=$((max_score + 1))
        if [[ -f "$dir/$f" ]]; then
            score=$((score + 1))
        else
            missing_files+=("$f")
        fi
    done

    # CLAUDE.md 섹션 검사
    if [[ -f "$dir/.claude/CLAUDE.md" ]]; then
        for sec in "${REQUIRED_SECTIONS_CLAUDE[@]}"; do
            max_score=$((max_score + 1))
            if grep -q "## $sec\|## .*$sec" "$dir/.claude/CLAUDE.md" 2>/dev/null; then
                score=$((score + 1))
            else
                issues+=("CLAUDE.md: '${sec}' 섹션 누락")
            fi
        done

        # TODO 잔존 확인
        local todo_count
        todo_count=$(grep -c "TODO" "$dir/.claude/CLAUDE.md" 2>/dev/null || true)
        todo_count=${todo_count:-0}
        if [[ $todo_count -gt 0 ]]; then
            issues+=("CLAUDE.md: TODO ${todo_count}개 미완성")
        fi

        # 디렉토리 구조가 비어있는지
        if grep -q '<!-- TODO: 프로젝트 디렉토리 구조' "$dir/.claude/CLAUDE.md" 2>/dev/null; then
            issues+=("CLAUDE.md: 디렉토리 구조 미작성")
        fi
    fi

    # dev.md 섹션 검사
    if [[ -f "$dir/.claude/agents/dev.md" ]]; then
        for sec in "${REQUIRED_SECTIONS_DEV[@]}"; do
            max_score=$((max_score + 1))
            if grep -q "$sec" "$dir/.claude/agents/dev.md" 2>/dev/null; then
                score=$((score + 1))
            else
                issues+=("dev.md: '${sec}' 섹션 누락")
            fi
        done

        # frontmatter 확인
        max_score=$((max_score + 1))
        if head -1 "$dir/.claude/agents/dev.md" | grep -q "^---" 2>/dev/null; then
            score=$((score + 1))
        else
            issues+=("dev.md: YAML frontmatter 누락")
        fi
    fi

    # team.md 연관 프로젝트 확인
    if [[ -f "$dir/.claude/agents/team.md" ]]; then
        max_score=$((max_score + 1))
        if grep -q "TODO" "$dir/.claude/agents/team.md" 2>/dev/null; then
            issues+=("team.md: 연관 프로젝트 미작성")
        else
            score=$((score + 1))
        fi
    fi

    # settings.local.json 유효성
    if [[ -f "$dir/.claude/settings.local.json" ]]; then
        max_score=$((max_score + 1))
        if python3 -c "import json; json.load(open('$dir/.claude/settings.local.json'))" 2>/dev/null; then
            score=$((score + 1))
        else
            issues+=("settings.local.json: JSON 파싱 에러")
        fi
    fi

    # 태스크 관리 디렉토리 검사
    max_score=$((max_score + 1))
    if [[ -d "$dir/docs/active" && -d "$dir/docs/archive" ]]; then
        score=$((score + 1))
    else
        issues+=("docs/active/ 또는 docs/archive/ 누락 — 태스크 관리 불가")
    fi

    # hooks 검사
    max_score=$((max_score + 1))
    if [[ -d "$dir/.claude/hooks" ]] && ls "$dir/.claude/hooks/"*.sh &>/dev/null; then
        score=$((score + 1))
    else
        issues+=(".claude/hooks/ 누락 또는 비어있음")
    fi

    # .gitignore에 Claude 항목 존재 여부
    if [[ -d "$dir/.git" ]]; then
        max_score=$((max_score + 1))
        if [[ -f "$dir/.gitignore" ]] && grep -qF "settings.local.json" "$dir/.gitignore" 2>/dev/null; then
            score=$((score + 1))
        else
            issues+=(".gitignore: settings.local.json 미등록 — 민감 설정 노출 위험")
        fi
    fi

    # backlog 항목 수
    if [[ -f "$dir/docs/backlog.md" ]]; then
        local bl_count
        bl_count=$(grep -c '^- \[ \]' "$dir/docs/backlog.md" 2>/dev/null || true)
        bl_count=${bl_count:-0}
        if [[ $bl_count -eq 0 ]]; then
            issues+=("backlog.md: 미완료 항목 없음 — 백로그 채우기 필요")
        fi
    fi

    # 결과 출력
    local pct=0
    [[ $max_score -gt 0 ]] && pct=$((score * 100 / max_score))

    local color="$RED"
    [[ $pct -ge 50 ]] && color="$YELLOW"
    [[ $pct -ge 80 ]] && color="$GREEN"

    echo "${color}${pct}%${NC} ${BOLD}${name}${NC} (${score}/${max_score})"

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        for mf in "${missing_files[@]}"; do
            echo "    ${RED}✗${NC} 파일 없음: $mf"
        done
    fi

    if [[ ${#issues[@]} -gt 0 ]]; then
        for iss in "${issues[@]}"; do
            echo "    ${YELLOW}!${NC} $iss"
        done
    fi

    # 반환: 0이면 완전, 1이면 미완성
    [[ ${#missing_files[@]} -eq 0 ]] && return 0 || return 1
}

# ═══════════════════════════════════════════
# 스택 자동 감지
# ═══════════════════════════════════════════
detect_stack() {
    local dir="$1"

    # 헬퍼: 루트 우선, 없으면 depth 2까지 탐색
    _find_file() {
        local base="$1" name="$2"
        [[ -f "$base/$name" ]] && { echo "$base/$name"; return; }
        find "$base" -maxdepth 2 -name "$name" -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.worktrees/*' 2>/dev/null | head -1
    }

    # 1단계: 루트에 있는 빌드 파일로 즉시 판정 (가장 정확)
    # iOS/macOS Xcode 프로젝트 (*.xcodeproj, *.xcworkspace, Podfile, Package.swift)
    # 루트 우선 (.xcodeproj 내부의 project.xcworkspace 배제)
    local xcproj=$(find "$dir" -maxdepth 1 -name "*.xcodeproj" 2>/dev/null | head -1)
    if [[ -n "$xcproj" ]]; then
        echo "ios"
        return
    fi
    local xcws=$(find "$dir" -maxdepth 1 -name "*.xcworkspace" 2>/dev/null | head -1)
    if [[ -n "$xcws" ]]; then
        echo "ios"
        return
    fi
    if [[ -f "$dir/Podfile" || -f "$dir/Podfile.lock" ]]; then
        echo "ios"
        return
    fi
    if [[ -f "$dir/Package.swift" ]]; then
        # iOS/macOS 플랫폼 명시 시 ios, 아니면 swift 라이브러리
        if grep -qE "platforms?:.*\.(iOS|macOS|tvOS|watchOS)" "$dir/Package.swift" 2>/dev/null; then
            echo "ios"
        else
            echo "swift-lib"
        fi
        return
    fi

    # Keycloak 테마 프로젝트 (themes/ + keycloak.conf 또는 themes/ + docker-compose.yml with keycloak)
    if [[ -d "$dir/themes" && ( -f "$dir/conf/keycloak.conf" || -d "$dir/realm-config" ) ]]; then
        # providers-src에 gradle 빌드가 있으면 keycloak-spi, 아니면 docker (테마 전용)
        local spi_gradle=$(find "$dir/providers-src" -maxdepth 3 -name "build.gradle.kts" -o -name "build.gradle" 2>/dev/null | head -1)
        if [[ -n "$spi_gradle" ]]; then
            echo "keycloak-spi"
        else
            echo "docker"
        fi
        return
    fi
    [[ -f "$dir/pyproject.toml" ]] && { grep -q "fastapi" "$dir/pyproject.toml" 2>/dev/null && echo "fastapi" || echo "python-lib"; return; }
    [[ -f "$dir/build.gradle.kts" || -f "$dir/build.gradle" ]] && {
        local gf="$dir/build.gradle.kts"; [[ ! -f "$gf" ]] && gf="$dir/build.gradle"
        grep -q "org.springframework.boot" "$gf" 2>/dev/null && { echo "springboot"; return; }
        grep -q "keycloak" "$gf" 2>/dev/null && { echo "keycloak-spi"; return; }
        echo "gradle"; return
    }
    [[ -f "$dir/pom.xml" ]] && { grep -q "spring-boot" "$dir/pom.xml" 2>/dev/null && echo "springboot" || echo "gradle"; return; }
    [[ -f "$dir/go.mod" ]] && { echo "go"; return; }
    [[ -f "$dir/Cargo.toml" ]] && { echo "rust"; return; }
    [[ -f "$dir/composer.json" ]] && { echo "php"; return; }
    [[ -f "$dir/package.json" ]] && {
        grep -q '"next"' "$dir/package.json" 2>/dev/null && { echo "nextjs"; return; }
        grep -q '"react"' "$dir/package.json" 2>/dev/null && { echo "react"; return; }
        echo "node"; return
    }

    # 1.4단계: Terraform/OpenTofu (루트 또는 서브 모듈에 .tf 존재)
    # 루트 레벨 *.tf
    local tf_root=$(find "$dir" -maxdepth 1 -name "*.tf" -not -path '*/.terraform/*' 2>/dev/null | head -1)
    if [[ -n "$tf_root" ]]; then
        echo "terraform"
        return
    fi
    # 일반적 테라폼 레이아웃: modules/ + envs/ 또는 bootstrap/ + .tool-versions(terraform)
    if [[ -d "$dir/modules" || -d "$dir/envs" || -d "$dir/bootstrap" || -d "$dir/stacks" || -d "$dir/live" ]]; then
        local tf_sub=$(find "$dir/modules" "$dir/envs" "$dir/bootstrap" "$dir/stacks" "$dir/live" -maxdepth 3 -name "*.tf" -not -path '*/.terraform/*' 2>/dev/null | head -1)
        if [[ -n "$tf_sub" ]]; then
            echo "terraform"
            return
        fi
    fi
    # .tflint.hcl / .terraform-version / .tool-versions(terraform) 힌트
    if [[ -f "$dir/.tflint.hcl" || -f "$dir/.terraform-version" ]]; then
        echo "terraform"
        return
    fi
    if [[ -f "$dir/.tool-versions" ]] && grep -qiE '^(terraform|opentofu)\b' "$dir/.tool-versions" 2>/dev/null; then
        echo "terraform"
        return
    fi

    # 1.4.5단계: monorepo 감지 (루트에 manifest 없고 워크스페이스 마커 있음)
    # — pnpm-workspace.yaml / turbo.json / lerna.json / nx.json / rush.json
    # — apps/ 또는 packages/ 디렉토리 안에 실제 프로젝트
    local is_monorepo=false
    if [[ -f "$dir/pnpm-workspace.yaml" || -f "$dir/turbo.json" || -f "$dir/lerna.json" || -f "$dir/nx.json" || -f "$dir/rush.json" ]]; then
        is_monorepo=true
    elif [[ -f "$dir/package.json" ]] && grep -q '"workspaces"' "$dir/package.json" 2>/dev/null; then
        is_monorepo=true
    fi
    if $is_monorepo; then
        # 자식 앱 스택을 모아 가장 빈도 높은 것 우선, 단 React/Next가 있으면 frontend 우선
        local _next_count=0 _react_count=0 _py_count=0 _node_count=0
        for sub in "$dir/apps"/* "$dir/packages"/*; do
            [[ -d "$sub" ]] || continue
            if [[ -f "$sub/package.json" ]]; then
                grep -q '"next"' "$sub/package.json" 2>/dev/null && _next_count=$((_next_count+1)) && continue
                grep -q '"react"' "$sub/package.json" 2>/dev/null && _react_count=$((_react_count+1)) && continue
                _node_count=$((_node_count+1))
            fi
            if [[ -f "$sub/pyproject.toml" ]]; then
                _py_count=$((_py_count+1))
            fi
        done
        # 혼합 monorepo (Next + Python) → nextjs 우선 (DEV_AGENT_TYPE frontend-developer)
        if (( _next_count > 0 )); then
            echo "monorepo-nextjs"
            return
        elif (( _react_count > 0 )); then
            echo "monorepo-react"
            return
        elif (( _py_count > 0 )); then
            echo "monorepo-python"
            return
        elif (( _node_count > 0 )); then
            echo "monorepo-node"
            return
        fi
    fi

    # 1.5단계: 루트 docker-compose (서브디렉토리 탐색보다 우선)
    if [[ -f "$dir/docker-compose.yml" || -f "$dir/docker-compose.yaml" || -f "$dir/compose.yml" ]]; then
        echo "docker"
        return
    fi

    # 2단계: 서브디렉토리 탐색 (루트에 없을 때)
    local pyproject=$(_find_file "$dir" "pyproject.toml")
    if [[ -n "$pyproject" ]]; then
        grep -q "fastapi" "$pyproject" 2>/dev/null && echo "fastapi" || echo "python-lib"
        return
    fi

    local gradle=$(_find_file "$dir" "build.gradle.kts")
    [[ -z "$gradle" ]] && gradle=$(_find_file "$dir" "build.gradle")
    if [[ -n "$gradle" ]]; then
        grep -q "org.springframework.boot" "$gradle" 2>/dev/null && { echo "springboot"; return; }
        grep -q "keycloak" "$gradle" 2>/dev/null && { echo "keycloak-spi"; return; }
        echo "gradle"; return
    fi

    local pom=$(_find_file "$dir" "pom.xml")
    if [[ -n "$pom" ]]; then
        grep -q "spring-boot" "$pom" 2>/dev/null && echo "springboot" || echo "gradle"
        return
    fi

    local gomod=$(_find_file "$dir" "go.mod")
    [[ -n "$gomod" ]] && { echo "go"; return; }

    local cargo=$(_find_file "$dir" "Cargo.toml")
    [[ -n "$cargo" ]] && { echo "rust"; return; }

    local composer=$(_find_file "$dir" "composer.json")
    [[ -n "$composer" ]] && { echo "php"; return; }

    local pkgjson=$(_find_file "$dir" "package.json")
    if [[ -n "$pkgjson" ]]; then
        grep -q '"next"' "$pkgjson" 2>/dev/null && { echo "nextjs"; return; }
        grep -q '"react"' "$pkgjson" 2>/dev/null && { echo "react"; return; }
        echo "node"; return
    fi

    # Docker - subdirectories (루트는 1.5단계에서 이미 체크)
    local compose_found=$(find "$dir" -maxdepth 2 \( -name "docker-compose*.yml" -o -name "compose.yml" \) -not -path '*/.git/*' 2>/dev/null | head -1)
    if [[ -n "$compose_found" ]]; then
        echo "docker"
        return
    fi
    if [[ -f "$dir/Dockerfile" || -f "$dir/deploy.sh" || -f "$dir/build.sh" ]]; then
        echo "docker"
        return
    fi
    # Fallback: check existing CLAUDE.md for stack hint
    if [[ -f "$dir/.claude/CLAUDE.md" ]]; then
        if grep -qi "docker\|인프라\|배포\|deploy" "$dir/.claude/CLAUDE.md" 2>/dev/null; then
            echo "docker"
            return
        fi
    fi

    echo "unknown"
}

# ═══════════════════════════════════════════
# 역할 자동 감지
# ═══════════════════════════════════════════
detect_role() {
    local dir="$1"
    local name=$(basename "$dir")

    # 1. 기존 CLAUDE.md 역할 (볼드/일반 모두 매칭)
    if [[ -f "$dir/.claude/CLAUDE.md" ]]; then
        # | 역할 | 값 | 또는 | **역할** | 값 | 패턴
        local desc=$(grep -E '\|\s*\*{0,2}역할\*{0,2}\s*\|' "$dir/.claude/CLAUDE.md" 2>/dev/null | grep -v '라이브러리' | head -1)
        if [[ -n "$desc" ]]; then
            # 두 번째 | 이후 ~ 세 번째 | 이전 추출
            desc=$(echo "$desc" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
            [[ -n "$desc" && "$desc" != *"---"* && "$desc" != *"TODO"* && ${#desc} -gt 2 ]] && { echo "$desc"; return; }
        fi
    fi

    # 2. pyproject.toml description (루트 + 서브)
    local pyproject=$(find "$dir" -maxdepth 2 -name "pyproject.toml" -not -path '*/.git/*' 2>/dev/null | head -1)
    if [[ -n "$pyproject" ]]; then
        local desc=$(grep '^description' "$pyproject" 2>/dev/null | head -1 | sed 's/.*= *"//;s/".*//')
        [[ -n "$desc" ]] && { echo "$desc"; return; }
    fi

    # 3. package.json description (루트 + 서브)
    local pkgjson=$(find "$dir" -maxdepth 2 -name "package.json" -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -1)
    if [[ -n "$pkgjson" ]]; then
        local desc=$(python3 -c "import json; print(json.load(open('$pkgjson')).get('description',''))" 2>/dev/null)
        [[ -n "$desc" ]] && { echo "$desc"; return; }
    fi

    # 4. composer.json description (루트 + 서브)
    local composer=$(find "$dir" -maxdepth 2 -name "composer.json" -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null | head -1)
    if [[ -n "$composer" ]]; then
        local desc=$(python3 -c "import json; print(json.load(open('$composer')).get('description',''))" 2>/dev/null)
        [[ -n "$desc" ]] && { echo "$desc"; return; }
    fi

    # 5. README.md 첫 번째 설명줄
    if [[ -f "$dir/README.md" ]]; then
        local desc=$(grep -m1 -v '^#\|^$\|^\[\|^!\|^---\|^```' "$dir/README.md" 2>/dev/null | head -1 | sed 's/^ *//')
        [[ -n "$desc" && ${#desc} -gt 5 ]] && { echo "$desc"; return; }
    fi

    # 6. 글로벌 CLAUDE.md 프로젝트 테이블에서 매칭
    if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
        local desc=$(grep "| $name " "$HOME/.claude/CLAUDE.md" 2>/dev/null | grep '|.*|.*|' | head -1)
        if [[ -n "$desc" ]]; then
            local stack_col=$(echo "$desc" | awk -F'|' '{print $4}' | sed 's/^ *//;s/ *$//')
            [[ -n "$stack_col" ]] && { echo "$stack_col"; return; }
        fi
    fi

    # 7. 폴백: 디렉토리명
    echo "$name"
}

# ═══════════════════════════════════════════
# DB 자동 감지
# ═══════════════════════════════════════════
detect_db() {
    local dir="$1"
    local has_pg=false has_mysql=false has_redis=false

    # docker-compose 스캔
    local compose_files=$(find "$dir" -maxdepth 2 \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" -o -name "compose.yml" \) 2>/dev/null)
    for cf in $compose_files; do
        grep -qi "postgres\|postgresql\|pgvector" "$cf" 2>/dev/null && has_pg=true
        grep -qi "mysql\|mariadb" "$cf" 2>/dev/null && has_mysql=true
        grep -qi "redis" "$cf" 2>/dev/null && has_redis=true
    done

    # 의존성 스캔 (루트 + 서브디렉토리)
    while IFS= read -r dep_file; do
        grep -qi "psycopg\|asyncpg\|sqlalchemy\|alembic" "$dep_file" 2>/dev/null && has_pg=true
        grep -qi "pymysql\|aiomysql\|mysqlclient" "$dep_file" 2>/dev/null && has_mysql=true
        grep -qi "redis\|aioredis" "$dep_file" 2>/dev/null && has_redis=true
    done < <(find "$dir" -maxdepth 2 \( -name "pyproject.toml" -o -name "requirements*.txt" \) -not -path '*/.git/*' 2>/dev/null)

    while IFS= read -r pkgjson; do
        grep -qi '"pg"\|"postgres"\|prisma\|typeorm\|knex' "$pkgjson" 2>/dev/null && has_pg=true
        grep -qi '"mysql"' "$pkgjson" 2>/dev/null && has_mysql=true
        grep -qi '"redis"\|"ioredis"' "$pkgjson" 2>/dev/null && has_redis=true
    done < <(find "$dir" -maxdepth 2 -name "package.json" -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)

    while IFS= read -r gf; do
        grep -qi "postgresql\|postgres" "$gf" 2>/dev/null && has_pg=true
        grep -qi "mysql" "$gf" 2>/dev/null && has_mysql=true
        grep -qi "redis\|jedis\|lettuce" "$gf" 2>/dev/null && has_redis=true
    done < <(find "$dir" -maxdepth 2 \( -name "build.gradle.kts" -o -name "build.gradle" -o -name "pom.xml" \) -not -path '*/.git/*' 2>/dev/null)

    while IFS= read -r composer; do
        grep -qi "mysql\|pdo" "$composer" 2>/dev/null && has_mysql=true
        grep -qi "redis\|predis" "$composer" 2>/dev/null && has_redis=true
        grep -qi "postgres\|pgsql" "$composer" 2>/dev/null && has_pg=true
    done < <(find "$dir" -maxdepth 2 -name "composer.json" -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null)

    # .env 파일 스캔 (루트 + 서브)
    while IFS= read -r ef; do
        grep -qi "POSTGRES\|PGHOST\|PG_\|DATABASE_URL.*postgres" "$ef" 2>/dev/null && has_pg=true
        grep -qi "MYSQL\|MARIADB" "$ef" 2>/dev/null && has_mysql=true
        grep -qi "REDIS" "$ef" 2>/dev/null && has_redis=true
    done < <(find "$dir" -maxdepth 2 -name ".env*" -not -path '*/.git/*' -not -name ".env.bak" 2>/dev/null)

    # application.yml / application.properties 스캔
    while IFS= read -r cf; do
        grep -qi "postgresql\|postgres" "$cf" 2>/dev/null && has_pg=true
        grep -qi "mysql\|mariadb" "$cf" 2>/dev/null && has_mysql=true
        grep -qi "redis" "$cf" 2>/dev/null && has_redis=true
    done < <(find "$dir" -maxdepth 4 \( -name "application.yml" -o -name "application.yaml" -o -name "application.properties" -o -name "database.php" \) -not -path '*/.git/*' 2>/dev/null)

    local result=""
    $has_pg && result="PostgreSQL"
    $has_mysql && result="${result:+$result + }MySQL"
    $has_redis && result="${result:+$result + }Redis"
    echo "$result"
}

# ═══════════════════════════════════════════
# 연관 프로젝트 자동 감지
# ═══════════════════════════════════════════
detect_related_projects() {
    local dir="$1"
    local name=$(basename "$dir")
    local global_claude="$HOME/.claude/CLAUDE.md"
    [[ ! -f "$global_claude" ]] && return

    # 글로벌 CLAUDE.md에서 프로젝트 경로 파싱
    local -a all_projects=()
    while IFS= read -r line; do
        local proj_path=$(echo "$line" | awk -F'|' '{print $3}' | sed 's/`//g;s/^ *//;s/ *$//')
        [[ -z "$proj_path" ]] && continue
        proj_path="${proj_path/#\~/$HOME}"
        local proj_name=$(basename "$proj_path")
        [[ "$proj_name" == "$name" ]] && continue
        [[ ! -d "$proj_path" ]] && continue
        all_projects+=("$proj_path")
    done < <(grep '| `~/' "$global_claude" 2>/dev/null | grep -v '경로')

    # 각 후보 프로젝트에 대해 참조 관계 확인
    for proj_path in "${all_projects[@]}"; do
        local proj_name=$(basename "$proj_path")
        local found=false
        local reason=""

        # docker-compose에서 참조
        for cf in "$dir"/docker-compose*.yml "$dir"/docker-compose*.yaml "$dir"/compose.yml; do
            if [[ -f "$cf" ]] && grep -qi "$proj_name" "$cf" 2>/dev/null; then
                found=true; reason="Docker Compose 서비스 참조"; break
            fi
        done

        # .env에서 참조
        if ! $found; then
            for ef in "$dir/.env" "$dir/.env.example" "$dir/.env.local"; do
                if [[ -f "$ef" ]] && grep -qi "$proj_name\|$(echo "$proj_name" | tr '-' '_')" "$ef" 2>/dev/null; then
                    found=true; reason="환경변수 참조"; break
                fi
            done
        fi

        # 소스 코드에서 참조 (빠른 검색)
        if ! $found; then
            for src_dir in "$dir/src" "$dir/app" "$dir/lib" "$dir/pages" "$dir/components"; do
                if [[ -d "$src_dir" ]] && grep -rql "$proj_name\|$(echo "$proj_name" | tr '-' '_')" "$src_dir" 2>/dev/null | head -1 | grep -q .; then
                    found=true; reason="소스 코드 참조"; break
                fi
            done
        fi

        # 설정 파일에서 참조
        if ! $found; then
            for cf in "$dir/src/main/resources/application.yml" "$dir/src/main/resources/application.yaml"; do
                if [[ -f "$cf" ]] && grep -qi "$proj_name" "$cf" 2>/dev/null; then
                    found=true; reason="설정 파일 참조"; break
                fi
            done
        fi

        $found && echo "${proj_path/#$HOME/~}|${reason}"
    done
}

# ═══════════════════════════════════════════
# 스택 프리셋 로드
# ═══════════════════════════════════════════
load_stack_preset() {
    local stack_id="$1"

    case "$stack_id" in
        fastapi)
            STACK="FastAPI + Python"
            # pyproject.toml에서 Python 버전 감지
            local _pyver="3.12"
            local _pydir="${PROJECT_DIR:-${dir:-}}"
            if [[ -n "$_pydir" && -f "${_pydir}/pyproject.toml" ]]; then
                local _v=$(grep -E 'requires-python|python_requires' "${_pydir}/pyproject.toml" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
                [[ -n "$_v" ]] && _pyver="$_v"
            fi
            STACK_DETAIL="FastAPI + Python ${_pyver} + SQLAlchemy async"
            LANG="python"; PKG_MGR="uv"
            BUILD_CMD="uv sync"
            RUN_CMD="uv run uvicorn src.main:app --reload"
            TEST_CMD="uv run pytest -q"
            LINT_CMD="uv run ruff check src/ tests/"
            FORMAT_CMD="uv run ruff format --check src/ tests/"
            TYPECHECK_CMD="uv run mypy src/"
            DEV_AGENT_TYPE="backend-developer"
            ;;
        springboot)
            STACK="Spring Boot + Kotlin"
            STACK_DETAIL="Spring Boot 3 + Kotlin + JPA"
            LANG="kotlin"; PKG_MGR="gradle"
            BUILD_CMD="./gradlew build"
            RUN_CMD="./gradlew bootRun"
            TEST_CMD="./gradlew test"
            LINT_CMD="./gradlew ktlintCheck"
            FORMAT_CMD="./gradlew ktlintFormat"
            TYPECHECK_CMD=""
            DEV_AGENT_TYPE="backend-developer"
            ;;
        php)
            STACK="CodeIgniter + PHP"
            STACK_DETAIL="CodeIgniter 3 + PHP 8.3"
            LANG="php"; PKG_MGR="composer"
            BUILD_CMD="composer install"
            RUN_CMD="php -S localhost:8080 -t public"
            TEST_CMD="vendor/bin/phpunit"
            LINT_CMD="vendor/bin/phpcs src/"
            FORMAT_CMD=""
            TYPECHECK_CMD="vendor/bin/phpstan analyse"
            DEV_AGENT_TYPE="backend-developer"
            ;;
        nextjs|react)
            STACK="Next.js + React"
            STACK_DETAIL="Next.js 15 + React 19 + TypeScript"
            LANG="typescript"; PKG_MGR="npm"
            BUILD_CMD="npm install && npm run build"
            RUN_CMD="npm run dev"
            TEST_CMD="npm test"
            LINT_CMD="npm run lint"
            FORMAT_CMD=""
            TYPECHECK_CMD="npx tsc --noEmit"
            DEV_AGENT_TYPE="frontend-developer"
            ;;
        monorepo-nextjs|monorepo-react|monorepo-node|monorepo-python)
            # monorepo: 루트는 워크스페이스 메타만, 실제 빌드는 자식 앱에서
            local _pkg_mgr="pnpm"
            [[ -f "$PROJECT_DIR/yarn.lock" ]] && _pkg_mgr="yarn"
            [[ -f "$PROJECT_DIR/package-lock.json" ]] && _pkg_mgr="npm"
            [[ -f "$PROJECT_DIR/pnpm-lock.yaml" ]] && _pkg_mgr="pnpm"
            # 자식 앱 목록 수집
            local _apps_list=""
            for sub in "$PROJECT_DIR/apps"/* "$PROJECT_DIR/packages"/*; do
                [[ -d "$sub" ]] || continue
                _apps_list="${_apps_list}$(basename "$sub"), "
            done
            _apps_list="${_apps_list%, }"
            case "$stack_id" in
                monorepo-nextjs)
                    STACK="Monorepo (Next.js + ${_pkg_mgr})"
                    STACK_DETAIL="${_pkg_mgr} workspace · apps: ${_apps_list:-?}"
                    LANG="typescript"
                    DEV_AGENT_TYPE="frontend-developer"
                    ;;
                monorepo-react)
                    STACK="Monorepo (React + ${_pkg_mgr})"
                    STACK_DETAIL="${_pkg_mgr} workspace · apps: ${_apps_list:-?}"
                    LANG="typescript"
                    DEV_AGENT_TYPE="frontend-developer"
                    ;;
                monorepo-python)
                    STACK="Monorepo (Python)"
                    STACK_DETAIL="${_pkg_mgr} workspace · apps: ${_apps_list:-?}"
                    LANG="python"
                    DEV_AGENT_TYPE="backend-developer"
                    ;;
                monorepo-node)
                    STACK="Monorepo (Node.js)"
                    STACK_DETAIL="${_pkg_mgr} workspace · apps: ${_apps_list:-?}"
                    LANG="typescript"
                    DEV_AGENT_TYPE="backend-developer"
                    ;;
            esac
            PKG_MGR="$_pkg_mgr"
            BUILD_CMD="${_pkg_mgr} install"
            RUN_CMD="${_pkg_mgr} -F web dev  # 또는 -F api"
            TEST_CMD="${_pkg_mgr} -r test"
            LINT_CMD="${_pkg_mgr} -r lint"
            FORMAT_CMD=""
            TYPECHECK_CMD="${_pkg_mgr} -r typecheck"
            ;;
        keycloak-spi|gradle)
            STACK="Keycloak SPI"
            STACK_DETAIL="Keycloak 26 + 커스텀 SPI + Kotlin/Java"
            LANG="kotlin"; PKG_MGR="gradle"
            BUILD_CMD="./gradlew build"
            RUN_CMD=""
            TEST_CMD="./gradlew test"
            LINT_CMD=""
            FORMAT_CMD=""
            TYPECHECK_CMD=""
            DEV_AGENT_TYPE="backend-developer"
            ;;
        docker)
            STACK="Docker Compose"
            STACK_DETAIL="Docker Compose 인프라 관리"
            LANG="docker"; PKG_MGR=""
            BUILD_CMD="docker compose build"
            RUN_CMD="docker compose up -d"
            TEST_CMD="docker compose ps"
            LINT_CMD=""
            FORMAT_CMD=""
            TYPECHECK_CMD=""
            DEV_AGENT_TYPE="ops-lead"
            ;;
        terraform)
            STACK="Terraform"
            local _tfdir="${PROJECT_DIR:-${dir:-.}}"
            # Terraform/OpenTofu 버전 감지 (.tool-versions > .terraform-version)
            local _tfver=""
            if [[ -f "$_tfdir/.tool-versions" ]]; then
                _tfver=$(grep -iE '^(terraform|opentofu)\b' "$_tfdir/.tool-versions" 2>/dev/null | head -1 | awk '{print $2}')
            fi
            [[ -z "$_tfver" && -f "$_tfdir/.terraform-version" ]] && _tfver=$(head -1 "$_tfdir/.terraform-version" 2>/dev/null | tr -d '[:space:]')
            # AWS/GCP/Azure provider 감지
            local _tfcloud=""
            if grep -rqhE 'source\s*=\s*"hashicorp/aws"' "$_tfdir" --include="*.tf" 2>/dev/null; then
                _tfcloud="AWS"
            elif grep -rqhE 'source\s*=\s*"hashicorp/google"' "$_tfdir" --include="*.tf" 2>/dev/null; then
                _tfcloud="GCP"
            elif grep -rqhE 'source\s*=\s*"hashicorp/azurerm"' "$_tfdir" --include="*.tf" 2>/dev/null; then
                _tfcloud="Azure"
            fi
            STACK_DETAIL="Terraform${_tfver:+ $_tfver}${_tfcloud:+ + $_tfcloud}"
            LANG="terraform"; PKG_MGR="terraform"
            BUILD_CMD="terraform init"
            RUN_CMD="terraform plan"
            TEST_CMD="terraform validate"
            if [[ -f "$_tfdir/.tflint.hcl" ]]; then
                LINT_CMD="tflint --recursive"
            else
                LINT_CMD="terraform fmt -check -recursive"
            fi
            FORMAT_CMD="terraform fmt -recursive"
            TYPECHECK_CMD="terraform validate"
            DEV_AGENT_TYPE="ops-lead"
            ;;
        python-lib)
            STACK="Python SDK"
            STACK_DETAIL="Python 라이브러리 + hatchling"
            LANG="python"; PKG_MGR="uv"
            BUILD_CMD="uv sync"
            RUN_CMD=""
            TEST_CMD="uv run pytest -q"
            LINT_CMD="uv run ruff check src/"
            FORMAT_CMD="uv run ruff format --check src/"
            TYPECHECK_CMD="uv run mypy src/"
            DEV_AGENT_TYPE="backend-developer"
            ;;
        node)
            STACK="Node.js"
            STACK_DETAIL="Node.js + JavaScript/TypeScript"
            LANG="typescript"; PKG_MGR="npm"
            BUILD_CMD="npm install"
            RUN_CMD="npm start"
            TEST_CMD="npm test"
            LINT_CMD="npm run lint"
            FORMAT_CMD=""
            TYPECHECK_CMD=""
            DEV_AGENT_TYPE="backend-developer"
            ;;
        go)
            STACK="Go"
            STACK_DETAIL="Go + stdlib"
            LANG="go"; PKG_MGR="go"
            BUILD_CMD="go build ./..."
            RUN_CMD="go run ."
            TEST_CMD="go test ./..."
            LINT_CMD="golangci-lint run"
            FORMAT_CMD="gofmt -l ."
            TYPECHECK_CMD="go vet ./..."
            DEV_AGENT_TYPE="backend-developer"
            ;;
        rust)
            STACK="Rust"
            STACK_DETAIL="Rust + Cargo"
            LANG="rust"; PKG_MGR="cargo"
            BUILD_CMD="cargo build"
            RUN_CMD="cargo run"
            TEST_CMD="cargo test"
            LINT_CMD="cargo clippy"
            FORMAT_CMD="cargo fmt --check"
            TYPECHECK_CMD=""
            DEV_AGENT_TYPE="backend-developer"
            ;;
        ios)
            STACK="iOS (Swift/SwiftUI)"
            local _iosdir="${PROJECT_DIR:-${dir:-.}}"
            # 루트 레벨만 탐색 (.xcodeproj 내부의 project.xcworkspace 배제)
            local _xcws=$(find "$_iosdir" -maxdepth 1 -name "*.xcworkspace" 2>/dev/null | head -1)
            local _xcproj=$(find "$_iosdir" -maxdepth 1 -name "*.xcodeproj" 2>/dev/null | head -1)
            local _scheme=""
            local _proj_flag=""
            # CocoaPods 사용 시 xcworkspace 우선, 없으면 xcodeproj
            if [[ -n "$_xcws" ]]; then
                _scheme=$(basename "$_xcws" .xcworkspace)
                _proj_flag="-workspace \"$(basename "$_xcws")\""
            elif [[ -n "$_xcproj" ]]; then
                _scheme=$(basename "$_xcproj" .xcodeproj)
                _proj_flag="-project \"$(basename "$_xcproj")\""
            else
                _scheme="$(basename "$_iosdir")"
            fi
            STACK_DETAIL="iOS + Swift + SwiftUI (Xcode)"
            LANG="swift"; PKG_MGR="xcodebuild"
            if [[ -f "$_iosdir/Podfile" ]]; then
                BUILD_CMD="pod install && xcodebuild ${_proj_flag} -scheme \"${_scheme}\" -configuration Debug -destination 'generic/platform=iOS Simulator' build"
            else
                BUILD_CMD="xcodebuild ${_proj_flag} -scheme \"${_scheme}\" -configuration Debug -destination 'generic/platform=iOS Simulator' build"
            fi
            RUN_CMD="open ${_xcproj:-${_xcws:-$_iosdir}}"
            TEST_CMD="xcodebuild ${_proj_flag} -scheme \"${_scheme}\" -destination 'platform=iOS Simulator,name=iPhone 15' test"
            LINT_CMD="swiftlint lint --quiet || true"
            FORMAT_CMD="swift-format lint -r . || true"
            TYPECHECK_CMD=""
            DEV_AGENT_TYPE="frontend-developer"
            ;;
        swift-lib)
            STACK="Swift Package"
            STACK_DETAIL="Swift Package Manager 라이브러리"
            LANG="swift"; PKG_MGR="swift"
            BUILD_CMD="swift build"
            RUN_CMD="swift run"
            TEST_CMD="swift test"
            LINT_CMD="swiftlint lint --quiet || true"
            FORMAT_CMD="swift-format lint -r Sources/ || true"
            TYPECHECK_CMD=""
            DEV_AGENT_TYPE="backend-developer"
            ;;
        *)
            STACK=""; STACK_DETAIL=""
            LANG=""; PKG_MGR=""
            BUILD_CMD=""; RUN_CMD=""
            TEST_CMD=""; LINT_CMD=""
            FORMAT_CMD=""; TYPECHECK_CMD=""
            DEV_AGENT_TYPE="backend-developer"
            return 1
            ;;
    esac
    return 0
}

# ═══════════════════════════════════════════
# 대화형 스택 선택 (자동 감지 실패 시)
# ═══════════════════════════════════════════
interactive_stack_select() {
    echo "${BOLD}스택 선택:${NC}"
    echo "  1) FastAPI + Python"
    echo "  2) Spring Boot + Kotlin"
    echo "  3) CodeIgniter + PHP"
    echo "  4) Next.js + React"
    echo "  5) Keycloak SPI + Java/Kotlin"
    echo "  6) Docker Compose (인프라)"
    echo "  7) Python 라이브러리/SDK"
    echo "  8) Node.js"
    echo "  9) Go"
    echo " 10) Rust"
    echo " 11) iOS (Swift/SwiftUI + Xcode)"
    echo " 12) Swift Package (SPM 라이브러리)"
    echo " 13) Terraform (IaC)"
    echo " 14) 기타 (직접 입력)"
    ask "번호 선택"
    read STACK_CHOICE

    case "$STACK_CHOICE" in
        1) load_stack_preset "fastapi" ;;
        2) load_stack_preset "springboot" ;;
        3) load_stack_preset "php" ;;
        4) load_stack_preset "nextjs" ;;
        5) load_stack_preset "keycloak-spi" ;;
        6) load_stack_preset "docker" ;;
        7) load_stack_preset "python-lib" ;;
        8) load_stack_preset "node" ;;
        9) load_stack_preset "go" ;;
        10) load_stack_preset "rust" ;;
        11) load_stack_preset "ios" ;;
        12) load_stack_preset "swift-lib" ;;
        13) load_stack_preset "terraform" ;;
        14)
            ask "스택 이름 (예: Flask + Python)"; read STACK
            STACK_DETAIL="$STACK"
            ask "언어 (python/kotlin/typescript/php/java/go)"; read LANG
            ask "패키지 매니저"; read PKG_MGR
            ask "빌드 명령어"; read BUILD_CMD
            ask "실행 명령어"; read RUN_CMD
            ask "테스트 명령어"; read TEST_CMD
            ask "린트 명령어"; read LINT_CMD
            FORMAT_CMD=""; TYPECHECK_CMD=""
            DEV_AGENT_TYPE="backend-developer"
            ;;
        *) err "잘못된 선택"; exit 1 ;;
    esac
}

# ═══════════════════════════════════════════
# 디렉토리 구조 자동 생성
# ═══════════════════════════════════════════
generate_dir_tree() {
    local dir="$1"
    local max_depth="${2:-3}"

    # src/ 또는 app/ 또는 lib/ 기준
    local root_dirs=()
    for d in src app lib cmd pkg internal; do
        [[ -d "$dir/$d" ]] && root_dirs+=("$d")
    done

    if [[ ${#root_dirs[@]} -eq 0 ]]; then
        echo "<!-- TODO: 프로젝트 디렉토리 구조 작성 -->"
        return
    fi

    local tree=""
    for rd in "${root_dirs[@]}"; do
        # find로 트리 생성 (depth 제한, __pycache__ 등 제외)
        tree="${tree}$(cd "$dir" && find "$rd" -maxdepth "$max_depth" \
            -not -path '*/__pycache__/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/.next/*' \
            -not -name '*.pyc' \
            -not -name '.DS_Store' \
            -type d | sort | sed 's|[^/]*/|  |g;s|  |├── |' 2>/dev/null)\n"
    done

    if [[ -n "$tree" ]]; then
        # 더 나은 트리 포맷
        cd "$dir" && find "${root_dirs[@]}" -maxdepth "$max_depth" \
            -not -path '*/__pycache__/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -not -path '*/.next/*' \
            -not -name '*.pyc' \
            -not -name '.DS_Store' \
            -type d | sort | while IFS= read -r line; do
                local depth=$(echo "$line" | tr -cd '/' | wc -c)
                local indent=""
                for ((i=0; i<depth; i++)); do indent="${indent}│   "; done
                local name=$(basename "$line")
                echo "${indent}├── ${name}/"
            done
    else
        echo "<!-- TODO: 프로젝트 디렉토리 구조 작성 -->"
    fi
}

# ═══════════════════════════════════════════
# AI 도구 가용성 확인
# ═══════════════════════════════════════════
HAS_GEMINI=false
HAS_CODEX=false

check_ai_tools() {
    command -v gemini &>/dev/null && HAS_GEMINI=true
    command -v codex &>/dev/null && HAS_CODEX=true

    if $HAS_GEMINI; then
        ok "Gemini CLI 감지"
    else
        skip "Gemini CLI 미설치 → 정적 분석만 수행"
    fi
    if $HAS_CODEX; then
        ok "Codex CLI 감지"
    else
        skip "Codex CLI 미설치 → Gemini 단독 분석"
    fi
}

# ═══════════════════════════════════════════
# Gemini 프로젝트 분석 (1M 토큰 컨텍스트 활용)
# ═══════════════════════════════════════════
AI_ANALYSIS_DIR=""

analyze_with_gemini() {
    local dir="$1"
    local name=$(basename "$dir")
    AI_ANALYSIS_DIR=$(mktemp -d)

    section "Gemini 코드베이스 분석: ${name}"
    info "분석 중... (30초~2분 소요)"

    # Gemini에 구조화된 분석 요청
    local prompt="다음 프로젝트를 분석하여 정확히 아래 4개 섹션을 출력하라.
각 섹션은 반드시 === 구분자로 시작한다. 구분자 외의 마크업/설명은 넣지 마라.
프로젝트: ${name} (${STACK_DETAIL})
역할: ${PROJECT_ROLE}

===ARCHITECTURE===
프로젝트에서 발견한 아키텍처 패턴과 규칙을 마크다운 리스트로 작성.
코드에서 실제 확인한 것만. 추측 금지.
예: '- DDD 4계층: Presentation → Application → Domain ← Infrastructure'
예: '- Repository 패턴: 인터페이스(domain/)와 구현(infrastructure/) 분리'

===BACKLOG===
코드를 분석하여 발견한 실제 개선 필요 사항을 backlog 형식 (schema v4) 으로 작성.

각 항목은 트랙 라벨 필수. 트랙 7개:
- 메인: backend / frontend / data / infra / auth
- 메타: ops (운영/모니터링) / meta (테스트/문서/리팩터)

각 항목 형식:
- [ ] \`[트랙]\` **제목** — 설명
  - 위치: \`파일경로:줄번호\` (가능하면)
  - 트리거: 🔒보안/🐛버그/⚡성능/🚀요구사항/📅일정/🔧리팩터 중 하나 + 사유
  - DONE: 끝났는지 측정 가능한 기준
  - 추정: 30m / 1h / 2h / 4h / 1d / 2d

구조:
## 메인 트랙
### 높음 (High)  /  ### 중간 (Medium)  /  ### 낮음 (Low)
## 메타 트랙 (격리)
### 중간 (Medium)  (테스트/문서/리팩터/lint는 여기로)

분류 원칙:
- 인증/JWT/JWKS/PII/RBAC → auth
- DB/SQL/ClickHouse/대시보드 → data
- Docker/배포/CI/env → infra
- API/라우트/서버 로직 → backend
- 페이지/컴포넌트/UI → frontend
- 헬스체크/모니터링/알림 → ops (메타)
- 테스트 커버리지/문서/리팩터/lint → meta (메타)

최소 5개, 최대 15개. 실제 코드에서 확인한 것만. 추측 금지.

===DIRTREE===
주요 디렉토리를 설명 포함하여 트리 형태로 작성. 예:
src/
├── domain/           # 도메인 계층 (엔티티, 값객체, 리포지토리 인터페이스)
│   ├── shared/       # 공통 (BaseEntity, UnitOfWork)
│   └── user/         # 사용자 도메인
├── application/      # 애플리케이션 계층 (서비스, commands, queries)

===DEPS===
프로젝트의 주요 의존성을 버전 포함하여 마크다운 리스트로 작성.
예: '- fastapi >= 0.115.0'
핵심 의존성만 15개 이내."

    # Gemini 실행 (프로젝트 디렉토리에서, 비대화형)
    local gemini_output
    gemini_output=$(cd "$dir" && gemini -p "$prompt" -m gemini-2.5-pro 2>/dev/null) || {
        warn "Gemini 분석 실패 → 정적 분석 폴백"
        return 1
    }

    if [[ -z "$gemini_output" || ${#gemini_output} -lt 100 ]]; then
        warn "Gemini 출력 부족 → 정적 분석 폴백"
        return 1
    fi

    # 섹션별 파싱
    echo "$gemini_output" | sed -n '/===ARCHITECTURE===/,/===BACKLOG===/p' | grep -v '===' > "$AI_ANALYSIS_DIR/architecture.md"
    echo "$gemini_output" | sed -n '/===BACKLOG===/,/===DIRTREE===/p' | grep -v '===' > "$AI_ANALYSIS_DIR/backlog.md"
    echo "$gemini_output" | sed -n '/===DIRTREE===/,/===DEPS===/p' | grep -v '===' > "$AI_ANALYSIS_DIR/dirtree.md"
    echo "$gemini_output" | sed -n '/===DEPS===/,$p' | grep -v '===' > "$AI_ANALYSIS_DIR/deps.md"

    # 각 파일이 비어있지 않은지 확인
    local sections_ok=0
    for f in architecture backlog dirtree deps; do
        if [[ -s "$AI_ANALYSIS_DIR/${f}.md" ]]; then
            sections_ok=$((sections_ok + 1))
        fi
    done

    if [[ $sections_ok -ge 3 ]]; then
        ok "Gemini 분석 완료 (${sections_ok}/4 섹션)"
        return 0
    else
        warn "Gemini 파싱 부분 실패 (${sections_ok}/4) → 사용 가능한 섹션만 적용"
        return 0
    fi
}

# ═══════════════════════════════════════════
# Codex 아키텍처 검증 (세컨드 오피니언)
# ═══════════════════════════════════════════
validate_with_codex() {
    local dir="$1"
    local name=$(basename "$dir")

    [[ ! -s "$AI_ANALYSIS_DIR/architecture.md" ]] && return 1

    section "Codex 아키텍처 검증: ${name}"

    local arch_content=$(cat "$AI_ANALYSIS_DIR/architecture.md")
    local prompt="아래는 ${name} (${STACK_DETAIL}) 프로젝트의 아키텍처 분석 결과다.
잘못된 점이나 누락된 핵심 패턴이 있으면 수정/추가하라.
문제없으면 'LGTM'만 출력.
마크다운 리스트 형식으로만 답하라.

${arch_content}"

    local codex_output
    codex_output=$(cd "$dir" && codex exec --full-auto "$prompt" 2>/dev/null) || {
        skip "Codex 검증 건너뜀"
        return 1
    }

    if [[ -n "$codex_output" && "$codex_output" != *"LGTM"* && ${#codex_output} -gt 20 ]]; then
        # Codex가 수정 제안한 경우 → 병합
        info "Codex 보완 사항 발견 → 병합"
        echo "" >> "$AI_ANALYSIS_DIR/architecture.md"
        echo "$codex_output" >> "$AI_ANALYSIS_DIR/architecture.md"
        ok "아키텍처 분석 보완 완료"
    else
        ok "Codex 검증: LGTM"
    fi
    return 0
}

# ═══════════════════════════════════════════
# 정적 분석 폴백 (AI 미사용 시)
# ═══════════════════════════════════════════
analyze_static() {
    local dir="$1"
    AI_ANALYSIS_DIR=$(mktemp -d)

    section "정적 코드 분석"

    # ── 아키텍처 패턴 감지 ──
    local arch=""

    # DDD 4계층
    local has_domain=false has_app=false has_infra=false has_pres=false
    [[ -d "$dir/src/domain" || -d "$dir/app/domain" ]] && has_domain=true
    [[ -d "$dir/src/application" || -d "$dir/app/application" ]] && has_app=true
    [[ -d "$dir/src/infrastructure" || -d "$dir/app/infrastructure" ]] && has_infra=true
    [[ -d "$dir/src/presentation" || -d "$dir/app/presentation" || -d "$dir/src/api" ]] && has_pres=true
    if $has_domain && $has_app && $has_infra; then
        arch="${arch}- DDD 계층 구조: Presentation → Application → Domain ← Infrastructure\n"
    fi

    # MVC
    if [[ -d "$dir/app/controllers" || -d "$dir/src/controllers" ]] && [[ -d "$dir/app/models" || -d "$dir/src/models" ]]; then
        arch="${arch}- MVC 패턴: Controllers + Models + Views\n"
    fi

    # CQRS
    if find "$dir/src" -name "commands.py" -o -name "queries.py" 2>/dev/null | grep -q .; then
        arch="${arch}- CQRS-lite: commands.py / queries.py 물리 분리\n"
    fi

    # Repository 패턴
    if grep -rql "Repository\|repository" "$dir/src" 2>/dev/null | head -1 | grep -q .; then
        arch="${arch}- Repository 패턴 사용\n"
    fi

    # UnitOfWork
    if grep -rql "UnitOfWork\|unit_of_work" "$dir/src" 2>/dev/null | head -1 | grep -q .; then
        arch="${arch}- UnitOfWork 패턴 사용\n"
    fi

    # Annotated (FastAPI)
    if grep -rql "Annotated\[" "$dir/src" 2>/dev/null | head -1 | grep -q .; then
        arch="${arch}- Annotated 패턴 (FastAPI Depends 대체)\n"
    fi

    # DI Container
    if find "$dir/src" -name "containers*" -o -name "container.py" -o -name "di.py" 2>/dev/null | grep -q .; then
        arch="${arch}- DI 컨테이너 사용\n"
    fi

    # Event-driven
    if grep -rql "EventPublisher\|event_handler\|EventBus" "$dir/src" 2>/dev/null | head -1 | grep -q .; then
        arch="${arch}- 이벤트 기반 패턴 사용\n"
    fi

    if [[ -n "$arch" ]]; then
        printf '%b' "$arch" > "$AI_ANALYSIS_DIR/architecture.md"
        ok "아키텍처 패턴 ${arch//[^-]/}" | wc -l | xargs -I{} echo "아키텍처 패턴 감지"
    fi

    # ── Backlog 자동 생성 (schema v4 — 메인/메타 분리) ──
    # 메인 트랙 (backend/frontend/data/infra/auth)
    local main_high="" main_mid="" main_low=""
    # 메타 트랙 (ops/meta)
    local meta_high="" meta_mid="" meta_low=""

    # TODO/FIXME/HACK 스캔 (트랙은 경로 기반 추론)
    local todo_files=$(grep -rl "TODO\|FIXME\|HACK\|XXX" "$dir/src" "$dir/app" "$dir/lib" 2>/dev/null | grep -v __pycache__ | grep -v node_modules | grep -v .git | head -20)
    if [[ -n "$todo_files" ]]; then
        while IFS= read -r tf; do
            local rel_path="${tf#$dir/}"
            local todo_line=$(grep -n "TODO\|FIXME\|HACK" "$tf" 2>/dev/null | head -1)
            local line_num="${todo_line%%:*}"
            local todo_text=$(echo "$todo_line" | sed 's/[^:]*://' | sed 's/.*TODO[: ]*//' | sed 's/.*FIXME[: ]*//' | sed 's/.*HACK[: ]*//' | sed 's/^ *//' | head -c 100)
            # 트랙 추론: 경로 키워드로
            local track="backend"
            case "$rel_path" in
                *auth*|*jwt*|*jwks*|*oauth*|*pii*|*rate-limit*) track="auth" ;;
                *clickhouse*|*sql*|*dashboard*|*analytics*) track="data" ;;
                *docker*|*deploy*|*ci*|*infra*) track="infra" ;;
                *components/*|*page.tsx*|*_components/*) track="frontend" ;;
                *audit*|*monitor*|*health*) track="ops" ;;
            esac
            [[ -n "$todo_text" ]] && main_mid="${main_mid}- [ ] \`[${track}]\` **TODO: ${todo_text}**\n  - 위치: \`${rel_path}:${line_num}\`\n  - 트리거: 🔧 코드 내 TODO 주석\n  - DONE: 해당 TODO 제거 + 동작 확인\n  - 추정: 1h\n\n"
        done <<< "$todo_files"
    fi

    # CORS * 검사 → auth 트랙
    if grep -rql 'allow_origins.*\*\|allow_methods.*\*\|allowedOrigins.*\*' "$dir/src" "$dir/app" 2>/dev/null; then
        local cors_file=$(grep -rl 'allow_origins.*\*\|allow_methods.*\*' "$dir/src" "$dir/app" 2>/dev/null | head -1)
        local cors_rel="${cors_file#$dir/}"
        main_high="${main_high}- [ ] \`[auth]\` **CORS 와일드카드 설정** — \`allow_origins=[\"*\"]\` 또는 \`allow_methods=[\"*\"]\` 프로덕션 보안 위험\n  - 위치: \`${cors_rel}\`\n  - 트리거: 🔒 프로덕션 배포 시 명시적 허용 목록 필요\n  - DONE: 환경별 허용 origin 화이트리스트 적용 + 배포 환경 확인\n  - 추정: 2h\n\n"
    fi

    # 테스트 커버리지 검사 → meta 트랙
    local src_count=$(find "$dir/src" "$dir/app" "$dir/lib" -name "*.py" -o -name "*.kt" -o -name "*.ts" -o -name "*.tsx" -o -name "*.php" 2>/dev/null | grep -v __pycache__ | grep -v node_modules | wc -l | tr -d ' ')
    local test_count=$(find "$dir/tests" "$dir/test" "$dir/__tests__" -name "*.py" -o -name "*.kt" -o -name "*.ts" -o -name "*.spec.*" -o -name "*.test.*" -o -name "*Test.php" 2>/dev/null | grep -v __pycache__ | grep -v node_modules | wc -l | tr -d ' ')
    if [[ $src_count -gt 0 && $test_count -eq 0 ]]; then
        meta_mid="${meta_mid}- [ ] \`[meta]\` **테스트 파일 없음** — 소스 파일 ${src_count}개 대비 테스트 0개\n  - 위치: \`tests/\`\n  - 트리거: 🔧 회귀 방어 부재\n  - DONE: 핵심 모듈 happy/error path 각 1쌍 + CI 실행 확인\n  - 추정: 1d\n\n"
    elif [[ $src_count -gt 0 && $test_count -gt 0 ]]; then
        local ratio=$((test_count * 100 / src_count))
        if [[ $ratio -lt 30 ]]; then
            meta_mid="${meta_mid}- [ ] \`[meta]\` **테스트 커버리지 부족** — 소스 ${src_count}개 / 테스트 ${test_count}개 (${ratio}%)\n  - 위치: \`tests/\`\n  - 트리거: 🔧 회귀 방어 부족 (30% 미만)\n  - DONE: 핵심 모듈 우선 커버리지 50%+ 또는 측정 가능한 목표 수치 설정\n  - 추정: 2d\n\n"
        fi
    fi

    # Dockerfile 누락 → infra
    if [[ -f "$dir/docker-compose.yml" || -f "$dir/docker-compose.yaml" || -f "$dir/compose.yml" ]] && [[ ! -f "$dir/Dockerfile" ]]; then
        main_low="${main_low}- [ ] \`[infra]\` **Dockerfile 누락** — docker-compose 존재하나 Dockerfile 없음\n  - 위치: 프로젝트 루트\n  - 트리거: 🔧 컨테이너 빌드 설정 필요\n  - DONE: Dockerfile 작성 + compose에서 build 성공\n  - 추정: 2h\n\n"
    fi

    # .env.example 누락 → infra
    if [[ -f "$dir/.env" && ! -f "$dir/.env.example" ]]; then
        main_mid="${main_mid}- [ ] \`[infra]\` **.env.example 누락** — .env 파일 존재하나 예시 파일 없음\n  - 위치: 프로젝트 루트\n  - 트리거: 🔧 팀원 온보딩 시 환경변수 가이드 필요\n  - DONE: .env에서 민감값 제거한 .env.example 추가\n  - 추정: 30m\n\n"
    fi

    # 큰 파일 감지 (500줄 이상) → meta 트랙(리팩터)
    local big_files=$(find "$dir/src" "$dir/app" "$dir/lib" \( -name "*.py" -o -name "*.kt" -o -name "*.ts" -o -name "*.php" \) 2>/dev/null | grep -v __pycache__ | grep -v node_modules | while IFS= read -r f; do
        local lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
        [[ $lines -gt 500 ]] && echo "${f#$dir/}:${lines}"
    done | head -3)
    if [[ -n "$big_files" ]]; then
        while IFS= read -r bf; do
            local bf_path="${bf%%:*}"
            local bf_lines="${bf#*:}"
            meta_low="${meta_low}- [ ] \`[meta]\` **대형 파일 분리 검토** — ${bf_path} (${bf_lines}줄)\n  - 위치: \`${bf_path}\`\n  - 트리거: 🔧 단일 파일 500줄 초과 — 책임 분리 검토\n  - DONE: 책임 단위로 분할 + 호출처 회귀 통과\n  - 추정: 1d\n\n"
        done <<< "$big_files"
    fi

    # Alembic 의존성 있는데 migrations 없음 → infra (DB 마이그레이션 기반)
    if grep -q "alembic" "$dir/pyproject.toml" 2>/dev/null && [[ ! -d "$dir/alembic/versions" ]]; then
        main_high="${main_high}- [ ] \`[infra]\` **Alembic 마이그레이션 설정** — alembic 의존성은 있으나 마이그레이션 디렉토리 미구성\n  - 위치: 프로젝트 루트\n  - 트리거: 📅 DB 스키마 변경 관리 필수\n  - DONE: alembic init + 첫 마이그레이션 생성 + upgrade 동작 확인\n  - 추정: 2h\n\n"
    fi

    # README 부실 검사 → meta
    if [[ -f "$dir/README.md" ]]; then
        local readme_lines=$(wc -l < "$dir/README.md" | tr -d ' ')
        if [[ $readme_lines -lt 10 ]]; then
            meta_low="${meta_low}- [ ] \`[meta]\` **README 보강** — README.md가 ${readme_lines}줄로 부실\n  - 위치: \`README.md\`\n  - 트리거: 🔧 프로젝트 소개·설치·실행 방법 필요\n  - DONE: 정체성/스택/빌드/실행/테스트 5섹션 채움\n  - 추정: 1h\n\n"
        fi
    fi

    # 헬퍼: 섹션 출력
    local _emit_section() {
        local title="$1" content="$2" empty_msg="$3"
        echo "### ${title}"
        echo ""
        if [[ -n "$content" ]]; then
            printf '%b' "$content"
        else
            echo "(${empty_msg})"
            echo ""
        fi
    }

    # backlog 조합 (v4)
    local proj_name=$(basename "$dir")
    {
        echo "# Backlog"
        echo ""
        echo "<!-- schema: v4 -->"
        local total_main=$(printf '%b%b%b' "$main_high" "$main_mid" "$main_low" | grep -c '^\- \[ \]')
        local total_meta=$(printf '%b%b%b' "$meta_high" "$meta_mid" "$meta_low" | grep -c '^\- \[ \]')
        local total_all=$((total_main + total_meta))
        echo "> 프로젝트: \`${proj_name}\`  ·  총 ${total_all}건  ·  메인 ${total_main} / 메타 ${total_meta}"
        echo ""
        echo "## 메인 트랙"
        echo ""
        echo "진입: \`@dev backlog\` (무지정 시 이 섹션만 후보)"
        echo ""
        _emit_section "높음 (High)" "$main_high" "분석 결과 고우선 항목 없음"
        _emit_section "중간 (Medium)" "$main_mid" "분석 결과 중간 항목 없음"
        _emit_section "낮음 (Low)" "$main_low" "분석 결과 낮음 항목 없음"
        echo "## 메타 트랙 (격리)"
        echo ""
        echo "진입: \`@dev backlog meta\` 명시 호출 시만. \`@dev backlog\` 무지정 호출 시 **자동 제외**."
        echo ""
        _emit_section "높음 (High)" "$meta_high" "없음"
        _emit_section "중간 (Medium)" "$meta_mid" "없음"
        _emit_section "낮음 (Low)" "$meta_low" "없음"
        echo "## 완료"
        echo ""
        echo "(완료 항목은 archive/로 이동)"
    } > "$AI_ANALYSIS_DIR/backlog.md"

    local total_items
    total_items=$(grep -c '^\- \[ \]' "$AI_ANALYSIS_DIR/backlog.md" 2>/dev/null) || total_items=0
    ok "정적 분석 완료: backlog ${total_items}건 (v4 schema)"
}

# ═══════════════════════════════════════════
# AI 분석 결과를 생성 파일에 적용
# ═══════════════════════════════════════════
apply_ai_analysis() {
    local dir="$1"
    local name=$(basename "$dir")

    [[ -z "$AI_ANALYSIS_DIR" || ! -d "$AI_ANALYSIS_DIR" ]] && return

    section "분석 결과 적용"

    # 아키텍처 규칙 적용
    if [[ -s "$AI_ANALYSIS_DIR/architecture.md" && -f "$dir/.claude/CLAUDE.md" ]]; then
        local arch_content=$(cat "$AI_ANALYSIS_DIR/architecture.md")
        if grep -q "<!-- TODO: 프로젝트 고유 아키텍처 규칙 작성 -->" "$dir/.claude/CLAUDE.md" 2>/dev/null; then
            # TODO 플레이스홀더 교체
            local tmpfile=$(mktemp)
            while IFS= read -r line; do
                if [[ "$line" == *"<!-- TODO: 프로젝트 고유 아키텍처 규칙 작성 -->"* ]]; then
                    echo "$arch_content"
                else
                    echo "$line"
                fi
            done < "$dir/.claude/CLAUDE.md" > "$tmpfile"
            cp "$tmpfile" "$dir/.claude/CLAUDE.md"
            rm -f "$tmpfile"
            ok "CLAUDE.md 아키텍처 규칙 채움"
        fi
    fi

    # 디렉토리 트리 적용 (AI 분석이 더 상세하면 교체)
    if [[ -s "$AI_ANALYSIS_DIR/dirtree.md" && -f "$dir/.claude/CLAUDE.md" ]]; then
        local ai_tree=$(cat "$AI_ANALYSIS_DIR/dirtree.md")
        local ai_tree_lines=$(echo "$ai_tree" | wc -l | tr -d ' ')
        if [[ $ai_tree_lines -gt 3 ]]; then
            # 기존 트리 블록 교체
            local tmpfile=$(mktemp)
            local in_tree=false
            local replaced=false
            while IFS= read -r line; do
                if [[ "$line" == '```' && "$in_tree" == true ]]; then
                    echo "$ai_tree"
                    echo '```'
                    in_tree=false
                    replaced=true
                elif [[ "$line" == "## 디렉토리 구조" ]]; then
                    echo "$line"
                    echo ""
                    echo '```'
                    in_tree=true
                elif [[ "$in_tree" == true ]]; then
                    # 기존 트리 내용 건너뜀
                    continue
                else
                    echo "$line"
                fi
            done < "$dir/.claude/CLAUDE.md" > "$tmpfile"
            if $replaced; then
                cp "$tmpfile" "$dir/.claude/CLAUDE.md"
                ok "CLAUDE.md 디렉토리 트리 교체 (AI 분석)"
            fi
            rm -f "$tmpfile"
        fi
    fi

    # 의존성 적용
    if [[ -s "$AI_ANALYSIS_DIR/deps.md" && -f "$dir/.claude/CLAUDE.md" ]]; then
        local deps_content=$(cat "$AI_ANALYSIS_DIR/deps.md" | sed '/^$/d')
        local deps_lines=$(echo "$deps_content" | wc -l | tr -d ' ')
        if [[ $deps_lines -gt 2 ]]; then
            # 기존 의존성 섹션이 있으면 교체, 없으면 추가
            if grep -q "## 주요 의존성" "$dir/.claude/CLAUDE.md" 2>/dev/null; then
                local tmpfile=$(mktemp)
                local in_deps=false
                while IFS= read -r line; do
                    if [[ "$line" == "## 주요 의존성" ]]; then
                        echo "$line"
                        echo ""
                        echo "$deps_content"
                        echo ""
                        in_deps=true
                    elif [[ "$line" == "##"* && "$in_deps" == true ]]; then
                        in_deps=false
                        echo "$line"
                    elif [[ "$in_deps" == false ]]; then
                        echo "$line"
                    fi
                done < "$dir/.claude/CLAUDE.md" > "$tmpfile"
                cp "$tmpfile" "$dir/.claude/CLAUDE.md"
                rm -f "$tmpfile"
            fi
            ok "CLAUDE.md 주요 의존성 교체 (AI 분석)"
        fi
    fi

    # Backlog 적용 (v4 schema — AI 분석 결과를 통째로 덮어쓰기)
    if [[ -s "$AI_ANALYSIS_DIR/backlog.md" && -f "$dir/docs/backlog.md" ]]; then
        local bl_items
        bl_items=$(grep -c '^\- \[ \]' "$AI_ANALYSIS_DIR/backlog.md" 2>/dev/null) || bl_items=0
        if [[ $bl_items -gt 0 ]]; then
            local backlog_content=$(cat "$AI_ANALYSIS_DIR/backlog.md")
            # AI 분석 결과가 v4 헤더(`# Backlog` + `<!-- schema: v4 -->`)를 이미 포함하면 그대로 사용
            # Gemini 출력이 본문만(### 섹션부터) 오는 경우 v4 헤더로 감싸기
            if echo "$backlog_content" | head -3 | grep -q "schema: v4"; then
                # 이미 v4 완성형
                cp "$AI_ANALYSIS_DIR/backlog.md" "$dir/docs/backlog.md"
            else
                # Gemini가 본문만 출력한 경우 — v4 래퍼 추가
                local proj_name=$(basename "$dir")
                cat > "$dir/docs/backlog.md" << BL_EOF
# Backlog

<!-- schema: v4 -->
> 프로젝트: \`${proj_name}\`  ·  AI 분석 결과 (Gemini)

> 트랙: \`backend\` / \`frontend\` / \`data\` / \`infra\` / \`auth\` (메인) · \`ops\` / \`meta\` (메타)
> 진입 규칙: \`@dev backlog\` 무지정 시 메인 트랙만 후보.
> 상세: \`~/.claude/workflows/standard-routines.md\` "백로그 트랙 정책 (v4)"

${backlog_content}

## 완료

(완료 항목은 archive/로 이동)
BL_EOF
            fi
            ok "backlog.md 채움 (${bl_items}건, v4 schema)"
        fi
    fi

    # 정리
    rm -rf "$AI_ANALYSIS_DIR"
}

# ═══════════════════════════════════════════
# 주요 의존성 자동 감지
# ═══════════════════════════════════════════
detect_dependencies() {
    local dir="$1"
    local deps=""

    case "$LANG" in
        python)
            local pyproject="$dir/pyproject.toml"
            if [[ -f "$pyproject" ]]; then
                # [project].dependencies 에서 주요 패키지 추출
                deps=$(sed -n '/^dependencies/,/^\[/p' "$pyproject" 2>/dev/null \
                    | grep -E '^\s*"' \
                    | sed 's/.*"//;s/".*//' \
                    | grep -v '^$' \
                    | head -15 \
                    | while IFS= read -r dep; do
                        # 패키지명만 추출 (버전 제거)
                        local pkg=$(echo "$dep" | sed 's/[>=<\[].*//' | sed 's/^ *//')
                        [[ -n "$pkg" ]] && echo "- $pkg"
                    done)
            fi
            # requirements.txt 폴백
            if [[ -z "$deps" ]]; then
                for rf in "$dir/requirements.txt" "$dir/requirements/base.txt"; do
                    if [[ -f "$rf" ]]; then
                        deps=$(grep -v '^#\|^$\|^-' "$rf" 2>/dev/null | sed 's/[>=<].*//' | head -15 | sed 's/^/- /')
                        break
                    fi
                done
            fi
            ;;
        kotlin|java)
            local gf="$dir/build.gradle.kts"
            [[ ! -f "$gf" ]] && gf="$dir/build.gradle"
            if [[ -f "$gf" ]]; then
                deps=$(grep -E 'implementation|api\(' "$gf" 2>/dev/null \
                    | grep -v '//' \
                    | sed 's/.*"\(.*\)".*/\1/' \
                    | grep ':' \
                    | head -15 \
                    | sed 's/^/- /')
            fi
            ;;
        typescript)
            if [[ -f "$dir/package.json" ]]; then
                deps=$(python3 -c "
import json, sys
try:
    d = json.load(open('$dir/package.json'))
    for k in list(d.get('dependencies', {}).keys())[:15]:
        print(f'- {k}')
except: pass
" 2>/dev/null)
            fi
            ;;
        php)
            if [[ -f "$dir/composer.json" ]]; then
                deps=$(python3 -c "
import json, sys
try:
    d = json.load(open('$dir/composer.json'))
    for k in list(d.get('require', {}).keys())[:15]:
        if k != 'php': print(f'- {k}')
except: pass
" 2>/dev/null)
            fi
            ;;
        terraform)
            # required_providers 의 provider source (registry 경로) 추출. 로컬 모듈 ./ ../ 경로는 제외
            local _tflist
            _tflist=$(find "$dir" -maxdepth 4 -name "*.tf" -not -path '*/.terraform/*' -print0 2>/dev/null | xargs -0 grep -hE 'source[[:space:]]*=[[:space:]]*"[a-zA-Z0-9_-]+/[a-zA-Z0-9_./-]+"' 2>/dev/null)
            if [[ -n "$_tflist" ]]; then
                deps=$(echo "$_tflist" \
                    | sed 's/.*source[[:space:]]*=[[:space:]]*"//;s/".*//' \
                    | grep -vE '^\.\.?/' \
                    | grep -v '^$' \
                    | sort -u \
                    | head -15 \
                    | sed 's/^/- /')
            fi
            ;;
        swift)
            # 1. Package.swift dependencies
            if [[ -f "$dir/Package.swift" ]]; then
                deps=$(grep -oE '\.package\([^)]*url:\s*"[^"]+"' "$dir/Package.swift" 2>/dev/null \
                    | sed 's/.*url:\s*"//;s/".*//' \
                    | sed 's|.*/||;s/\.git$//' \
                    | head -15 \
                    | sed 's/^/- /')
            fi
            # 2. Podfile
            if [[ -z "$deps" && -f "$dir/Podfile" ]]; then
                deps=$(grep -E "^\s*pod\s+['\"]" "$dir/Podfile" 2>/dev/null \
                    | sed "s/.*pod\s*['\"]//;s/['\"].*//" \
                    | head -15 \
                    | sed 's/^/- /')
            fi
            # 3. Xcode 프로젝트의 SPM 의존성 (project.pbxproj에서 XCRemoteSwiftPackageReference)
            if [[ -z "$deps" ]]; then
                local pbx=$(find "$dir" -maxdepth 3 -name "project.pbxproj" -not -path '*/.git/*' 2>/dev/null | head -1)
                if [[ -n "$pbx" ]]; then
                    deps=$(grep -oE 'repositoryURL\s*=\s*"[^"]+"' "$pbx" 2>/dev/null \
                        | sed 's/.*"//;s/".*//' \
                        | sed 's|.*/||;s/\.git$//' \
                        | sort -u \
                        | head -15 \
                        | sed 's/^/- /')
                fi
            fi
            ;;
    esac

    echo "$deps"
}

# ═══════════════════════════════════════════
# 개별 파일 생성 함수들
# ═══════════════════════════════════════════

generate_claude_md() {
    local dir="$1"
    local name=$(basename "$dir")

    local DB_LINE=""
    [[ -n "${DB:-}" ]] && DB_LINE="| DB | $DB |
"

    local CMDS=""
    [[ -n "$BUILD_CMD" ]] && CMDS="${CMDS}\n# 빌드/의존성\n${BUILD_CMD}"
    [[ -n "$RUN_CMD" ]] && CMDS="${CMDS}\n\n# 개발 서버\n${RUN_CMD}"
    [[ -n "$TEST_CMD" ]] && CMDS="${CMDS}\n\n# 테스트\n${TEST_CMD}"
    [[ -n "$LINT_CMD" ]] && CMDS="${CMDS}\n\n# 린트\n${LINT_CMD}"
    [[ -n "$FORMAT_CMD" ]] && CMDS="${CMDS}\n\n# 포맷\n${FORMAT_CMD}"
    [[ -n "$TYPECHECK_CMD" ]] && CMDS="${CMDS}\n\n# 타입 체크\n${TYPECHECK_CMD}"

    local DIR_TREE=$(generate_dir_tree "$dir")
    local DEPS=$(detect_dependencies "$dir")

    local DEPS_SECTION=""
    if [[ -n "$DEPS" ]]; then
        DEPS_SECTION="## 주요 의존성

${DEPS}
"
    fi

    # 가이드 참조 자동 생성
    local GUIDE_REFS=""
    if [[ -d "$dir/docs/guides" ]]; then
        local guide_files=$(find "$dir/docs/guides" -name "*.md" -type f 2>/dev/null | sort)
        if [[ -n "$guide_files" ]]; then
            while IFS= read -r gf; do
                local gname=$(basename "$gf")
                local gtitle=$(head -1 "$gf" 2>/dev/null | sed 's/^# //')
                [[ -n "$gtitle" ]] && GUIDE_REFS="${GUIDE_REFS}
- ${gtitle} → \`docs/guides/${gname}\`"
            done <<< "$guide_files"
        fi
    fi

    local GUIDE_SECTION=""
    if [[ -n "$GUIDE_REFS" ]]; then
        GUIDE_SECTION="
${GUIDE_REFS}"
    fi

    # 문서 맵 자동 생성
    local DOC_MAP=""
    if [[ -d "$dir/docs" ]]; then
        [[ -f "$dir/docs/architecture.md" ]] && DOC_MAP="${DOC_MAP}
| 아키텍처 | \`docs/architecture.md\` | 시스템 역할, 디렉토리, 레이어, DI, DB 모델 |"
        [[ -f "$dir/docs/conventions.md" ]] && DOC_MAP="${DOC_MAP}
| 코딩 컨벤션 | \`docs/conventions.md\` | DI 패턴, 네이밍, 들여쓰기 규칙 |"
        [[ -f "$dir/docs/decisions.md" ]] && DOC_MAP="${DOC_MAP}
| 기술 결정 (ADR) | \`docs/decisions.md\` | 설계 결정 기록 |"
        [[ -d "$dir/docs/modules" ]] && DOC_MAP="${DOC_MAP}
| 모듈 상세 | \`docs/modules/\` | 모듈별 서비스/레포지토리 설명 |"
        [[ -d "$dir/docs/feature" ]] && DOC_MAP="${DOC_MAP}
| 기능 문서 | \`docs/feature/\` | 도메인별 개요, API, CHANGELOG |"
        [[ -d "$dir/docs/integrations" ]] && DOC_MAP="${DOC_MAP}
| 외부 연동 | \`docs/integrations/\` | 외부 시스템 연동 가이드 |"
        [[ -d "$dir/docs/error" ]] && DOC_MAP="${DOC_MAP}
| 에러 카탈로그 | \`docs/error/\` | 에러 코드, Known Issues |"
        [[ -d "$dir/docs/testing" ]] && DOC_MAP="${DOC_MAP}
| 테스트 | \`docs/testing/\` | 테스트 전략, 체크리스트 |"
        [[ -d "$dir/docs/guides" ]] && DOC_MAP="${DOC_MAP}
| 가이드 | \`docs/guides/\` | 설정, 운영 가이드 |"
        [[ -f "$dir/docs/backlog.md" ]] && DOC_MAP="${DOC_MAP}
| 백로그 | \`docs/backlog.md\` | 미완료 작업 목록 |"
    fi

    local DOC_MAP_SECTION=""
    if [[ -n "$DOC_MAP" ]]; then
        DOC_MAP_SECTION="## 문서 맵

| 주제 | 경로 | 내용 |
|------|------|------|${DOC_MAP}
"
    fi

    cat > "$dir/.claude/CLAUDE.md" << CLAUDE_EOF
# ${name}

## 프로젝트 개요

| 항목 | 값 |
|------|-----|
| 스택 | ${STACK_DETAIL} |
| 역할 | ${PROJECT_ROLE} |
${DB_LINE}| 패키지 매니저 | ${PKG_MGR:-없음} |

${DOC_MAP_SECTION}## 빌드/실행

\`\`\`bash$(printf '%b' "$CMDS")
\`\`\`

${DEPS_SECTION}## 아키텍처 규칙

<!-- TODO: 프로젝트 고유 아키텍처 규칙 작성 -->
상세: \`docs/architecture.md\`, \`docs/conventions.md\`

## Claude Code 규칙

- 커밋 메시지에 \`Co-Authored-By\` 포함하지 않음
- 커밋 메시지는 한글로 작성
- 문서: \`docs/\` 디렉토리 구조 참조 → \`docs/README.md\`
- 기술 결정: \`docs/decisions.md\` 기록${GUIDE_SECTION}

### 코드 검색 우선순위

1. \`mcp__local-rag__query_documents\` (의미론적 + 키워드)
2. \`Grep\` (정확한 패턴)
3. \`Glob\` (파일명/경로)
4. \`Read\` (위 결과에서 확인된 파일)
CLAUDE_EOF
}

generate_dev_md() {
    local dir="$1"
    local name=$(basename "$dir")

    # 태스크 라우팅 테이블 — 작업 키워드별 글로벌 에이전트 매칭
    # DEV_AGENT_TYPE은 키워드 매칭 실패 시 fallback (primary stack agent)
    local ROUTING_TABLE
    ROUTING_TABLE="| 백엔드 API | api, 엔드포인트, 서버, 라우터, 스키마 | backend-developer → code-reviewer → code-tester |
| 프론트엔드 UI | UI, 화면, 컴포넌트, 페이지, React, Vue | frontend-developer → code-reviewer → code-tester |
| 디자인/UX | 디자인, 스타일, CSS, UX, 와이어프레임 | designer → frontend-developer → code-reviewer |
| 데이터/쿼리 | 쿼리, 대시보드, SQL, ClickHouse, 분석, 코호트 | data-analyst |
| 인프라/배포 | docker, compose, deploy, terraform, CI, k8s | ops-lead → code-reviewer |
| AI/ML | 임베딩, RAG, 추천, 벡터, ML 파이프라인 | ai-engineer → code-reviewer |
| 기획/스펙 | PRD, 스펙, 요구사항, 로드맵, 우선순위 | po → prompt-engineer |
| 프롬프트 설계 | 프롬프트, 시스템 지시, agent.md, CLAUDE.md | prompt-engineer → code-reviewer |
| QA 설계 | 테스트 케이스, 회귀, E2E, 테스트 전략 | qa → code-tester |
| 코드베이스 분석/문서화 | 문서화, 온보딩, docs/, 인수인계, 코드베이스 파악, 현행화 | codebase-documenter |
| 버그/디버깅 | fix, bug, 에러, 오류, 안 됨 | debug-master → ${DEV_AGENT_TYPE} → code-reviewer → code-tester |
| 보안/인증 | 보안, JWT, 인증, OAuth, 취약점 | ${DEV_AGENT_TYPE} → code-reviewer + codex:adversarial-review |
| 리팩토링 | 리팩토링, 정리, 개선 | ${DEV_AGENT_TYPE} → code-reviewer |
| 설계 검토 | 설계, 아키텍처 | Plan → qa |
| 기타 신규 기능 (fallback) | 추가, 구현, 만들어 | Plan → ${DEV_AGENT_TYPE} → code-reviewer → code-tester |"

    local TEST_LINE=""
    [[ -n "$TEST_CMD" ]] && TEST_LINE="- 테스트: \`${TEST_CMD}\`"

    # 크로스 프로젝트 참조
    local CROSS_REF=""
    if [[ ${#RELATED_PROJECTS[@]} -gt 0 ]]; then
        CROSS_REF="
## 크로스 프로젝트 참조

| 프로젝트 | 경로 | 참조 시점 |
|----------|------|-----------|"
        for entry in "${RELATED_PROJECTS[@]}"; do
            local REL_PATH="${entry%%|*}"
            local REL_DESC="${entry#*|}"
            local REL_NAME=$(basename "$REL_PATH")
            CROSS_REF="${CROSS_REF}
| ${REL_NAME} | \`${REL_PATH}\` | ${REL_DESC} |"
        done
    fi

    # 워크플로우 분기 (Phase 기반 병렬)
    local WORKFLOW
    local PHASE2_TABLE
    if [[ "$DEV_AGENT_TYPE" == "ops-lead" ]]; then
        PHASE2_TABLE="| # | Agent | mode | 역할 |
|---|-------|------|------|
| 4a | code-reviewer | background | 코드 리뷰 |
| 4b | codex:review | background | Codex 병렬 리뷰 |
| 4c | codebase-documenter | background | mode=incremental: 변경 파일/diff 전달 → 영향 받은 기존 문서만 갱신 (신규 생성 없음) |"
    elif [[ -n "$TEST_CMD" ]]; then
        PHASE2_TABLE="| # | Agent | mode | 역할 |
|---|-------|------|------|
| 4a | code-reviewer | background | 코드 리뷰 |
| 4b | codex:review | background | Codex 병렬 리뷰 |
| 4c | code-tester | background | \`${TEST_CMD}\` 실행 |
| 4d | codebase-documenter | background | mode=incremental: 변경 파일/diff 전달 → 영향 받은 기존 문서만 갱신 (신규 생성 없음) |"
    else
        PHASE2_TABLE="| # | Agent | mode | 역할 |
|---|-------|------|------|
| 4a | code-reviewer | background | 코드 리뷰 |
| 4b | codex:review | background | Codex 병렬 리뷰 |
| 4c | codebase-documenter | background | mode=incremental: 변경 파일/diff 전달 → 영향 받은 기존 문서만 갱신 (신규 생성 없음) |"
    fi

    WORKFLOW="**Phase 0 — 분석 (순차)**
1. docs/ 로드 → 태스크 분석 → 규모 판단 (S/M/L)
2. **라우팅 결정**: 위 \`태스크 라우팅\` 표에서 작업 키워드 매칭 → 글로벌 에이전트 체인 확정. 매칭 실패 시 fallback은 \`${DEV_AGENT_TYPE}\`
3. M/L → 스펙 작성 (WHAT/WHY/수용기준) → Plan Mode (SDD)

**Phase 1 — 구현 (순차, 위임 우선)**
4. 선정된 글로벌 에이전트(들)에게 Agent 도구로 위임. 호출 시 \`컨텍스트 패싱\` 섹션의 항목을 프롬프트에 모두 포함
   - 병렬 가능한 에이전트(예: backend-developer + designer)는 단일 메시지로 동시 호출
   - trivial 변경(1~2파일, <10줄)만 직접 구현 허용

**Phase 2 — 검증 (병렬, 모두 background)**
구현 완료 즉시 동시 디스패치:

${PHASE2_TABLE}

**Phase 3 — 취합 (순차)**
5. Phase 2 결과 전부 수집
6. 리뷰 지적사항 있으면 수정 → 재검증 (최대 3회)
7. 에스컬레이션 조건 확인
8. 태스크 완료 → \`/session-handoff\` → 새 세션"

    cat > "$dir/.claude/agents/dev.md" << DEV_EOF
---
name: ${name}-dev
description: ${name} 프로젝트 도메인 전문가 + 글로벌 에이전트 코디네이터. ${STACK_DETAIL}. 직접 구현보다 라우팅·컨텍스트 패싱·결과 통합이 주 역할.
---

# ${name} 도메인 전문가 (글로벌 에이전트 코디네이터)

## 역할 정의

이 에이전트는 **프로젝트 도메인 전문가**이자 **글로벌 에이전트 코디네이터**다.

| 책임 | 설명 |
|------|------|
| 도메인 지식 | \`docs/\` 와 코드베이스에서 ${name} 프로젝트 컨텍스트를 보유 |
| 라우팅 결정 | 작업 키워드를 분석하여 가장 적합한 **글로벌 에이전트**(\`~/.claude/agents/*.md\`) 선정 |
| 컨텍스트 패싱 | 글로벌 에이전트 spawn 시 프로젝트 스택/문서/diff/결정사항을 프롬프트에 주입 |
| 결과 통합 | 글로벌 에이전트 결과를 받아 프로젝트 관점에서 검토·조정·다음 단계 결정 |
| 직접 구현 | trivial 변경(1~2파일, 10줄 미만, low-risk)에 한해 허용. 그 외는 위임 우선 |

## 세션 시작 프로토콜

1. \`docs/README.md\` 읽기
2. 작업 관련 \`docs/modules/*.md\` 읽기
3. \`docs/active/*.md\` 읽기 (진행 중 작업)
4. \`docs/backlog.md\` 확인
5. \`docs/decisions.md\` 참조 (기술 결정)
6. 최근 변경사항 확인 (\`git log --oneline -10\`)

## 프로젝트 특성

- ${STACK_DETAIL}
- ${PROJECT_ROLE}

## 글로벌 규칙 (반드시 준수)

글로벌 \`~/.claude/CLAUDE.md\`의 모든 규칙을 따른다. 핵심 요약:

### 코드 검색 우선순위
1. \`mcp__local-rag__query_documents\` (의미론적 + 키워드)
2. \`Grep\` (정확한 패턴)
3. \`Glob\` (파일명/경로)
4. \`Read\` (위 결과에서 확인된 파일)

### 디버깅 7단계
재현 → 수집 → 범위 축소 → 가설 수립 → 가설 검증 → 수정 → 확인. 추측 수정 금지.

### SSH 접속
반드시 \`expect\` 스크립트 사용. \`ssh\` 직접 실행 금지. MCP SSH 도구 우선.

### 파이프라인
코드 수정 시 최소: Gemini 스캔 → developer → 병렬(code-reviewer + codex:review) → tester.

### 파이프라인 단축 키워드

| 키워드 | 동작 |
|--------|------|
| "코드만", "구현만" | 개발 에이전트만 실행, 리뷰/테스트 생략 |
| "리뷰 없이", "검증 없이" | 리뷰 단계 생략 |
| "테스트 없이" | 테스트 단계 생략 |
| "파이프라인 없이", "단독으로" | 해당 에이전트만 단독 실행 |
| "TDD로" | qa 테스트 설계 → 사용자 확인 → developer Green 구현 |
| "스펙 없이" | SDD 스펙 작성 단계 생략 |

### SDD (Spec-Driven Development)
M/L 규모 태스크 → 구현 전 스펙 파일 선행 필수 (WHAT/WHY/수용기준) → Plan Mode → 태스크 분해 → 구현.

### TDD 순서 (신규 기능)
feature 태스크 → qa(테스트 설계) → 사용자 확인 → developer(Green 구현) → reviewer + codex.

### 컨텍스트 관리
1 태스크 = 1 세션. 태스크 완료 후 \`/session-handoff\` → 새 세션. Gemini 결과는 파일 저장 후 요약만 전달.

### 에스컬레이션 (글로벌)
- developer→tester 3회 실패 → \`codex:codex-rescue\` **foreground** 에스컬레이션
- 보안/DB/인프라/API breaking change → \`codex:adversarial-review\` 격상
- M/L 규모 → developer 구현 + \`codex:parallel-impl\` 대안 병렬 실행

아래는 프로젝트 고유 라우팅만 정의한다.

### 태스크 라우팅

| 태스크 유형 | 감지 키워드 | 에이전트 체인 |
|------------|-----------|--------------|
${ROUTING_TABLE}

### 에스컬레이션

- 3파일 이상 변경 → Plan 선행 필수
- 크로스 프로젝트 영향 감지 → @team 권유
- 리뷰 지적 3회 반복 → codex:rescue foreground
- 보안/DB 스키마 변경 → codex:adversarial-review 격상

### 컨텍스트 패싱 (글로벌 에이전트 호출 시 필수)

글로벌 에이전트(\`~/.claude/agents/*\`)는 **이 프로젝트를 모른다**. spawn 프롬프트에 다음을 반드시 포함:

1. **프로젝트 컨텍스트**: \`${name}\` — ${STACK_DETAIL}. ${PROJECT_ROLE}
2. **태스크**: 사용자 원본 요청 + 의도 요약
3. **관련 문서**: \`docs/modules/\` 에서 변경 영역 모듈 문서 핵심 발췌
4. **기술 결정**: \`docs/decisions.md\` 에서 관련 결정사항
5. **현재 상태**: 변경 파일 목록 + \`git diff\` 요약
6. **프로젝트 컨벤션**: \`.claude/CLAUDE.md\` 의 코딩 규칙
${TEST_LINE}

호출 예 (Agent 도구):
\`\`\`
subagent_type: backend-developer
prompt: |
  프로젝트: ${name} (${STACK_DETAIL})
  태스크: <원본 요청>
  관련 모듈 문서: <발췌>
  관련 결정: <발췌>
  변경 영역: <파일 경로 + diff>
  컨벤션: <CLAUDE.md 발췌>
\`\`\`

### 워크플로우

${WORKFLOW}
${CROSS_REF}

## 태스크 관리

### 명령어

| 명령 | 동작 |
|------|------|
| \`@dev backlog\` | backlog.md에서 최상위 미완료 항목 1개 선택 → active/ 파일 생성 → 실행 |
| \`@dev backlog 전체\` | backlog.md 미완료 항목 순차 처리 |
| \`@dev active\` | active/ 디렉토리의 미완료 작업 파일 순차 처리 |
| \`@dev active {파일명}\` | 특정 active 파일만 처리 |
| \`@dev document\` | \`codebase-documenter\` 호출 → 코드베이스 스캔/분석 → \`docs/\` 생성·갱신 (README, architecture, modules, conventions). 신규 온보딩·인수인계·현행화용 |
| \`@dev document {경로|모듈}\` | 특정 디렉토리/모듈만 범위 한정해서 문서화 |
| \`@dev {직접 지시}\` | 즉시 태스크 라우팅 → 실행 |

### backlog.md 파싱 규칙

- \`- [ ]\` 항목을 미완료 태스크로 인식, \`- [x]\`는 건너뜀
- 섹션 헤더로 우선순위 힌트 (높음/긴급 > 중간 > 낮음)
- 태스크 선택 후 → \`docs/active/YYYY-MM-DD-{태스크요약}.md\` 생성

### 완료 처리

1. active/ 파일 상태 → \`완료\`
2. backlog.md \`- [ ]\` → \`- [x]\`
3. active/ → \`archive/YYYY-MM/\` 이동

## 작업 완료 시

1. 변경 모듈의 \`docs/modules/{모듈}/\` 업데이트
2. 기술 결정 → \`docs/decisions.md\`
3. \`active/\` → \`archive/YYYY-MM/\` 이동
4. backlog 업데이트

## 인수인계

이 에이전트 + docs/ 폴더만 있으면 누구든 프로젝트 파악 가능.
DEV_EOF
}

generate_team_md() {
    local dir="$1"
    local name=$(basename "$dir")

    local TEAM_TABLE
    if [[ ${#RELATED_PROJECTS[@]} -gt 0 ]]; then
        TEAM_TABLE="| 프로젝트 | 경로 | 에이전트 | 연동 포인트 |
|----------|------|---------|------------|"
        for entry in "${RELATED_PROJECTS[@]}"; do
            local REL_PATH="${entry%%|*}"
            local REL_DESC="${entry#*|}"
            local REL_NAME=$(basename "$REL_PATH")
            TEAM_TABLE="${TEAM_TABLE}
| ${REL_NAME} | \`${REL_PATH}\` | @dev | ${REL_DESC} |"
        done
    else
        TEAM_TABLE="<!-- TODO: 연관 프로젝트 추가 -->
| 프로젝트 | 경로 | 에이전트 | 연동 포인트 |
|----------|------|---------|------------|"
    fi

    cat > "$dir/.claude/agents/team.md" << TEAM_EOF
---
name: ${name}-team
description: ${name} 크로스 프로젝트 팀 에이전트.
---

# ${name} 팀 에이전트

## 연관 프로젝트

${TEAM_TABLE}

## 팀 구성 규칙

- 연관 프로젝트 참조 필요 시 해당 프로젝트 @dev를 teammate로 spawn
- 각 teammate는 자기 프로젝트의 dev.md 라우팅을 따름
- 결과를 수집하여 통합 리뷰
TEAM_EOF
}

generate_docs_structure() {
    local dir="$1"
    local name=$(basename "$dir")

    # 디렉토리 생성
    mkdir -p "$dir/docs/active"
    mkdir -p "$dir/docs/archive"
    mkdir -p "$dir/docs/modules"
    mkdir -p "$dir/docs/error"
    mkdir -p "$dir/docs/testing"
    mkdir -p "$dir/docs/guides"
    touch "$dir/docs/active/.gitkeep"
    touch "$dir/docs/archive/.gitkeep"
    touch "$dir/docs/modules/.gitkeep"

    # docs/README.md — 네비게이션
    if [[ ! -f "$dir/docs/README.md" ]]; then
        cat > "$dir/docs/README.md" << DOCREADME_EOF
# 문서 네비게이션

## 가이드

| # | 문서 | 설명 |
|---|------|------|
<!-- 가이드 추가 시 행 추가 -->

## 모듈 × 카테고리

<!-- AUTO-START:matrix -->
| 모듈 | Overview | API | Errors | Tests |
|------|----------|-----|--------|-------|
<!-- AUTO-END:matrix -->

## 기타

| 문서 | 설명 |
|------|------|
| [backlog.md](backlog.md) | TODO |
| [error/](error/) | 에러 카탈로그 |
| [testing/](testing/) | 테스트 문서 |
| [active/](active/) | 진행 중 작업 |
| [archive/](archive/) | 완료 작업 |
| [decisions.md](decisions.md) | 기술 결정 기록 (ADR) |
DOCREADME_EOF
        ok "생성: docs/README.md"
    fi

    # docs/decisions.md — ADR
    if [[ ! -f "$dir/docs/decisions.md" ]]; then
        cat > "$dir/docs/decisions.md" << DECISIONS_EOF
# 기술 결정 기록 (ADR)

## 형식

### YYYY-MM-DD: 결정 제목

- **상태**: 제안 / 채택 / 폐기
- **맥락**: 왜 이 결정이 필요했는지
- **결정**: 무엇을 결정했는지
- **결과**: 이 결정으로 인한 영향

---

<!-- 새 결정은 위에 추가 -->
DECISIONS_EOF
        ok "생성: docs/decisions.md"
    fi

    # docs/error/README.md
    if [[ ! -f "$dir/docs/error/README.md" ]]; then
        cat > "$dir/docs/error/README.md" << ERRREADME_EOF
# 에러 카탈로그

모듈별 에러 코드와 대응 방법을 정리한다.

| 파일 | 모듈 | 설명 |
|------|------|------|
<!-- 에러 문서 추가 시 행 추가 -->
ERRREADME_EOF
        ok "생성: docs/error/README.md"
    fi

    # docs/testing/README.md
    if [[ ! -f "$dir/docs/testing/README.md" ]]; then
        local TEST_SECTION=""
        [[ -n "$TEST_CMD" ]] && TEST_SECTION="## 실행 방법

\`\`\`bash
${TEST_CMD}
\`\`\`"
        cat > "$dir/docs/testing/README.md" << TESTREADME_EOF
# 테스트 문서

${TEST_SECTION}

## 테스트 구조

<!-- 테스트 디렉토리 구조 및 전략 작성 -->

## 커버리지 목표

<!-- 커버리지 기준 작성 -->
TESTREADME_EOF
        ok "생성: docs/testing/README.md"
    fi

    # docs/backlog.md (schema v4 — 트랙 분리)
    if [[ ! -f "$dir/docs/backlog.md" ]]; then
        cat > "$dir/docs/backlog.md" << BACKLOG_EOF
# Backlog

<!-- schema: v4 -->
> 프로젝트: \`${name}\`  ·  총 0건  ·  메인 0 / 메타 0

> 트랙: \`backend\` / \`frontend\` / \`data\` / \`infra\` / \`auth\` (메인) · \`ops\` / \`meta\` (메타)
> 진입 규칙: \`@dev backlog\` 무지정 시 메인 트랙만 후보. 메타는 \`@dev backlog meta\` 명시 호출 필요.
> 상세: \`~/.claude/workflows/standard-routines.md\` "백로그 트랙 정책 (v4)"

## 메인 트랙

진입: \`@dev backlog\` (무지정 시 이 섹션만 후보)

### 높음 (High)

- [ ] \`[트랙]\` **항목 제목** — 설명
  - 위치: \`경로/파일.ext\`
  - 트리거: 🔒/🐛/⚡/🚀/📅/🔧 중 하나 + 구체 사유
  - DONE: 끝났는지 판단할 측정 기준
  - 추정: 30m / 1h / 2h / 1d / 2d

### 중간 (Medium)

(없음)

### 낮음 (Low)

(없음)

## 메타 트랙 (격리)

진입: \`@dev backlog meta\` 명시 호출 시만. \`@dev backlog\` 무지정 호출 시 **자동 제외**.

### 중간 (Medium)

(없음)

## 완료

(완료 항목은 archive/로 이동)
BACKLOG_EOF
        ok "생성: docs/backlog.md (schema v4)"
    fi
}

generate_settings_json() {
    local dir="$1"

    # ── 공통 허용 규칙 ──
    local ALLOW_RULES='"mcp__local-rag__query_documents"'
    # RAG 관련
    ALLOW_RULES="${ALLOW_RULES},\n      \"mcp__local-rag__ingest_file\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"mcp__local-rag__ingest_data\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"mcp__local-rag__list_files\""
    # 스킬
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(ask-gemini)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(ask-codex)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(debug)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(logs)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(cross-check)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(check-sso-compat)\""
    # 세션 관련 스킬
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(session-handoff)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(done)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(start)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Skill(today-tasks)\""
    # SSH expect
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(expect:*)\""
    # MCP SSH
    ALLOW_RULES="${ALLOW_RULES},\n      \"mcp__ssh__runRemoteCommand\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"mcp__ssh__checkConnectivity\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"mcp__ssh__getHostInfo\""
    # git 읽기 명령
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git log:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git diff:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git status:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git branch:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git show:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git blame:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git stash list:*)\""

    # ── 스택별 허용 규칙 ──
    case "$LANG" in
        python)
            [[ -n "$TEST_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TEST_CMD} 2>&1)\""
            [[ -n "$LINT_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${LINT_CMD} 2>&1 | tail -20)\""
            [[ -n "$FORMAT_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${FORMAT_CMD} 2>&1 | head -200)\""
            [[ -n "$TYPECHECK_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TYPECHECK_CMD} 2>&1 | tail -20)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(uv run python:*)\""
            ;;
        kotlin|java)
            [[ -n "$TEST_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TEST_CMD} 2>&1)\""
            [[ -n "$BUILD_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${BUILD_CMD} 2>&1)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(./gradlew:*)\""
            ;;
        typescript)
            [[ -n "$TEST_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TEST_CMD} 2>&1)\""
            [[ -n "$LINT_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${LINT_CMD} 2>&1)\""
            [[ -n "$TYPECHECK_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TYPECHECK_CMD} 2>&1)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(npm run build 2>&1)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(npx:*)\""
            ;;
        php)
            [[ -n "$TEST_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TEST_CMD} 2>&1)\""
            [[ -n "$LINT_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${LINT_CMD} 2>&1)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(php:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(composer:*)\""
            ;;
        docker)
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(docker compose ps 2>&1)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(docker compose logs:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(docker compose config:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(docker ps:*)\""
            ;;
        go)
            [[ -n "$TEST_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TEST_CMD} 2>&1)\""
            [[ -n "$LINT_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${LINT_CMD} 2>&1)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(go build:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(go run:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(go vet:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(go mod:*)\""
            ;;
        rust)
            [[ -n "$TEST_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${TEST_CMD} 2>&1)\""
            [[ -n "$LINT_CMD" ]] && ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(${LINT_CMD} 2>&1)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(cargo build:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(cargo run:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(cargo test:*)\""
            ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(cargo clippy:*)\""
            ;;
    esac

    # ── 공통 git 쓰기 명령 ──
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git add:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git checkout:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git switch:*)\""
    ALLOW_RULES="${ALLOW_RULES},\n      \"Bash(git commit:*)\""

    # ── hooks 설정 ──
    local HOOKS_JSON=""
    if [[ -d "$dir/.claude/hooks" ]]; then
        local pre_hook="$dir/.claude/hooks/pre-commit-check.sh"
        if [[ -f "$pre_hook" ]]; then
            HOOKS_JSON=',\n  "hooks": {\n    "PreToolUse": [\n      {\n        "matcher": "Bash",\n        "hooks": [".claude/hooks/pre-commit-check.sh"]\n      }\n    ]\n  }'
        fi
    fi

    printf '{
  "permissions": {
    "allow": [
      %b
    ]
  }%b
}\n' "$ALLOW_RULES" "$HOOKS_JSON" > "$dir/.claude/settings.local.json"
}

# ═══════════════════════════════════════════
# .gitignore 관리
# ═══════════════════════════════════════════
ensure_gitignore() {
    local dir="$1"
    local gitignore="$dir/.gitignore"

    # git 리포가 아니면 건너뜀
    [[ ! -d "$dir/.git" ]] && return

    local entries=(
        ".claude/settings.local.json"
        ".claude/todos.json"
        ".claude/projects/"
        ".claude/memory/"
    )

    if [[ ! -f "$gitignore" ]]; then
        section ".gitignore 생성"
        printf '# Claude Code 로컬 설정\n' > "$gitignore"
        for entry in "${entries[@]}"; do
            echo "$entry" >> "$gitignore"
        done
        ok ".gitignore 생성 (Claude 항목 ${#entries[@]}개)"
        return
    fi

    local added=0
    for entry in "${entries[@]}"; do
        if ! grep -qF "$entry" "$gitignore" 2>/dev/null; then
            echo "$entry" >> "$gitignore"
            added=$((added + 1))
        fi
    done

    if [[ $added -gt 0 ]]; then
        ok ".gitignore에 Claude 항목 ${added}개 추가"
    else
        skip ".gitignore: Claude 항목 이미 존재"
    fi
}

# ═══════════════════════════════════════════
# 글로벌 프로젝트 테이블 자동 등록
# ═══════════════════════════════════════════
register_global_project() {
    local dir="$1"
    local name=$(basename "$dir")
    local global_claude="$HOME/.claude/CLAUDE.md"
    [[ ! -f "$global_claude" ]] && return

    # 이미 등록되어 있는지 확인
    if grep -qF "| $name " "$global_claude" 2>/dev/null || grep -qF "| ${name} |" "$global_claude" 2>/dev/null; then
        skip "글로벌 프로젝트 테이블: ${name} 이미 등록"
        return
    fi

    # 프로젝트 테이블의 마지막 행 찾기
    local last_row
    last_row=$(grep -n '| `~/' "$global_claude" | tail -1)
    if [[ -z "$last_row" ]]; then
        warn "글로벌 프로젝트 테이블을 찾을 수 없음 → 수동 등록 필요"
        return
    fi

    local line_num=${last_row%%:*}
    local short_path="${dir/#$HOME/~}"
    local new_row="| ${name} | \`${short_path}\` | ${STACK_DETAIL} |"

    # sed로 마지막 프로젝트 행 뒤에 삽입
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "${line_num}a\\
${new_row}" "$global_claude"
    else
        sed -i "${line_num}a\\${new_row}" "$global_claude"
    fi

    ok "글로벌 프로젝트 테이블에 ${name} 등록"
}

# ═══════════════════════════════════════════
# hooks 템플릿 생성
# ═══════════════════════════════════════════
generate_hooks() {
    local dir="$1"
    local name=$(basename "$dir")
    local hooks_dir="$dir/.claude/hooks"

    [[ -d "$hooks_dir" ]] && { skip "hooks 디렉토리 이미 존재"; return; }

    mkdir -p "$hooks_dir"

    # PreToolUse: Co-Authored-By 차단 hook
    cat > "$hooks_dir/pre-commit-check.sh" << 'HOOK_EOF'
#!/bin/bash
# PreToolUse: Bash(git commit*) 시 Co-Authored-By 차단
# 훅 등록: settings.local.json → hooks.PreToolUse

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [[ "$TOOL" == "Bash" ]]; then
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    if echo "$CMD" | grep -qi "git commit" && echo "$CMD" | grep -qi "Co-Authored-By"; then
        echo '{"decision": "block", "reason": "커밋 메시지에 Co-Authored-By 포함 금지 (글로벌 규칙)"}'
        exit 0
    fi
fi

echo '{"decision": "approve"}'
HOOK_EOF
    chmod +x "$hooks_dir/pre-commit-check.sh"

    # PostToolUse: 파일 생성 시 RAG 인덱싱 알림
    cat > "$hooks_dir/post-write-rag-hint.sh" << 'HOOK_EOF'
#!/bin/bash
# PostToolUse: Write/Edit 완료 후 RAG 인덱싱 리마인더

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [[ "$TOOL" == "Write" ]]; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    if [[ -n "$FILE" && "$FILE" == *.py || "$FILE" == *.ts || "$FILE" == *.kt || "$FILE" == *.php || "$FILE" == *.md ]]; then
        echo "신규 파일 생성됨: ${FILE} → mcp__local-rag__ingest_file 권장"
    fi
fi
HOOK_EOF
    chmod +x "$hooks_dir/post-write-rag-hint.sh"

    ok "hooks 생성: pre-commit-check.sh, post-write-rag-hint.sh"
    info "settings.local.json에 hooks 등록이 필요합니다"
}

# ═══════════════════════════════════════════
# 기존 파일 비교 + 선택적 업데이트
# ═══════════════════════════════════════════
update_existing_project() {
    local dir="$1"
    local name=$(basename "$dir")

    header "기존 설정 감사: ${name}"

    # 감사 실행
    audit_project "$dir" || true
    echo ""

    # 누락 파일 생성
    local created=0
    local updated=0

    for f in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "$dir/$f" ]]; then
            section "생성: $f"
            case "$f" in
                ".claude/CLAUDE.md")
                    mkdir -p "$dir/.claude"
                    generate_claude_md "$dir"
                    ok "생성: $f"
                    created=$((created + 1))
                    ;;
                ".claude/agents/dev.md")
                    mkdir -p "$dir/.claude/agents"
                    generate_dev_md "$dir"
                    ok "생성: $f"
                    created=$((created + 1))
                    ;;
                ".claude/agents/team.md")
                    mkdir -p "$dir/.claude/agents"
                    generate_team_md "$dir"
                    ok "생성: $f"
                    created=$((created + 1))
                    ;;
                ".claude/settings.local.json")
                    mkdir -p "$dir/.claude"
                    generate_settings_json "$dir"
                    ok "생성: $f"
                    created=$((created + 1))
                    ;;
                "docs/backlog.md"|"docs/README.md"|"docs/decisions.md")
                    generate_docs_structure "$dir"
                    created=$((created + 1))
                    ;;
            esac
        fi
    done

    # 기존 파일 섹션 검사 + 보강
    if [[ -f "$dir/.claude/CLAUDE.md" && $created -eq 0 ]]; then
        section "CLAUDE.md 섹션 검사"
        local needs_update=false
        local existing="$dir/.claude/CLAUDE.md"
        local tmpfile=$(mktemp)
        cp "$existing" "$tmpfile"

        for sec in "${REQUIRED_SECTIONS_CLAUDE[@]}"; do
            if ! grep -q "## $sec\|## .*$sec" "$existing" 2>/dev/null; then
                warn "'${sec}' 섹션 누락 → 추가"
                case "$sec" in
                    "프로젝트 개요")
                        echo -e "\n## 프로젝트 개요\n\n| 항목 | 값 |\n|------|-----|\n| 스택 | ${STACK_DETAIL} |\n| 역할 | ${PROJECT_ROLE} |\n| 패키지 매니저 | ${PKG_MGR:-없음} |" >> "$tmpfile"
                        ;;
                    "디렉토리 구조")
                        local DIR_TREE=$(generate_dir_tree "$dir")
                        echo -e "\n## 디렉토리 구조\n\n\`\`\`\n${DIR_TREE}\n\`\`\`" >> "$tmpfile"
                        ;;
                    "빌드/실행")
                        local CMDS=""
                        [[ -n "$BUILD_CMD" ]] && CMDS="${CMDS}\n${BUILD_CMD}"
                        [[ -n "$TEST_CMD" ]] && CMDS="${CMDS}\n${TEST_CMD}"
                        [[ -n "$LINT_CMD" ]] && CMDS="${CMDS}\n${LINT_CMD}"
                        echo -e "\n## 빌드/실행\n\n\`\`\`bash$(printf '%b' "$CMDS")\n\`\`\`" >> "$tmpfile"
                        ;;
                    "아키텍처 규칙")
                        echo -e "\n## 아키텍처 규칙\n\n<!-- TODO: 프로젝트 고유 아키텍처 규칙 작성 -->" >> "$tmpfile"
                        ;;
                    "Claude Code 규칙")
                        echo -e "\n## Claude Code 규칙\n\n- 커밋 메시지에 \`Co-Authored-By\` 포함하지 않음\n- 커밋 메시지는 한글로 작성" >> "$tmpfile"
                        ;;
                esac
                needs_update=true
            else
                ok "'${sec}' 존재"
            fi
        done

        if $needs_update; then
            if confirm_yes "CLAUDE.md에 누락 섹션을 추가할까요?"; then
                cp "$tmpfile" "$existing"
                ok "CLAUDE.md 업데이트 완료"
                updated=$((updated + 1))
            fi
        fi
        rm -f "$tmpfile"
    fi

    # dev.md frontmatter 검사
    if [[ -f "$dir/.claude/agents/dev.md" ]]; then
        section "dev.md 검사"
        if ! head -1 "$dir/.claude/agents/dev.md" | grep -q "^---" 2>/dev/null; then
            warn "YAML frontmatter 누락"
            if confirm_yes "frontmatter를 추가할까요?"; then
                local tmpdev=$(mktemp)
                cat > "$tmpdev" << FM_EOF
---
name: ${name}-dev
description: ${name} 전담 개발 에이전트. ${STACK_DETAIL}.
---

FM_EOF
                cat "$dir/.claude/agents/dev.md" >> "$tmpdev"
                cp "$tmpdev" "$dir/.claude/agents/dev.md"
                rm -f "$tmpdev"
                ok "frontmatter 추가 완료"
                updated=$((updated + 1))
            fi
        else
            ok "frontmatter 존재"
        fi

        # 필수 섹션 검사
        for sec in "${REQUIRED_SECTIONS_DEV[@]}"; do
            if grep -q "$sec" "$dir/.claude/agents/dev.md" 2>/dev/null; then
                ok "dev.md: '${sec}' 존재"
            else
                warn "dev.md: '${sec}' 누락"
            fi
        done
    fi

    # settings.local.json 검증
    if [[ -f "$dir/.claude/settings.local.json" ]]; then
        section "settings.local.json 검사"
        if python3 -c "import json; json.load(open('$dir/.claude/settings.local.json'))" 2>/dev/null; then
            ok "JSON 유효"
            local rule_count
            rule_count=$(python3 -c "import json; d=json.load(open('$dir/.claude/settings.local.json')); print(len(d.get('permissions',{}).get('allow',[])))" 2>/dev/null) || rule_count=0
            info "허용 규칙: ${rule_count}개"
        else
            err "JSON 파싱 에러"
            if confirm_yes "재생성할까요?"; then
                generate_settings_json "$dir"
                ok "settings.local.json 재생성"
                updated=$((updated + 1))
            fi
        fi
    fi

    # hooks 검사
    if [[ ! -d "$dir/.claude/hooks" ]]; then
        section "hooks 디렉토리 없음"
        if confirm_yes "hooks 템플릿을 생성할까요?"; then
            generate_hooks "$dir"
            created=$((created + 1))
        fi
    else
        ok "hooks 디렉토리 존재"
    fi

    # .gitignore 검사
    ensure_gitignore "$dir"

    # AI 분석으로 빈 섹션 채우기
    local has_todo
    has_todo=$(grep -c "<!-- TODO" "$dir/.claude/CLAUDE.md" 2>/dev/null) || has_todo=0
    local has_empty_backlog=false
    if [[ -f "$dir/docs/backlog.md" ]]; then
        grep -q "항목 제목" "$dir/docs/backlog.md" 2>/dev/null && has_empty_backlog=true
        grep -q "(추가 필요)" "$dir/docs/backlog.md" 2>/dev/null && has_empty_backlog=true
        # backlog에 실제 항목이 없으면
        local real_items
        real_items=$(grep -c '^\- \[ \]' "$dir/docs/backlog.md" 2>/dev/null) || real_items=0
        [[ $real_items -eq 0 ]] && has_empty_backlog=true
    fi

    if [[ $has_todo -gt 0 || "$has_empty_backlog" == true ]]; then
        section "빈 섹션 감지 → AI 분석 실행"
        if $HAS_GEMINI; then
            if analyze_with_gemini "$dir"; then
                $HAS_CODEX && validate_with_codex "$dir"
                apply_ai_analysis "$dir"
            else
                analyze_static "$dir"
                apply_ai_analysis "$dir"
            fi
        else
            analyze_static "$dir"
            apply_ai_analysis "$dir"
        fi
    fi

    # 결과 요약
    echo ""
    header "업데이트 결과"
    info "신규 생성: ${created}개"
    info "업데이트: ${updated}개"
}

# ═══════════════════════════════════════════
# 신규 프로젝트 전체 생성
# ═══════════════════════════════════════════
create_new_project() {
    local dir="$1"

    mkdir -p "$dir/.claude/agents"
    ok "디렉토리 생성: .claude/agents/"

    generate_claude_md "$dir"
    ok "생성: .claude/CLAUDE.md"

    generate_dev_md "$dir"
    ok "생성: .claude/agents/dev.md"

    generate_team_md "$dir"
    ok "생성: .claude/agents/team.md"

    generate_settings_json "$dir"
    ok "생성: .claude/settings.local.json"

    generate_docs_structure "$dir"

    generate_hooks "$dir"

    ensure_gitignore "$dir"

    register_global_project "$dir"

    # AI 분석으로 실제 내용 채우기
    if $HAS_GEMINI; then
        if analyze_with_gemini "$dir"; then
            $HAS_CODEX && validate_with_codex "$dir"
            apply_ai_analysis "$dir"
        else
            analyze_static "$dir"
            apply_ai_analysis "$dir"
        fi
    else
        analyze_static "$dir"
        apply_ai_analysis "$dir"
    fi

    # RAG 인덱싱 안내
    section "후속 작업 안내"
    info "Claude Code 세션에서 RAG 인덱싱 실행 권장:"
    info "  mcp__local-rag__ingest_file 로 주요 파일 인덱싱"
}

# AI 도구 확인 (모든 모드에서)
check_ai_tools

# ═══════════════════════════════════════════
# --rebuild 모드: 기존 설정 백업 후 전체 재생성
# ═══════════════════════════════════════════
if [[ "${1:-}" == "--rebuild" ]]; then
    shift
    AUTO_CONFIRM=true

    PROJECT_DIR="${1:-}"
    [[ -z "$PROJECT_DIR" ]] && { err "사용법: init-claude-config.sh --rebuild <프로젝트경로>"; exit 1; }

    PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")"
    [[ ! -d "$PROJECT_DIR" ]] && { err "디렉토리가 존재하지 않음: $PROJECT_DIR"; exit 1; }

    PROJECT_NAME=$(basename "$PROJECT_DIR")
    header "전체 재생성 모드: ${PROJECT_NAME}"

    # 스택 감지
    detected=$(detect_stack "$PROJECT_DIR")
    if load_stack_preset "$detected"; then
        ok "스택: ${STACK}"
    else
        err "스택 감지 실패 → 대화형 모드 사용 필요"
        exit 1
    fi

    PROJECT_ROLE=$(detect_role "$PROJECT_DIR")
    ok "역할: ${PROJECT_ROLE}"

    DB=$(detect_db "$PROJECT_DIR")
    [[ -n "$DB" ]] && ok "DB: ${DB}" || skip "DB: 감지 안 됨"

    RELATED_PROJECTS=()
    while IFS= read -r rel; do
        [[ -n "$rel" ]] && RELATED_PROJECTS+=("$rel")
    done < <(detect_related_projects "$PROJECT_DIR")
    [[ ${#RELATED_PROJECTS[@]} -gt 0 ]] && ok "연관 프로젝트: ${#RELATED_PROJECTS[@]}개" || skip "연관 프로젝트: 없음"

    # 백업
    if [[ -d "$PROJECT_DIR/.claude" ]]; then
        BACKUP_DIR="$PROJECT_DIR/.claude/_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"

        # 재생성 대상만 백업 (settings.local.json은 유지)
        for f in CLAUDE.md agents/dev.md agents/team.md; do
            if [[ -f "$PROJECT_DIR/.claude/$f" ]]; then
                mkdir -p "$(dirname "$BACKUP_DIR/$f")"
                cp "$PROJECT_DIR/.claude/$f" "$BACKUP_DIR/$f"
            fi
        done
        ok "백업: $BACKUP_DIR"
    fi

    # 전체 재생성
    mkdir -p "$PROJECT_DIR/.claude/agents"

    section "CLAUDE.md 재생성"
    generate_claude_md "$PROJECT_DIR"
    ok "재생성: .claude/CLAUDE.md"

    section "dev.md 재생성"
    generate_dev_md "$PROJECT_DIR"
    ok "재생성: .claude/agents/dev.md"

    section "team.md 재생성"
    generate_team_md "$PROJECT_DIR"
    ok "재생성: .claude/agents/team.md"

    # settings.local.json은 재생성 (권한 규칙 최신화)
    section "settings.local.json 재생성"
    generate_settings_json "$PROJECT_DIR"
    ok "재생성: .claude/settings.local.json"

    # docs 구조 보강 (없는 것만)
    generate_docs_structure "$PROJECT_DIR"

    # hooks 보강 (없는 경우만)
    if [[ ! -d "$PROJECT_DIR/.claude/hooks" ]]; then
        generate_hooks "$PROJECT_DIR"
    fi

    ensure_gitignore "$PROJECT_DIR"

    # AI 분석으로 빈 섹션 채우기
    local has_todo
    has_todo=$(grep -c "<!-- TODO" "$PROJECT_DIR/.claude/CLAUDE.md" 2>/dev/null) || has_todo=0
    if [[ $has_todo -gt 0 ]]; then
        section "빈 섹션 → AI 분석"
        if $HAS_GEMINI; then
            if analyze_with_gemini "$PROJECT_DIR"; then
                $HAS_CODEX && validate_with_codex "$PROJECT_DIR"
                apply_ai_analysis "$PROJECT_DIR"
            else
                analyze_static "$PROJECT_DIR"
                apply_ai_analysis "$PROJECT_DIR"
            fi
        else
            analyze_static "$PROJECT_DIR"
            apply_ai_analysis "$PROJECT_DIR"
        fi
    fi

    # 최종 감사
    echo ""
    header "최종 상태"
    audit_project "$PROJECT_DIR" || true

    echo ""
    ok "전체 재생성 완료: ${PROJECT_NAME}"
    info "이전 설정: ${BACKUP_DIR:-없음}"
    exit 0
fi

# ═══════════════════════════════════════════
# --audit 모드: 전체 프로젝트 감사
# ═══════════════════════════════════════════
if [[ "${1:-}" == "--audit" ]]; then
    header "전체 프로젝트 Claude 설정 감사"

    WORKSPACE="${2:-$HOME/Workspace}"
    echo "스캔 대상: $WORKSPACE\n"

    total=0
    complete=0

    for dir in "$WORKSPACE"/*/; do
        [[ ! -d "$dir" ]] && continue
        total=$((total + 1))

        # .claude 디렉토리가 있거나 git 리포인 경우만
        if [[ -d "$dir/.claude" || -d "$dir/.git" ]]; then
            if audit_project "${dir%/}"; then
                complete=$((complete + 1))
            fi
            echo ""
        fi
    done

    echo ""
    header "요약"
    info "전체 프로젝트: ${total}"
    info "설정 완전: ${complete}"
    info "미완성: $((total - complete))"
    exit 0
fi

# ═══════════════════════════════════════════
# --batch 모드: 일괄 처리
# ═══════════════════════════════════════════
if [[ "${1:-}" == "--batch" ]]; then
    AUTO_CONFIRM=true
    shift
    for dir in "$@"; do
        dir="${dir/#\~/$HOME}"
        dir="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"
        [[ ! -d "$dir" ]] && { err "없는 경로: $dir"; continue; }

        header "처리: $(basename "$dir")"

        # 스택 자동 감지
        detected=$(detect_stack "$dir")
        if load_stack_preset "$detected"; then
            ok "스택 감지: $STACK"
        else
            warn "스택 감지 실패: $dir — 건너뜀"
            continue
        fi

        PROJECT_ROLE=$(detect_role "$dir")
        DB=$(detect_db "$dir")
        RELATED_PROJECTS=()
        while IFS= read -r rel; do
            [[ -n "$rel" ]] && RELATED_PROJECTS+=("$rel")
        done < <(detect_related_projects "$dir")

        ok "역할: ${PROJECT_ROLE}"
        [[ -n "$DB" ]] && ok "DB: ${DB}" || skip "DB: 없음"
        [[ ${#RELATED_PROJECTS[@]} -gt 0 ]] && ok "연관: ${#RELATED_PROJECTS[@]}개" || skip "연관: 없음"

        if [[ -d "$dir/.claude" ]]; then
            update_existing_project "$dir"
        else
            create_new_project "$dir"
        fi
    done
    exit 0
fi

# ═══════════════════════════════════════════
# --auto 모드: 단일 프로젝트 완전 자동
# ═══════════════════════════════════════════
if [[ "${1:-}" == "--auto" ]]; then
    shift
    AUTO_CONFIRM=true

    PROJECT_DIR="${1:-}"
    [[ -z "$PROJECT_DIR" ]] && { err "사용법: init-claude-config.sh --auto <프로젝트경로>"; exit 1; }

    PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")"
    [[ ! -d "$PROJECT_DIR" ]] && { err "디렉토리가 존재하지 않음: $PROJECT_DIR"; exit 1; }

    PROJECT_NAME=$(basename "$PROJECT_DIR")
    header "완전 자동 모드: ${PROJECT_NAME}"

    # 스택 감지
    detected=$(detect_stack "$PROJECT_DIR")
    if load_stack_preset "$detected"; then
        ok "스택: ${STACK}"
    else
        err "스택 감지 실패 → 대화형 모드 사용 필요"
        exit 1
    fi

    # 역할 감지
    PROJECT_ROLE=$(detect_role "$PROJECT_DIR")
    ok "역할: ${PROJECT_ROLE}"

    # DB 감지
    DB=$(detect_db "$PROJECT_DIR")
    [[ -n "$DB" ]] && ok "DB: ${DB}" || skip "DB: 감지 안 됨"

    # 연관 프로젝트 감지
    RELATED_PROJECTS=()
    while IFS= read -r rel; do
        [[ -n "$rel" ]] && RELATED_PROJECTS+=("$rel")
    done < <(detect_related_projects "$PROJECT_DIR")
    if [[ ${#RELATED_PROJECTS[@]} -gt 0 ]]; then
        ok "연관 프로젝트: ${#RELATED_PROJECTS[@]}개"
        for entry in "${RELATED_PROJECTS[@]}"; do
            info "  → ${entry%%|*} (${entry#*|})"
        done
    else
        skip "연관 프로젝트: 없음"
    fi

    echo ""

    # 기존/신규 분기
    if [[ -d "$PROJECT_DIR/.claude" ]]; then
        update_existing_project "$PROJECT_DIR"
    else
        create_new_project "$PROJECT_DIR"
    fi

    # 최종 감사
    echo ""
    header "최종 상태"
    audit_project "$PROJECT_DIR" || true

    echo ""
    todo_count=$(grep -r "TODO" "$PROJECT_DIR/.claude/" 2>/dev/null | wc -l | tr -d ' ')
    if [[ $todo_count -gt 0 ]]; then
        echo "${YELLOW}TODO ${todo_count}개:${NC}"
        grep -rn "TODO" "$PROJECT_DIR/.claude/" 2>/dev/null | while IFS= read -r line; do
            echo "  ${YELLOW}!${NC} $line"
        done
    fi

    echo ""
    ok "완료: ${PROJECT_NAME}"
    exit 0
fi

# ═══════════════════════════════════════════
# 메인: 단일 프로젝트 대화형
# ═══════════════════════════════════════════
PROJECT_DIR="${1:-}"
if [[ -z "$PROJECT_DIR" ]]; then
    ask "프로젝트 경로"
    read PROJECT_DIR
fi

PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")"

if [[ ! -d "$PROJECT_DIR" ]]; then
    err "디렉토리가 존재하지 않음: $PROJECT_DIR"
    exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_DIR")
IS_EXISTING=false
[[ -d "$PROJECT_DIR/.claude" ]] && IS_EXISTING=true

if $IS_EXISTING; then
    header "기존 프로젝트 감지: ${PROJECT_NAME}"
    info ".claude/ 디렉토리가 이미 존재합니다"
    echo ""
    echo "  ${BOLD}1)${NC} 감사만 (현재 상태 확인)"
    echo "  ${BOLD}2)${NC} 감사 + 누락 항목 생성/업데이트"
    echo "  ${BOLD}3)${NC} 전체 재생성 (기존 설정 덮어쓰기)"
    echo "  ${BOLD}4)${NC} 취소"
    ask "선택"
    read MODE_CHOICE
else
    header "새 프로젝트: ${PROJECT_NAME}"
    MODE_CHOICE="new"
fi

# 스택 감지
detected=$(detect_stack "$PROJECT_DIR")

case "$MODE_CHOICE" in
    1)
        # 감사만
        if load_stack_preset "$detected"; then
            info "스택 감지: $STACK"
        fi
        echo ""
        audit_project "$PROJECT_DIR" || true
        exit 0
        ;;
    4)
        info "취소됨"
        exit 0
        ;;
esac

# 스택 선택 (자동 감지 → 확인 → 직접 선택)
if load_stack_preset "$detected"; then
    info "스택 자동 감지: ${BOLD}${STACK}${NC}"
    ask "맞으면 Enter, 아니면 다른 번호 입력"
    read STACK_OVERRIDE
    if [[ -n "$STACK_OVERRIDE" ]]; then
        # 번호로 재선택
        case "$STACK_OVERRIDE" in
            1) load_stack_preset "fastapi" ;;
            2) load_stack_preset "springboot" ;;
            3) load_stack_preset "php" ;;
            4) load_stack_preset "nextjs" ;;
            5) load_stack_preset "keycloak-spi" ;;
            6) load_stack_preset "docker" ;;
            7) load_stack_preset "python-lib" ;;
            8) load_stack_preset "node" ;;
            9) load_stack_preset "go" ;;
            10) load_stack_preset "rust" ;;
            11) load_stack_preset "ios" ;;
            12) load_stack_preset "swift-lib" ;;
            13) load_stack_preset "terraform" ;;
            *) interactive_stack_select ;;
        esac
    fi
else
    warn "스택 자동 감지 실패"
    interactive_stack_select
fi

# 프로젝트 역할
if $IS_EXISTING && [[ -f "$PROJECT_DIR/.claude/CLAUDE.md" ]]; then
    existing_role=$(grep -A1 "| 역할 |" "$PROJECT_DIR/.claude/CLAUDE.md" 2>/dev/null | tail -1 | sed 's/.*| //;s/ |.*//' || echo "")
    if [[ -n "$existing_role" && "$existing_role" != *"역할"* ]]; then
        info "기존 역할: ${existing_role}"
        ask "변경하려면 입력 (유지하려면 Enter)"
        read NEW_ROLE
        PROJECT_ROLE="${NEW_ROLE:-$existing_role}"
    else
        ask "프로젝트 역할/설명 (한줄)"
        read PROJECT_ROLE
    fi
else
    ask "프로젝트 역할/설명 (한줄)"
    read PROJECT_ROLE
fi

# DB 선택 (자동 감지 결과 활용)
AUTO_DB=$(detect_db "$PROJECT_DIR")
if [[ -n "$AUTO_DB" ]]; then
    info "DB 자동 감지: ${BOLD}${AUTO_DB}${NC}"
    ask "맞으면 Enter, 아니면 번호 선택 (1:MySQL 2:PG 3:Redis 4:없음 5:기타)"
    read DB_CHOICE
    if [[ -z "$DB_CHOICE" ]]; then
        DB="$AUTO_DB"
    else
        case "$DB_CHOICE" in
            1) DB="MySQL 8.0" ;;
            2) DB="PostgreSQL" ;;
            3) DB="Redis" ;;
            4) DB="" ;;
            5) ask "DB명"; read DB ;;
            *) DB="$AUTO_DB" ;;
        esac
    fi
else
    echo "${BOLD}DB:${NC}"
    echo "  1) MySQL  2) PostgreSQL  3) Redis만  4) 없음  5) 기타"
    ask "번호"
    read DB_CHOICE
    case "$DB_CHOICE" in
        1) DB="MySQL 8.0" ;;
        2) DB="PostgreSQL" ;;
        3) DB="Redis" ;;
        4) DB="" ;;
        5) ask "DB명"; read DB ;;
        *) DB="" ;;
    esac
fi

# 연관 프로젝트
echo ""
info "연관 프로젝트 (크로스 프로젝트 참조용)"
RELATED_PROJECTS=()
while true; do
    ask "연관 프로젝트 경로 (없으면 Enter)"
    read REL_PATH
    [[ -z "$REL_PATH" ]] && break
    ask "연동 포인트 설명"
    read REL_DESC
    RELATED_PROJECTS+=("${REL_PATH}|${REL_DESC}")
done

# 실행
case "$MODE_CHOICE" in
    2)
        update_existing_project "$PROJECT_DIR"
        ;;
    3)
        warn "기존 설정을 덮어씁니다"
        if confirm_no "정말 계속할까요?"; then
            create_new_project "$PROJECT_DIR"
        else
            info "취소됨"
            exit 0
        fi
        ;;
    new)
        create_new_project "$PROJECT_DIR"
        ;;
esac

# ─── 최종 감사 ───
echo ""
header "최종 상태"
audit_project "$PROJECT_DIR" || true

echo ""
echo "${YELLOW}TODO 확인:${NC}"
todo_count=$(grep -r "TODO" "$PROJECT_DIR/.claude/" 2>/dev/null | wc -l | tr -d ' ')
if [[ $todo_count -gt 0 ]]; then
    grep -rn "TODO" "$PROJECT_DIR/.claude/" 2>/dev/null | while IFS= read -r line; do
        echo "  ${YELLOW}!${NC} $line"
    done
else
    ok "TODO 항목 없음"
fi

echo ""
ok "완료: ${PROJECT_NAME}"
