#!/usr/bin/env bash
set -euo pipefail

MODE="sync"
DRY_RUN=false
QUIET=false

usage() {
    cat <<'EOF'
사용법:
  ~/.claude/scripts/sync-codex.sh
  ~/.claude/scripts/sync-codex.sh --dry-run
  ~/.claude/scripts/sync-codex.sh status
  ~/.claude/scripts/sync-codex.sh --quiet

동기화 대상:
  - ~/.claude/CLAUDE.md -> ~/.codex/AGENTS.md
  - ~/Workspace/*/CLAUDE.md -> 각 프로젝트 AGENTS.md
  - ~/.claude/settings.json -> ~/.codex/hooks.json (지원 이벤트만)
  - ~/.claude/skills/* -> ~/.codex/skills/* (없는 항목만 심링크)
EOF
}

log() {
    if [[ "$QUIET" == "false" ]]; then
        echo "[sync-codex] $*"
    fi
}

warn() {
    echo "[sync-codex] $*" >&2
}

run_copy() {
    local source_path="$1"
    local target_path="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] cp $source_path $target_path"
        return 0
    fi

    mkdir -p "$(dirname "$target_path")"

    if [[ -L "$target_path" ]]; then
        rm "$target_path"
    fi

    cp "$source_path" "$target_path"
}

append_unique_line() {
    local target_file="$1"
    local line="$2"

    [[ -n "$line" ]] || return 0

    if [[ -f "$target_file" ]] && grep -Fqx -- "$line" "$target_file" 2>/dev/null; then
        return 0
    fi

    printf '%s\n' "$line" >> "$target_file"
}

json_array_from_file() {
    local source_file="$1"

    if [[ -s "$source_file" ]]; then
        jq -R . < "$source_file" | jq -s .
    else
        echo '[]'
    fi
}

extract_markdown_section() {
    local source_file="$1"
    local section_title="$2"

    awk -v heading="## ${section_title}" '
        $0 == heading { capture = 1 }
        capture {
            if (started && /^## / && $0 != heading) {
                exit
            }
            print
            started = 1
        }
    ' "$source_file"
}

list_workspace_project_sources() {
    local project_dir
    local project_name
    local root_claude_file
    local hidden_claude_file
    local source_file

    for project_dir in "$WORKSPACE_DIR"/*; do
        [[ -d "$project_dir" ]] || continue
        project_name="$(basename "$project_dir")"
        [[ "$project_name" == ".claude" ]] && continue

        root_claude_file="$project_dir/CLAUDE.md"
        hidden_claude_file="$project_dir/.claude/CLAUDE.md"
        source_file=""

        if [[ -f "$root_claude_file" ]]; then
            source_file="$root_claude_file"
        elif [[ -f "$hidden_claude_file" ]]; then
            source_file="$hidden_claude_file"
        fi

        [[ -n "$source_file" ]] || continue
        printf '%s\t%s\n' "$project_dir" "$source_file"
    done | sort
}

build_project_agents_file() {
    local project_dir="$1"
    local claude_file="$2"
    local target_file="$3"
    local project_name
    local local_dev_agent
    local local_team_agent
    local backlog_file
    local active_dir

    project_name="$(basename "$project_dir")"
    local_dev_agent="$project_dir/.claude/agents/dev.md"
    local_team_agent="$project_dir/.claude/agents/team.md"
    backlog_file="$project_dir/docs/backlog.md"
    active_dir="$project_dir/docs/active"

    {
        cat <<EOF
# Project Codex Instructions

이 파일은 \`$claude_file\` 를 기준으로 \`sync-codex\`가 갱신한다.
프로젝트별 Claude 규칙은 유지하고, Codex에서 바로 쓰기 위한 호환 규칙만 상단에 덧붙인다.

## Codex Compatibility

- 현재 프로젝트: \`$project_name\`
- 전역 역할 호출 규칙은 \`~/.codex/AGENTS.md\`를 따른다.
- 아래 원본 프로젝트 규칙과 전역 규칙이 충돌하면 더 구체적인 프로젝트 규칙을 우선한다.

### 프로젝트 호출

EOF

        if [[ -f "$local_dev_agent" ]]; then
            printf -- "- \`@dev\`: \`%s\` 를 먼저 읽고 그 라우팅 규칙을 따른다.\n" "$local_dev_agent"
        else
            echo "- \`@dev\`: 로컬 에이전트가 없으면 전역 \`~/.claude/agents/dev-lead.md\`를 사용한다."
        fi

        if [[ -f "$local_team_agent" ]]; then
            printf -- "- \`@team\`: \`%s\` 를 먼저 읽고 크로스 프로젝트 영향 범위를 판단한다.\n" "$local_team_agent"
        else
            echo "- \`@team\`: 로컬 team 에이전트가 없으면 전역 규칙과 관련 저장소 문맥으로 best-effort 대응한다."
        fi

        cat <<'EOF'

### 자주 쓰는 호출 예시

- `@dev 지금 작업 진행해`
- `백엔드 현재 프로젝트 기능 구현해`
- `리뷰어 현재 변경분 리뷰해`
- `테스터 관련 테스트만 확인해`

### 프로젝트 태스크 문서

EOF

        if [[ -f "$backlog_file" ]]; then
            printf -- "- backlog: \`%s\`\n" "$backlog_file"
        else
            printf -- "- backlog: \`docs/backlog.md\` 없음\n"
        fi

        if [[ -d "$active_dir" ]]; then
            printf -- "- active: \`%s\`\n" "$active_dir"
        else
            printf -- "- active: \`docs/active/\` 없음\n"
        fi

        cat <<'EOF'

## Source Project Rules

아래는 프로젝트 원본 `CLAUDE.md` 내용이다.

EOF

        cat "$claude_file"
    } > "$target_file"
}

build_global_agents_file() {
    local target_file="$1"
    local section_title
    local section_text
    local sections=(
        "응답 스타일"
        "커밋 규칙"
        "디버깅 규칙"
        "SSH 접속 규칙"
        "코딩 컨벤션"
        "문서 작성 규칙"
        "프로젝트 공통 규칙"
        "프로젝트 목록"
        "SSO 핵심 정책"
    )

    {
        cat <<'EOF'
# Codex CLI Instructions

이 파일은 `~/.claude/CLAUDE.md`를 기준으로 `sync-codex`가 갱신한다.
Claude 전용 에이전트 파이프라인, MCP 검색 규칙, 제품 고유 워크플로우는 제외하고 Codex에서 바로 적용 가능한 규칙만 유지한다.

## Role

코드 분석, 구현, 디버깅, 리뷰를 수행하는 시니어 엔지니어. Claude 설정과의 이질감을 줄이되 Codex의 도구와 권한 모델에 맞춰 행동한다.

## Language

- 출력은 한글
- 커밋 메시지는 한글
- Co-Authored-By 포함하지 않음

## Migration Rules

- `~/.claude`를 소스 오브 트루스로 둔다.
- `~/.claude/agents/*.md`는 필요할 때 직접 읽어 역할 프롬프트로 재사용한다.
- Claude 전용 파이프라인, Agent/MCP 호출, 제품 고유 훅은 Codex의 스킬, 내장 서브에이전트, `hooks.json`으로 대체한다.

## Hybrid Orchestration

- Codex의 `UserPromptSubmit` 훅이 필요 시 Gemini와 Claude 보조 실행을 백그라운드로 시작할 수 있다.
- 생성되는 보조 컨텍스트:
  - `~/.claude/cache/gemini/{project}-scan.md`
  - `~/.claude/cache/gemini/{project}-review-prescan.md`
  - `~/.claude/cache/claude/{project}-codex-brief.md`
- Workspace 프로젝트에서 작업할 때 위 파일이 있고 최근 생성되었다면 먼저 읽고 참고한다.
- 기본 fresh 기준:
  - 프로젝트 스캔: 30분
  - 리뷰 프리스캔: 10분
  - Claude brief: 15분
- 이 보조 출력은 참고 자료다. 프로젝트 실제 코드와 규칙이 더 우선한다.

## Claude Compatibility

Claude 스타일 호출문을 Codex에서도 호환 모드로 해석한다. 이 호출은 네이티브 에이전트 import가 아니라, 해당 프롬프트 파일을 먼저 읽고 그 역할에 맞춰 작업하는 규칙이다.

### 호출 해석 우선순위

1. 현재 프로젝트의 `.claude/agents/{name}.md`
2. 현재 프로젝트의 `CLAUDE.md` 및 `docs/`
3. 전역 `~/.claude/agents/{name}.md`

### 프로젝트 호출

- `@dev`: 현재 프로젝트의 `.claude/agents/dev.md`를 우선 읽고 그 라우팅 규칙을 따른다. 프로젝트 파일이 없으면 `~/.claude/agents/dev-lead.md`를 대신 사용한다.
- `@team`: 현재 프로젝트의 `.claude/agents/team.md`를 우선 읽고 크로스 프로젝트 영향 범위를 기준으로 진행한다. 프로젝트 파일이 없으면 전역 규칙과 관련 저장소 문맥으로 best-effort 대응한다.

### 역할 호출 매핑

아래 호출명이 요청 첫머리나 핵심 지시로 오면 해당 프롬프트를 읽고 역할을 적용한다.

| 호출명 | 프롬프트 |
|--------|----------|
| `백엔드` | `~/.claude/agents/backend-developer.md` |
| `backend`, `backend-developer` | `~/.claude/agents/backend-developer.md` |
| `프론트` | `~/.claude/agents/frontend-developer.md` |
| `frontend`, `frontend-developer` | `~/.claude/agents/frontend-developer.md` |
| `AI엔지니어` | `~/.claude/agents/ai-engineer.md` |
| `ai`, `ai-engineer` | `~/.claude/agents/ai-engineer.md` |
| `테스터` | `~/.claude/agents/code-tester.md` |
| `tester`, `code-tester` | `~/.claude/agents/code-tester.md` |
| `리뷰어` | `~/.claude/agents/code-reviewer.md` |
| `reviewer`, `code-reviewer` | `~/.claude/agents/code-reviewer.md` |
| `큐에이` | `~/.claude/agents/qa.md` |
| `qa` | `~/.claude/agents/qa.md` |
| `디자이너` | `~/.claude/agents/designer.md` |
| `designer` | `~/.claude/agents/designer.md` |
| `피오` | `~/.claude/agents/po.md` |
| `po` | `~/.claude/agents/po.md` |
| `데이터` | `~/.claude/agents/data-analyst.md` |
| `data`, `data-analyst` | `~/.claude/agents/data-analyst.md` |
| `옵스` | `~/.claude/agents/ops-lead.md` |
| `ops`, `ops-lead` | `~/.claude/agents/ops-lead.md` |
| `프롬프트` | `~/.claude/agents/prompt-engineer.md` |
| `prompt`, `prompt-engineer` | `~/.claude/agents/prompt-engineer.md` |
| `디버그`, `디버깅`, `debug-master` | `~/.claude/agents/debug-master.md` |
| `dev-lead` | `~/.claude/agents/dev-lead.md` |

### 실행 규칙

- 역할 호출이 오면 먼저 해당 프롬프트 파일을 읽고, 필요한 경우 현재 프로젝트 규칙과 합성해서 적용한다.
- 사용자가 병렬 처리나 서브에이전트를 요구하면 Codex 내장 `worker`, `explorer`, `default`를 쓰되 위 프롬프트의 역할을 그대로 넘긴다.
- 사용자가 역할만 지정하고 파일명을 안 적어도 된다. 예: `리뷰어 지금 변경분 봐줘`, `백엔드 identity-hub 로그인 API 구현해`.
- 전역 `~/.claude/agents/*.md` 또는 현재 프로젝트 `.claude/agents/*.md`의 **파일명 자체**를 역할명으로 써도 된다. 예: `backend-developer`, `code-reviewer`, `ops-lead`, `dev`.
- 매핑에 없는 에이전트도 경로를 직접 지정하면 된다. 예: `~/.claude/agents/dev-lead.md처럼 진행해`, `./.claude/agents/dev.md 기준으로 처리해`.

### 호환 키워드

- `코드만`, `구현만`: 구현 우선. 리뷰/테스트 생략 요청으로 해석한다.
- `리뷰 없이`, `검증 없이`: 리뷰 단계 생략 요청으로 해석한다.
- `테스트 없이`: 테스트 생략 요청으로 해석한다.
- `파이프라인 없이`, `단독으로`: 단일 역할로만 수행한다.
- `TDD로`: 테스트 케이스 우선 설계 후 구현 순서로 해석한다.
- `스펙 없이`: 스펙 문서 선행 단계를 생략한다.

### 호출 예시

- `@dev backlog`
- `@dev active`
- `백엔드 identity-hub 로그인 API 구현해`
- `리뷰어 현재 diff 리뷰해`
- `@team 이 API 변경 영향 범위 같이 봐`

EOF

        for section_title in "${sections[@]}"; do
            section_text="$(extract_markdown_section "$CLAUDE_GLOBAL_FILE" "$section_title")"
            if [[ -n "$section_text" ]]; then
                printf '%s\n\n' "$section_text"
            fi
        done
    } > "$target_file"
}

build_codex_hooks_file() {
    local target_file="$1"
    local session_commands_file="$TEMP_DIR/session-hooks.txt"
    local prompt_commands_file="$TEMP_DIR/prompt-hooks.txt"
    local stop_commands_file="$TEMP_DIR/stop-hooks.txt"
    local session_json
    local prompt_json
    local stop_json

    : > "$session_commands_file"
    : > "$prompt_commands_file"
    : > "$stop_commands_file"

    append_unique_line "$session_commands_file" "$SYNC_SCRIPT_FILE --quiet"

    if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
        while IFS= read -r command_line; do
            append_unique_line "$session_commands_file" "$command_line"
        done < <(jq -r '.hooks.SessionStart[]?.hooks[]?.command // empty' "$CLAUDE_SETTINGS_FILE" 2>/dev/null)

        while IFS= read -r command_line; do
            append_unique_line "$stop_commands_file" "$command_line"
        done < <(jq -r '.hooks.Stop[]?.hooks[]?.command // empty' "$CLAUDE_SETTINGS_FILE" 2>/dev/null)
    fi

    if [[ -f "$CLAUDE_DIR/hooks/codex-session-notify.sh" ]]; then
        append_unique_line "$session_commands_file" "$CLAUDE_DIR/hooks/codex-session-notify.sh"
    fi

    if [[ -f "$CLAUDE_DIR/hooks/codex-prompt-notify.sh" ]]; then
        append_unique_line "$prompt_commands_file" "$CLAUDE_DIR/hooks/codex-prompt-notify.sh"
    fi

    if [[ ! -s "$prompt_commands_file" ]]; then
        append_unique_line "$prompt_commands_file" "$CLAUDE_DIR/hooks/codex-prompt-notify.sh"
    fi

    if [[ -f "$CLAUDE_DIR/hooks/codex-hybrid-orchestrator.sh" ]]; then
        append_unique_line "$prompt_commands_file" "/bin/zsh $CLAUDE_DIR/hooks/codex-hybrid-orchestrator.sh"
    fi

    session_json="$(json_array_from_file "$session_commands_file")"
    prompt_json="$(json_array_from_file "$prompt_commands_file")"
    stop_json="$(json_array_from_file "$stop_commands_file")"

    jq -n \
        --argjson session_commands "$session_json" \
        --argjson prompt_commands "$prompt_json" \
        --argjson stop_commands "$stop_json" \
        '{
            hooks: {
                SessionStart: [
                    {
                        hooks: ($session_commands | map({type: "command", command: .}))
                    }
                ],
                UserPromptSubmit: [
                    {
                        hooks: ($prompt_commands | map({type: "command", command: .}))
                    }
                ],
                Stop: [
                    {
                        hooks: ($stop_commands | map({type: "command", command: .}))
                    }
                ]
            }
        }' > "$target_file"
}

sync_generated_file() {
    local source_path="$1"
    local target_path="$2"
    local changed=1

    if [[ -f "$target_path" ]] && cmp -s "$source_path" "$target_path"; then
        changed=0
    fi

    if [[ "$changed" -eq 1 ]]; then
        run_copy "$source_path" "$target_path"
        return 0
    fi

    return 1
}

sync_global_agents() {
    local generated_file="$TEMP_DIR/AGENTS.md"

    build_global_agents_file "$generated_file"

    if sync_generated_file "$generated_file" "$CODEX_AGENTS_FILE"; then
        GLOBAL_AGENTS_CHANGED=1
        log "글로벌 AGENTS.md 갱신"
    else
        GLOBAL_AGENTS_CHANGED=0
        log "글로벌 AGENTS.md 최신 상태"
    fi
}

sync_workspace_agents() {
    local project_dir
    local claude_file
    local agents_file
    local generated_file

    PROJECTS_UPDATED=0
    PROJECTS_SCANNED=0

    while IFS=$'\t' read -r project_dir claude_file; do
        [[ -n "$project_dir" ]] || continue
        [[ -n "$claude_file" ]] || continue

        agents_file="$project_dir/AGENTS.md"
        generated_file="$TEMP_DIR/$(basename "$project_dir").AGENTS.md"
        PROJECTS_SCANNED=$((PROJECTS_SCANNED + 1))

        build_project_agents_file "$project_dir" "$claude_file" "$generated_file"

        if sync_generated_file "$generated_file" "$agents_file"; then
            PROJECTS_UPDATED=$((PROJECTS_UPDATED + 1))
            log "$(basename "$project_dir")/AGENTS.md 갱신"
        fi
    done < <(list_workspace_project_sources)
}

sync_skills() {
    local skill_dir
    local skill_name
    local target_path

    SKILLS_TOTAL=0
    SKILLS_LINKED=0
    SKILLS_AVAILABLE=0

    mkdir -p "$CODEX_SKILLS_DIR"

    for skill_dir in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -d "$skill_dir" ]] || continue
        [[ -f "$skill_dir/SKILL.md" ]] || continue

        skill_name="$(basename "$skill_dir")"
        target_path="$CODEX_SKILLS_DIR/$skill_name"
        SKILLS_TOTAL=$((SKILLS_TOTAL + 1))

        if [[ -L "$target_path" ]] && [[ ! -e "$target_path" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[dry-run] rm $target_path"
            else
                rm "$target_path"
            fi
        fi

        if [[ -e "$target_path" ]]; then
            SKILLS_AVAILABLE=$((SKILLS_AVAILABLE + 1))
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] ln -s $skill_dir $target_path"
        else
            ln -s "$skill_dir" "$target_path"
        fi

        SKILLS_LINKED=$((SKILLS_LINKED + 1))
        SKILLS_AVAILABLE=$((SKILLS_AVAILABLE + 1))
    done
}

sync_hooks() {
    local generated_file="$TEMP_DIR/hooks.json"

    build_codex_hooks_file "$generated_file"

    if sync_generated_file "$generated_file" "$CODEX_HOOKS_FILE"; then
        HOOKS_CHANGED=1
        log "Codex hooks.json 갱신"
    else
        HOOKS_CHANGED=0
        log "Codex hooks.json 최신 상태"
    fi
}

print_status() {
    local generated_agents_file="$TEMP_DIR/status-AGENTS.md"
    local generated_hooks_file="$TEMP_DIR/status-hooks.json"
    local unsupported_events
    local global_status="최신"
    local hooks_status="최신"
    local project_dir
    local project_file
    local project_agents_file
    local project_status
    local generated_project_file

    build_global_agents_file "$generated_agents_file"
    build_codex_hooks_file "$generated_hooks_file"

    if [[ ! -f "$CODEX_AGENTS_FILE" ]] || ! cmp -s "$generated_agents_file" "$CODEX_AGENTS_FILE"; then
        global_status="드리프트"
    fi

    if [[ ! -f "$CODEX_HOOKS_FILE" ]] || ! cmp -s "$generated_hooks_file" "$CODEX_HOOKS_FILE"; then
        hooks_status="드리프트"
    fi

    SKILLS_TOTAL=0
    SKILLS_AVAILABLE=0
    for project_file in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -d "$project_file" ]] || continue
        [[ -f "$project_file/SKILL.md" ]] || continue
        SKILLS_TOTAL=$((SKILLS_TOTAL + 1))
        if [[ -e "$CODEX_SKILLS_DIR/$(basename "$project_file")" ]]; then
            SKILLS_AVAILABLE=$((SKILLS_AVAILABLE + 1))
        fi
    done

    unsupported_events="$(
        jq -r '.hooks | keys[]' "$CLAUDE_SETTINGS_FILE" 2>/dev/null \
            | grep -Ev '^(SessionStart|Stop)$' \
            || true
    )"

    echo "=== Codex 동기화 상태 ==="
    echo ""
    echo "글로벌 AGENTS: $global_status"
    echo "Codex hooks:   $hooks_status"
    echo "스킬:          $SKILLS_AVAILABLE/$SKILLS_TOTAL 사용 가능"
    echo ""
    echo "| 프로젝트 | 상태 |"
    echo "|----------|------|"

    while IFS=$'\t' read -r project_dir project_file; do
        [[ -n "$project_dir" ]] || continue
        [[ -n "$project_file" ]] || continue

        project_agents_file="$project_dir/AGENTS.md"
        generated_project_file="$TEMP_DIR/$(basename "$project_dir").status.AGENTS.md"
        build_project_agents_file "$project_dir" "$project_file" "$generated_project_file"

        if [[ ! -f "$project_agents_file" ]]; then
            project_status="미생성"
        elif cmp -s "$generated_project_file" "$project_agents_file"; then
            project_status="최신"
        else
            project_status="드리프트"
        fi
        echo "| $(basename "$project_dir") | $project_status |"
    done < <(list_workspace_project_sources)

    echo ""
    echo "지원 외 Claude 훅 이벤트:"
    if [[ -n "$unsupported_events" ]]; then
        printf '%s\n' "$unsupported_events"
    else
        echo "없음"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        status)
            MODE="status"
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --quiet)
            QUIET=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            warn "알 수 없는 인자: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if ! command -v jq >/dev/null 2>&1; then
    warn "jq가 필요합니다."
    exit 1
fi

CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"
WORKSPACE_DIR="$HOME/Workspace"

CLAUDE_GLOBAL_FILE="$CLAUDE_DIR/CLAUDE.md"
CLAUDE_SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CLAUDE_SKILLS_DIR="$CLAUDE_DIR/skills"
SYNC_SCRIPT_FILE="$CLAUDE_DIR/scripts/sync-codex.sh"

CODEX_AGENTS_FILE="$CODEX_DIR/AGENTS.md"
CODEX_HOOKS_FILE="$CODEX_DIR/hooks.json"
CODEX_SKILLS_DIR="$CODEX_DIR/skills"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sync-codex.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

[[ -f "$CLAUDE_GLOBAL_FILE" ]] || { warn "글로벌 CLAUDE.md를 찾을 수 없습니다: $CLAUDE_GLOBAL_FILE"; exit 1; }
[[ -f "$CLAUDE_SETTINGS_FILE" ]] || { warn "settings.json을 찾을 수 없습니다: $CLAUDE_SETTINGS_FILE"; exit 1; }

if [[ "$MODE" == "status" ]]; then
    print_status
    exit 0
fi

log "1/4 글로벌 규칙 동기화"
sync_global_agents

log "2/4 프로젝트 규칙 동기화"
sync_workspace_agents

log "3/4 Codex hooks 동기화"
sync_hooks

log "4/4 Claude 스킬 링크 동기화"
sync_skills

if [[ "$QUIET" == "false" ]]; then
    echo ""
    echo "=== 동기화 완료 ==="
    echo "글로벌 AGENTS: $([[ "$GLOBAL_AGENTS_CHANGED" -eq 1 ]] && echo "갱신" || echo "최신")"
    echo "프로젝트 AGENTS: ${PROJECTS_UPDATED}개 갱신 / ${PROJECTS_SCANNED}개 확인"
    echo "Codex hooks: $([[ "$HOOKS_CHANGED" -eq 1 ]] && echo "갱신" || echo "최신")"
    echo "스킬: ${SKILLS_AVAILABLE}/${SKILLS_TOTAL} 사용 가능 (신규 링크 ${SKILLS_LINKED}개)"
    echo ""
    echo "다음에 다시 실행:"
    echo "  ~/.claude/scripts/sync-codex.sh"
    echo "  ~/.claude/scripts/sync-codex.sh status"
    echo "  ~/.claude/scripts/sync-codex.sh --dry-run"
fi
