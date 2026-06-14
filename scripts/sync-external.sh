#!/usr/bin/env bash
set -euo pipefail

MODE="sync"
DRY_RUN=false
QUIET=false

CLAUDE_DIR="${HOME}/.claude"
CODEX_DIR="${HOME}/.codex"
GEMINI_DIR="${HOME}/.gemini"
AGENTS_DIR="${HOME}/.agents"
WORKSPACE_DIR="${HOME}/Workspace"

CLAUDE_GLOBAL_FILE="${CLAUDE_DIR}/CLAUDE.md"
CLAUDE_SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CLAUDE_SKILLS_DIR="${CLAUDE_DIR}/skills"
CLAUDE_WORKFLOWS_DIR="${CLAUDE_DIR}/workflows"
CLAUDE_AGENTS_DIR="${CLAUDE_DIR}/agents"
CLAUDE_SHARED_DIR="${CLAUDE_DIR}/shared"
SYNC_SCRIPT_FILE="${CLAUDE_DIR}/scripts/sync-external.sh"

CODEX_AGENTS_FILE="${CODEX_DIR}/AGENTS.md"
CODEX_HOOKS_FILE="${CODEX_DIR}/hooks.json"
CODEX_WORKFLOWS_DIR="${CODEX_DIR}/workflows"
CODEX_AGENTS_DIR="${CODEX_DIR}/agents"
CODEX_SHARED_DIR="${CODEX_DIR}/shared"

GEMINI_AGENTS_FILE="${GEMINI_DIR}/GEMINI.md"
GEMINI_HOOKS_FILE="${GEMINI_DIR}/hooks.json"
GEMINI_WORKFLOWS_DIR="${GEMINI_DIR}/workflows"
GEMINI_AGENTS_DIR="${GEMINI_DIR}/agents"
GEMINI_SHARED_DIR="${GEMINI_DIR}/shared"

# Agent Skills 멀티툴 표준 (Gemini CLI 공식: .agents/skills interop alias)
AGENTS_SKILLS_DIR="${AGENTS_DIR}/skills"
AGENTS_SHARED_DIR="${AGENTS_DIR}/shared"
AGENTS_REGISTRY_DIR="${AGENTS_DIR}/registry"
AGENTS_SCRIPTS_DIR="${AGENTS_DIR}/scripts"
AGENTS_CACHE_LINK="${AGENTS_DIR}/cache"

TEMP_DIR=""

GLOBAL_CODEX_CHANGED=0
GLOBAL_GEMINI_CHANGED=0
PROJECTS_SCANNED=0
PROJECTS_CREATED=0
PROJECTS_SKIPPED=0
AGENTS_SKILLS_TOTAL=0
AGENTS_SKILLS_LINKED=0
AGENTS_SKILLS_AVAILABLE=0
AGENTS_SHARED_TOTAL=0
AGENTS_SHARED_LINKED=0
AGENTS_SHARED_AVAILABLE=0
AGENTS_REGISTRY_TOTAL=0
AGENTS_REGISTRY_LINKED=0
AGENTS_REGISTRY_AVAILABLE=0
AGENTS_SCRIPTS_TOTAL=0
AGENTS_SCRIPTS_LINKED=0
AGENTS_SCRIPTS_AVAILABLE=0
CODEX_WORKFLOWS_TOTAL=0
CODEX_WORKFLOWS_LINKED=0
CODEX_WORKFLOWS_AVAILABLE=0
GEMINI_WORKFLOWS_TOTAL=0
GEMINI_WORKFLOWS_LINKED=0
GEMINI_WORKFLOWS_AVAILABLE=0
CODEX_AGENTS_TOTAL=0
CODEX_AGENTS_LINKED=0
CODEX_AGENTS_AVAILABLE=0
GEMINI_AGENTS_TOTAL=0
GEMINI_AGENTS_LINKED=0
GEMINI_AGENTS_AVAILABLE=0
CODEX_SHARED_TOTAL=0
CODEX_SHARED_LINKED=0
CODEX_SHARED_AVAILABLE=0
GEMINI_SHARED_TOTAL=0
GEMINI_SHARED_LINKED=0
GEMINI_SHARED_AVAILABLE=0
CODEX_HOOKS_CHANGED=0
GEMINI_HOOKS_CHANGED=0

usage() {
    cat <<'EOF'
사용법:
  ~/.claude/scripts/sync-external.sh
  ~/.claude/scripts/sync-external.sh --dry-run
  ~/.claude/scripts/sync-external.sh --quiet
  ~/.claude/scripts/sync-external.sh status

동기화 대상:
  - ~/.claude/CLAUDE.md -> ~/.codex/AGENTS.md
  - ~/.claude/CLAUDE.md -> ~/.gemini/GEMINI.md
  - ~/Workspace/*/CLAUDE.md 또는 ~/Workspace/*/.claude/CLAUDE.md -> 각 프로젝트 AGENTS.md
  - ~/.claude/skills/* -> ~/.agents/skills/* 심링크 (멀티툴 interop 표준, Codex/Gemini 공통 인식)
  - ~/.claude/shared/* -> ~/.agents/shared/* 심링크 (중립 정책 표면)
  - ~/.claude/registry/* -> ~/.agents/registry/* 심링크 (중립 정책 표면)
  - ~/.claude/scripts/llm-* -> ~/.agents/scripts/* 심링크 (중립 실행 표면)
  - ~/.claude/cache -> ~/.agents/cache 심링크 (로컬 런타임 상태 표면)
  - ~/.claude/workflows/* -> ~/.codex/workflows/*, ~/.gemini/workflows/* 심링크
  - ~/.claude/agents/* -> ~/.codex/agents/*, ~/.gemini/agents/* 심링크
  - ~/.claude/shared/* -> ~/.codex/shared/*, ~/.gemini/shared/* 심링크
  - ~/.claude/settings.json hooks -> ~/.codex/hooks.json, ~/.gemini/hooks.json
EOF
}

log() {
    if [[ "$QUIET" == "false" ]]; then
        echo "[sync-external] $*"
    fi
}

warn() {
    echo "[sync-external] $*" >&2
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

codex_silent_hook_command() {
    local command_line="$1"
    local adapter="$CLAUDE_DIR/hooks/codex-silent-json-adapter.sh"

    [[ -n "$command_line" ]] || return 0

    if [[ "$command_line" == *"$adapter"* ]]; then
        printf '%s\n' "$command_line"
        return 0
    fi

    printf '%s\n' "/bin/zsh $adapter -- $command_line"
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

list_markdown_sections() {
    local source_file="$1"

    awk '
        /^## / {
            title = $0
            sub(/^## /, "", title)
            print title
        }
    ' "$source_file"
}

section_excluded_for_target() {
    local target="$1"
    local section_title="$2"

    [[ "$target" == "gemini" ]] || return 1

    # 정확 매칭(prefix) — Claude 전용 라우팅/워크플로우 규칙은 Gemini에서 제외.
    # `워크플로우 자동화`처럼 Gemini도 알아야 할 hook 동작 섹션은 제외하지 않는다.
    case "$section_title" in
        트리거*|파이프라인*|"작업 타입"*|백로그*|"코드/문서"*|"에이전트 한글"*|"워크플로우 문서"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
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

이 파일은 \`$claude_file\` 를 기준으로 \`sync-external\`이 최초 생성한다.
프로젝트별 Claude 규칙은 유지하고, Codex에서 바로 쓰기 위한 호환 규칙만 상단에 덧붙인다.

## Codex Compatibility

- 현재 프로젝트: \`$project_name\`
- 전역 역할 호출 규칙은 \`~/.codex/AGENTS.md\`를 따른다.
- 아래 원본 프로젝트 규칙과 전역 규칙이 충돌하면 더 구체적인 프로젝트 규칙을 우선한다.
- 이 파일은 한 번만 생성한다. 이후 프로젝트별 수정은 직접 관리한다.

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

emit_external_llm_router_rules() {
    cat <<'EOF'
## LLM Router Centralization

외부 LLM 호출은 중립 표면인 `~/.agents`의 공통 라우터를 기준으로 한다. `~/.claude`는 설정 저장소 checkout이자 구현 원본이고, Codex/Gemini/Antigravity/공용 스킬은 `~/.agents`를 바라본다.

- 중앙 표면: `~/.agents`
- 정책 정본: `~/.agents/registry/llm-routing.json`
- task 라우터: `~/.agents/scripts/llm-router.sh`
- provider 어댑터: `~/.agents/scripts/llm-call.sh`
- handoff: `~/.agents/cache/llm-handoff/current.json`
- health: `~/.agents/cache/llm-provider-health.json`
- 공용 스킬: `~/.agents/skills/*`
- 구현 원본: `~/.claude` git checkout

### 호출 규칙

- task-level 위임은 `llm-router.sh`를 사용한다.
- provider-specific 스킬도 직접 CLI 대신 `llm-router.sh --provider ...`를 사용한다.
- `codex exec`, `agy`, `gemini`, `ini`, Ollama `curl` 직접 호출은 `llm-call.sh`/전용 wrapper 내부에서만 허용한다.
- 예외는 라우터/어댑터 자체를 디버깅하거나 수동 복구하는 경우뿐이며, 그 경우 결과에 예외 사유를 명시한다.
- 민감/로컬-only 질의는 반드시 `private --provider gemma`를 사용한다. 외부 provider fallback을 임의로 열지 않는다.

### 표준 명령

```bash
# provider health / route health
~/.agents/scripts/llm-router.sh doctor
~/.agents/scripts/llm-router.sh route-health

# broad scan: Gemini -> Codex -> Gemma fallback
~/.agents/scripts/llm-router.sh scan --caller manual --prompt "영향 범위 분석"

# implementation handoff: Codex -> Gemini fallback
~/.agents/scripts/llm-router.sh implement --caller manual --prompt "패치 초안 작성"

# multi-provider review
~/.agents/scripts/llm-router.sh review --caller manual --prompt "현재 diff 리뷰"

# local-only/private
~/.agents/scripts/llm-router.sh private --caller manual --provider gemma --prompt "민감한 로컬 검토"

# provider-specific, still centralized
~/.agents/scripts/llm-router.sh scan --caller ask-gemini --provider gemini --prompt "$QUESTION"
~/.agents/scripts/llm-router.sh implement --caller ask-codex --provider codex --prompt "$QUESTION"
~/.agents/scripts/llm-router.sh private --caller ask-ollama --provider gemma --model qwen3.5:9b --prompt "$QUESTION"
```

EOF
}

build_global_agents_file() {
    local target="$1"
    local target_file="$2"
    local section_title
    local section_text

    {
        if [[ "$target" == "codex" ]]; then
            cat <<'EOF'
# Codex CLI Instructions

이 파일은 `~/.claude/CLAUDE.md`를 기준으로 `sync-external`이 갱신한다.
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

- Codex가 작업을 시작한 세션에서는 Codex가 구현/검증/최종 응답의 작업 소유자다.
- Claude Code는 같은 워크트리를 직접 수정하는 두 번째 작업자가 아니라 read-only 판단 보조자/리뷰어/오케스트레이터로 병행한다.
- `claude 같이`, `claude도`, `둘 다`, `하이브리드`, `hybrid` 또는 아키텍처/설계/API/DB/auth 변경처럼 판단 비용이 큰 요청에서는 `~/.codex/workflows/codex.md`의 "Codex 주도 + Claude Code 병행 워크플로우"를 적용한다.
- Codex의 `UserPromptSubmit` 훅이 필요 시 Gemini와 Claude 보조 실행을 백그라운드로 시작할 수 있다.
- 생성되는 보조 컨텍스트:
  - `~/.agents/cache/gemini/{project}-scan.md`
  - `~/.agents/cache/gemini/{project}-review-prescan.md`
  - `~/.agents/cache/claude/{project}-codex-brief.md`
- Workspace 프로젝트에서 작업할 때 위 파일이 있고 최근 생성되었다면 먼저 읽고 참고한다.
- 기본 fresh 기준:
  - 프로젝트 스캔: 30분
  - 리뷰 프리스캔: 10분
  - Claude brief: 15분
- 이 보조 출력은 참고 자료다. 프로젝트 실제 코드와 규칙이 더 우선한다.
- Claude brief와 Codex 판단이 충돌하면 파일 읽기, 테스트, git diff로 검증하고 추정으로 채택하지 않는다.
- 같은 워크트리에 Codex와 Claude Code가 동시에 write하지 않는다. 병렬 구현이 필요하면 worktree를 분리한다.

EOF
            emit_external_llm_router_rules
            cat <<'EOF'
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
- 전역 `~/.claude/agents/*.md` 또는 현재 프로젝트 `.claude/agents/*.md`의 파일명 자체를 역할명으로 써도 된다.
- 매핑에 없는 에이전트도 경로를 직접 지정하면 된다.

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
        elif [[ "$target" == "gemini" ]]; then
            cat <<'EOF'
# Antigravity 글로벌 규칙

이 파일은 `~/.claude/CLAUDE.md`를 기준으로 `sync-external`이 갱신한다.
Claude 전용 파이프라인과 검색 우선순위는 제외하고 Antigravity/Gemini에서 바로 적용 가능한 규칙만 유지한다.

## 역할

Antigravity의 Gemini 에이전트는 병렬 구현 담당이다.
깊은 추론, 최종 리뷰, 의사결정, 사용자 응답 정리는 Claude Code가 처리한다.

- 출력은 한글
- 커밋 메시지는 한글
- Co-Authored-By 포함하지 않음
- `~/.claude`를 소스 오브 트루스로 둔다.
- `~/.claude/agents/*.md`, `~/.claude/workflows/*.md`, `~/.claude/skills/*`는 필요 시 참조한다.
- 병렬 구현 중 판단이 갈리면 임의 확정하지 말고 Claude Code의 결정을 기다린다.
- 프로젝트 내부 규칙이 전역 규칙보다 구체적이면 프로젝트 규칙을 우선한다.

EOF
            emit_external_llm_router_rules
        else
            warn "알 수 없는 글로벌 대상: $target"
            return 1
        fi

        while IFS= read -r section_title; do
            [[ -n "$section_title" ]] || continue

            if section_excluded_for_target "$target" "$section_title"; then
                continue
            fi

            section_text="$(extract_markdown_section "$CLAUDE_GLOBAL_FILE" "$section_title")"
            if [[ -n "$section_text" ]]; then
                printf '%s\n\n' "$section_text"
            fi
        done < <(list_markdown_sections "$CLAUDE_GLOBAL_FILE")
    } > "$target_file"
}

hook_command_for_target() {
    local target="$1"
    local command_line="$2"
    local rewritten
    local converted_command
    local basename_part
    local dirname_part
    local gemini_candidate

    [[ -n "$command_line" ]] || return 0

    if [[ "$target" == "codex" ]]; then
        # Codex hook runner is stricter than Claude Code:
        # - any stdout is parsed as event JSON
        # - run imported Claude hooks through a silent side-effect adapter
        # - avoid literal $HOME expansion drift
        # - run shell hooks through an explicit zsh interpreter
        rewritten="${command_line//\$HOME\/.claude\/hooks\//$CLAUDE_DIR/hooks/}"
        if [[ "$rewritten" == $CLAUDE_DIR/hooks/*.sh && "$rewritten" != /bin/zsh* ]]; then
            converted_command="/bin/zsh $rewritten"
        else
            converted_command="$rewritten"
        fi
        codex_silent_hook_command "$converted_command"
        return 0
    fi

    if [[ "$target" != "gemini" ]]; then
        printf '%s\n' "$command_line"
        return 0
    fi

    if [[ "$command_line" == *codex-* ]]; then
        rewritten="${command_line//codex-/gemini-}"

        if [[ "$rewritten" == "$command_line" ]]; then
            return 0
        fi

        basename_part="$(basename "$rewritten" 2>/dev/null || true)"
        dirname_part="$(dirname "$rewritten" 2>/dev/null || true)"
        gemini_candidate="$dirname_part/$basename_part"

        if [[ -f "$gemini_candidate" ]]; then
            printf '%s\n' "$rewritten"
        fi

        return 0
    fi

    printf '%s\n' "$command_line"
}

append_hook_command() {
    local target="$1"
    local target_file="$2"
    local command_line="$3"
    local converted_command

    converted_command="$(hook_command_for_target "$target" "$command_line")"
    [[ -n "$converted_command" ]] || return 0

    append_unique_line "$target_file" "$converted_command"
}

append_settings_event_commands() {
    local target="$1"
    local event_name="$2"
    local target_file="$3"
    local command_line

    [[ -f "$CLAUDE_SETTINGS_FILE" ]] || return 0

    while IFS= read -r command_line; do
        append_hook_command "$target" "$target_file" "$command_line"
    done < <(jq -r --arg event "$event_name" '.hooks[$event][]?.hooks[]?.command // empty' "$CLAUDE_SETTINGS_FILE" 2>/dev/null)
}

build_external_hooks_file() {
    local target="$1"
    local target_file="$2"
    local session_commands_file="$TEMP_DIR/${target}-session-hooks.txt"
    local prompt_commands_file="$TEMP_DIR/${target}-prompt-hooks.txt"
    local stop_commands_file="$TEMP_DIR/${target}-stop-hooks.txt"
    local session_json
    local prompt_json
    local stop_json

    : > "$session_commands_file"
    : > "$prompt_commands_file"
    : > "$stop_commands_file"

    append_hook_command "$target" "$session_commands_file" "$SYNC_SCRIPT_FILE --quiet"

    append_settings_event_commands "$target" "SessionStart" "$session_commands_file"
    append_settings_event_commands "$target" "UserPromptSubmit" "$prompt_commands_file"
    append_settings_event_commands "$target" "Stop" "$stop_commands_file"

    if [[ "$target" == "codex" ]]; then
        if [[ -f "$CLAUDE_DIR/hooks/codex-session-notify.sh" ]]; then
            append_hook_command "$target" "$session_commands_file" "$CLAUDE_DIR/hooks/codex-session-notify.sh"
        fi

        if [[ -f "$CLAUDE_DIR/hooks/codex-prompt-notify.sh" ]]; then
            append_hook_command "$target" "$prompt_commands_file" "$CLAUDE_DIR/hooks/codex-prompt-notify.sh"
        fi

        if [[ -f "$CLAUDE_DIR/hooks/codex-hybrid-orchestrator.sh" ]]; then
            append_hook_command "$target" "$prompt_commands_file" "/bin/zsh $CLAUDE_DIR/hooks/codex-hybrid-orchestrator.sh"
        fi
    fi

    if [[ "$target" == "gemini" ]]; then
        if [[ -f "$CLAUDE_DIR/hooks/gemini-session-notify.sh" ]]; then
            append_hook_command "$target" "$session_commands_file" "$CLAUDE_DIR/hooks/gemini-session-notify.sh"
        fi

        if [[ -f "$CLAUDE_DIR/hooks/gemini-prompt-notify.sh" ]]; then
            append_hook_command "$target" "$prompt_commands_file" "$CLAUDE_DIR/hooks/gemini-prompt-notify.sh"
        fi

        if [[ -f "$CLAUDE_DIR/hooks/gemini-hybrid-orchestrator.sh" ]]; then
            append_hook_command "$target" "$prompt_commands_file" "/bin/zsh $CLAUDE_DIR/hooks/gemini-hybrid-orchestrator.sh"
        fi
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
    local target="$1"
    local generated_file
    local destination_file

    generated_file="$TEMP_DIR/${target}-global.md"

    case "$target" in
        codex)
            destination_file="$CODEX_AGENTS_FILE"
            ;;
        gemini)
            destination_file="$GEMINI_AGENTS_FILE"
            ;;
        *)
            warn "알 수 없는 글로벌 대상: $target"
            return 1
            ;;
    esac

    build_global_agents_file "$target" "$generated_file"

    if sync_generated_file "$generated_file" "$destination_file"; then
        if [[ "$target" == "codex" ]]; then
            GLOBAL_CODEX_CHANGED=1
            log "Codex 글로벌 AGENTS.md 갱신"
        else
            GLOBAL_GEMINI_CHANGED=1
            log "Gemini 글로벌 GEMINI.md 갱신"
        fi
    else
        if [[ "$target" == "codex" ]]; then
            GLOBAL_CODEX_CHANGED=0
            log "Codex 글로벌 AGENTS.md 최신 상태"
        else
            GLOBAL_GEMINI_CHANGED=0
            log "Gemini 글로벌 GEMINI.md 최신 상태"
        fi
    fi
}

sync_workspace_agents() {
    local project_dir
    local claude_file
    local agents_file
    local generated_file

    PROJECTS_UPDATED=0
    PROJECTS_CREATED=0
    PROJECTS_SKIPPED=0
    PROJECTS_SCANNED=0

    while IFS=$'\t' read -r project_dir claude_file; do
        [[ -n "$project_dir" ]] || continue
        [[ -n "$claude_file" ]] || continue

        agents_file="$project_dir/AGENTS.md"
        generated_file="$TEMP_DIR/$(basename "$project_dir").AGENTS.md"
        PROJECTS_SCANNED=$((PROJECTS_SCANNED + 1))

        if [[ -e "$agents_file" ]]; then
            PROJECTS_SKIPPED=$((PROJECTS_SKIPPED + 1))
            continue
        fi

        build_project_agents_file "$project_dir" "$claude_file" "$generated_file"
        run_copy "$generated_file" "$agents_file"

        PROJECTS_CREATED=$((PROJECTS_CREATED + 1))
        log "$(basename "$project_dir")/AGENTS.md 생성"
    done < <(list_workspace_project_sources)
}

sync_symlink_dir() {
    local source_dir="$1"
    local target_dir="$2"
    local require_skill_file="$3"
    local total_var="$4"
    local linked_var="$5"
    local available_var="$6"
    local source_path
    local entry_name
    local target_path
    local total=0
    local linked=0
    local available=0

    mkdir -p "$target_dir"

    for source_path in "$source_dir"/*; do
        [[ -e "$source_path" ]] || continue
        [[ -d "$source_path" || -f "$source_path" ]] || continue

        if [[ "$require_skill_file" == "true" ]]; then
            [[ -d "$source_path" ]] || continue
            [[ -f "$source_path/SKILL.md" || -f "$source_path/skill.md" ]] || continue
        fi

        entry_name="$(basename "$source_path")"
        target_path="$target_dir/$entry_name"
        total=$((total + 1))

        if [[ -L "$target_path" ]] && [[ ! -e "$target_path" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[dry-run] rm $target_path"
            else
                rm "$target_path"
            fi
        fi

        if [[ -e "$target_path" || -L "$target_path" ]]; then
            available=$((available + 1))
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] ln -s $source_path $target_path"
        else
            ln -s "$source_path" "$target_path"
        fi

        linked=$((linked + 1))
        available=$((available + 1))
    done

    printf -v "$total_var" '%s' "$total"
    printf -v "$linked_var" '%s' "$linked"
    printf -v "$available_var" '%s' "$available"
}

sync_skills() {
    sync_symlink_dir "$CLAUDE_SKILLS_DIR" "$AGENTS_SKILLS_DIR" "true" \
        AGENTS_SKILLS_TOTAL AGENTS_SKILLS_LINKED AGENTS_SKILLS_AVAILABLE
    log "Agent 스킬 링크 (.agents/skills 멀티툴 표준): 신규 ${AGENTS_SKILLS_LINKED}개 / 사용 가능 ${AGENTS_SKILLS_AVAILABLE}/${AGENTS_SKILLS_TOTAL}"
}

sync_file_links() {
    local source_dir="$1"
    local target_dir="$2"
    local total_var="$3"
    local linked_var="$4"
    local available_var="$5"
    shift 5

    local entry_name
    local source_path
    local target_path
    local total=0
    local linked=0
    local available=0

    mkdir -p "$target_dir"

    for entry_name in "$@"; do
        source_path="$source_dir/$entry_name"
        target_path="$target_dir/$entry_name"
        [[ -e "$source_path" ]] || continue

        total=$((total + 1))

        if [[ -L "$target_path" ]] && [[ ! -e "$target_path" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[dry-run] rm $target_path"
            else
                rm "$target_path"
            fi
        fi

        if [[ -e "$target_path" || -L "$target_path" ]]; then
            available=$((available + 1))
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] ln -s $source_path $target_path"
        else
            ln -s "$source_path" "$target_path"
        fi

        linked=$((linked + 1))
        available=$((available + 1))
    done

    printf -v "$total_var" '%s' "$total"
    printf -v "$linked_var" '%s' "$linked"
    printf -v "$available_var" '%s' "$available"
}

sync_single_symlink() {
    local source_path="$1"
    local target_path="$2"
    local label="$3"

    mkdir -p "$(dirname "$target_path")"

    if [[ -L "$target_path" ]]; then
        if [[ "$(readlink "$target_path")" == "$source_path" ]]; then
            log "$label 링크 최신: $target_path"
            return 0
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] rm $target_path"
        else
            rm "$target_path"
        fi
    elif [[ -e "$target_path" ]]; then
        warn "$label 링크 건너뜀: $target_path already exists and is not a symlink"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] ln -s $source_path $target_path"
    else
        ln -s "$source_path" "$target_path"
    fi
    log "$label 링크 생성: $target_path -> $source_path"
}

sync_agents_control_plane() {
    sync_symlink_dir "$CLAUDE_SHARED_DIR" "$AGENTS_SHARED_DIR" "false" \
        AGENTS_SHARED_TOTAL AGENTS_SHARED_LINKED AGENTS_SHARED_AVAILABLE
    log "Agent shared 링크: 신규 ${AGENTS_SHARED_LINKED}개 / 사용 가능 ${AGENTS_SHARED_AVAILABLE}/${AGENTS_SHARED_TOTAL}"

    sync_symlink_dir "$CLAUDE_DIR/registry" "$AGENTS_REGISTRY_DIR" "false" \
        AGENTS_REGISTRY_TOTAL AGENTS_REGISTRY_LINKED AGENTS_REGISTRY_AVAILABLE
    log "Agent registry 링크: 신규 ${AGENTS_REGISTRY_LINKED}개 / 사용 가능 ${AGENTS_REGISTRY_AVAILABLE}/${AGENTS_REGISTRY_TOTAL}"

    sync_file_links "$CLAUDE_DIR/scripts" "$AGENTS_SCRIPTS_DIR" \
        AGENTS_SCRIPTS_TOTAL AGENTS_SCRIPTS_LINKED AGENTS_SCRIPTS_AVAILABLE \
        llm-router.sh llm-router.py llm-call.sh gemini-wrapped.sh _lib_ini_call.py _nvm-path.sh
    log "Agent scripts 링크: 신규 ${AGENTS_SCRIPTS_LINKED}개 / 사용 가능 ${AGENTS_SCRIPTS_AVAILABLE}/${AGENTS_SCRIPTS_TOTAL}"

    sync_single_symlink "$CLAUDE_DIR/cache" "$AGENTS_CACHE_LINK" "Agent cache"
}

sync_workflows() {
    local target="$1"

    case "$target" in
        codex)
            sync_symlink_dir "$CLAUDE_WORKFLOWS_DIR" "$CODEX_WORKFLOWS_DIR" "false" \
                CODEX_WORKFLOWS_TOTAL CODEX_WORKFLOWS_LINKED CODEX_WORKFLOWS_AVAILABLE
            log "Codex workflows 링크: 신규 ${CODEX_WORKFLOWS_LINKED}개 / 사용 가능 ${CODEX_WORKFLOWS_AVAILABLE}/${CODEX_WORKFLOWS_TOTAL}"
            ;;
        gemini)
            sync_symlink_dir "$CLAUDE_WORKFLOWS_DIR" "$GEMINI_WORKFLOWS_DIR" "false" \
                GEMINI_WORKFLOWS_TOTAL GEMINI_WORKFLOWS_LINKED GEMINI_WORKFLOWS_AVAILABLE
            log "Gemini workflows 링크: 신규 ${GEMINI_WORKFLOWS_LINKED}개 / 사용 가능 ${GEMINI_WORKFLOWS_AVAILABLE}/${GEMINI_WORKFLOWS_TOTAL}"
            ;;
        *)
            warn "알 수 없는 workflows 대상: $target"
            return 1
            ;;
    esac
}

sync_agents_dir() {
    local target="$1"

    case "$target" in
        codex)
            sync_symlink_dir "$CLAUDE_AGENTS_DIR" "$CODEX_AGENTS_DIR" "false" \
                CODEX_AGENTS_TOTAL CODEX_AGENTS_LINKED CODEX_AGENTS_AVAILABLE
            log "Codex agents 링크: 신규 ${CODEX_AGENTS_LINKED}개 / 사용 가능 ${CODEX_AGENTS_AVAILABLE}/${CODEX_AGENTS_TOTAL}"
            ;;
        gemini)
            sync_symlink_dir "$CLAUDE_AGENTS_DIR" "$GEMINI_AGENTS_DIR" "false" \
                GEMINI_AGENTS_TOTAL GEMINI_AGENTS_LINKED GEMINI_AGENTS_AVAILABLE
            log "Gemini agents 링크: 신규 ${GEMINI_AGENTS_LINKED}개 / 사용 가능 ${GEMINI_AGENTS_AVAILABLE}/${GEMINI_AGENTS_TOTAL}"
            ;;
        *)
            warn "알 수 없는 agents 대상: $target"
            return 1
            ;;
    esac
}

sync_shared_dir() {
    local target="$1"

    case "$target" in
        codex)
            sync_symlink_dir "$CLAUDE_SHARED_DIR" "$CODEX_SHARED_DIR" "false" \
                CODEX_SHARED_TOTAL CODEX_SHARED_LINKED CODEX_SHARED_AVAILABLE
            log "Codex shared 링크: 신규 ${CODEX_SHARED_LINKED}개 / 사용 가능 ${CODEX_SHARED_AVAILABLE}/${CODEX_SHARED_TOTAL}"
            ;;
        gemini)
            sync_symlink_dir "$CLAUDE_SHARED_DIR" "$GEMINI_SHARED_DIR" "false" \
                GEMINI_SHARED_TOTAL GEMINI_SHARED_LINKED GEMINI_SHARED_AVAILABLE
            log "Gemini shared 링크: 신규 ${GEMINI_SHARED_LINKED}개 / 사용 가능 ${GEMINI_SHARED_AVAILABLE}/${GEMINI_SHARED_TOTAL}"
            ;;
        *)
            warn "알 수 없는 shared 대상: $target"
            return 1
            ;;
    esac
}

sync_hooks() {
    local target="$1"
    local generated_file
    local destination_file

    generated_file="$TEMP_DIR/${target}-hooks.json"

    case "$target" in
        codex)
            destination_file="$CODEX_HOOKS_FILE"
            ;;
        gemini)
            destination_file="$GEMINI_HOOKS_FILE"
            ;;
        *)
            warn "알 수 없는 hooks 대상: $target"
            return 1
            ;;
    esac

    build_external_hooks_file "$target" "$generated_file"

    if sync_generated_file "$generated_file" "$destination_file"; then
        if [[ "$target" == "codex" ]]; then
            CODEX_HOOKS_CHANGED=1
            log "Codex hooks.json 갱신"
        else
            GEMINI_HOOKS_CHANGED=1
            log "Gemini hooks.json 갱신"
        fi
    else
        if [[ "$target" == "codex" ]]; then
            CODEX_HOOKS_CHANGED=0
            log "Codex hooks.json 최신 상태"
        else
            GEMINI_HOOKS_CHANGED=0
            log "Gemini hooks.json 최신 상태"
        fi
    fi
}

repair_codex_project_moai_hooks() {
    local workspace_dir="$HOME/Workspace"
    local hooks_file
    local generated_file

    [[ -d "$workspace_dir" ]] || return 0

    while IFS= read -r hooks_file; do
        [[ -f "$hooks_file" ]] || continue
        generated_file="$TEMP_DIR/$(echo "$hooks_file" | tr '/ ' '__').json"

        if ! jq --arg prefix "/bin/zsh $CLAUDE_DIR/hooks/codex-silent-json-adapter.sh -- /bin/bash " '
            def unquote:
                if startswith("'") and endswith("'") then .[1:-1] else . end;
            def wrap_moai:
                if type == "string"
                    and (contains("codex-silent-json-adapter.sh") | not)
                    and ((unquote) | test("^/.+/.codex/hooks/moai/handle-[^/]+\\.sh$"))
                then $prefix + (unquote)
                else .
                end;

            (.. | objects | select(has("command")).command) |= wrap_moai
        ' "$hooks_file" > "$generated_file"; then
            warn "Codex 프로젝트 MoAI 훅 보정 실패: $hooks_file"
            continue
        fi

        sync_generated_file "$generated_file" "$hooks_file" >/dev/null || true
    done < <(find "$workspace_dir" -maxdepth 4 -path '*/.codex/hooks.json' -type f 2>/dev/null)
}

count_available_links() {
    local source_dir="$1"
    local target_dir="$2"
    local require_skill_file="$3"
    local source_path
    local total=0
    local available=0

    for source_path in "$source_dir"/*; do
        [[ -e "$source_path" ]] || continue
        [[ -d "$source_path" || -f "$source_path" ]] || continue

        if [[ "$require_skill_file" == "true" ]]; then
            [[ -d "$source_path" ]] || continue
            [[ -f "$source_path/SKILL.md" || -f "$source_path/skill.md" ]] || continue
        fi

        total=$((total + 1))

        if [[ -e "$target_dir/$(basename "$source_path")" || -L "$target_dir/$(basename "$source_path")" ]]; then
            available=$((available + 1))
        fi
    done

    printf '%s\t%s\n' "$available" "$total"
}

count_named_file_links() {
    local source_dir="$1"
    local target_dir="$2"
    shift 2

    local entry_name
    local total=0
    local available=0

    for entry_name in "$@"; do
        [[ -e "$source_dir/$entry_name" ]] || continue
        total=$((total + 1))
        if [[ -e "$target_dir/$entry_name" || -L "$target_dir/$entry_name" ]]; then
            available=$((available + 1))
        fi
    done

    printf '%s\t%s\n' "$available" "$total"
}

file_drift_status() {
    local generated_file="$1"
    local target_file="$2"

    if [[ ! -f "$target_file" ]]; then
        echo "미생성"
    elif cmp -s "$generated_file" "$target_file"; then
        echo "최신"
    else
        echo "드리프트"
    fi
}

# MCP sync: ~/.claude.json::mcpServers 를 SSOT로 읽어 Codex/Gemini에 단방향 등록.
# 제외 대상: codex-cli(자기참조), claude.ai 내장(Anthropic 인증 종속), Claude plugin
# (마켓플레이스 자동 등록은 각 도구가 별도 관리). 이미 있으면 skip (idempotent).
sync_mcp_servers() {
    local claude_json="${HOME}/.claude.json"
    local server_name
    local server_json
    local cmd
    local args_json
    local env_json
    local server_type
    local url
    local existing_codex
    local existing_gemini

    if [[ ! -f "$claude_json" ]]; then
        warn "MCP SSOT 없음: $claude_json — sync 건너뜀"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        warn "jq 필요 — MCP sync 건너뜀"
        return 0
    fi

    existing_codex="$(codex mcp list 2>/dev/null | awk 'NR>1 && /^[a-z]/{print $1}' | tr '\n' ' ')"
    # gemini mcp list 는 stderr 로 출력. 멀티바이트 ✓/✗ 우회: 콜론 앞 토큰 추출
    existing_gemini="$(gemini mcp list 2>&1 | LC_ALL=C grep -E '^[^[:space:]]+ [A-Za-z0-9_-]+:' | awk '{sub(/:$/,"",$2); print $2}' | tr '\n' ' ')"

    while IFS= read -r server_name; do
        [[ -n "$server_name" ]] || continue

        # 제외 규칙
        case "$server_name" in
            codex-cli|gitlab)
                # codex-cli: Codex에 등록하면 자기참조. Gemini에서도 의미 없음
                # gitlab: 인증 안 된 상태(! Needs auth) — 인증 설정은 사용자 수동
                log "MCP '$server_name' 제외 (자기참조 또는 인증 필요)"
                continue
                ;;
        esac

        server_json="$(jq -r --arg n "$server_name" '.mcpServers[$n]' "$claude_json")"
        server_type="$(echo "$server_json" | jq -r '.type // "stdio"')"
        cmd="$(echo "$server_json" | jq -r '.command // ""')"
        url="$(echo "$server_json" | jq -r '.url // ""')"

        # --- Codex 등록 ---
        if [[ " $existing_codex " == *" $server_name "* ]]; then
            log "Codex MCP '$server_name' 이미 등록됨 — skip"
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[dry-run] codex mcp add $server_name ..."
            else
                local codex_env_args=()
                while IFS=$'\t' read -r k v; do
                    [[ -n "$k" ]] || continue
                    codex_env_args+=("--env" "$k=$v")
                done < <(echo "$server_json" | jq -r '.env // {} | to_entries[] | "\(.key)\t\(.value)"')

                if [[ -n "$url" && "$url" != "null" ]]; then
                    codex mcp add "$server_name" --url "$url" >/dev/null 2>&1 \
                        && log "Codex MCP '$server_name' 등록 (HTTP)" \
                        || warn "Codex MCP '$server_name' 등록 실패"
                elif [[ -n "$cmd" && "$cmd" != "null" ]]; then
                    local args_array=()
                    while IFS= read -r a; do
                        [[ -n "$a" ]] || continue
                        args_array+=("$a")
                    done < <(echo "$server_json" | jq -r '.args // [] | .[]')

                    codex mcp add "$server_name" "${codex_env_args[@]}" -- "$cmd" "${args_array[@]}" >/dev/null 2>&1 \
                        && log "Codex MCP '$server_name' 등록 (stdio)" \
                        || warn "Codex MCP '$server_name' 등록 실패"
                fi
            fi
        fi

        # --- Gemini 등록 ---
        if [[ " $existing_gemini " == *" $server_name "* ]]; then
            log "Gemini MCP '$server_name' 이미 등록됨 — skip"
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "[dry-run] gemini mcp add $server_name ..."
            else
                local gemini_env_args=()
                while IFS=$'\t' read -r k v; do
                    [[ -n "$k" ]] || continue
                    gemini_env_args+=("-e" "$k=$v")
                done < <(echo "$server_json" | jq -r '.env // {} | to_entries[] | "\(.key)\t\(.value)"')

                if [[ -n "$url" && "$url" != "null" ]]; then
                    gemini mcp add -s user -t http "$server_name" "$url" >/dev/null 2>&1 \
                        && log "Gemini MCP '$server_name' 등록 (HTTP)" \
                        || warn "Gemini MCP '$server_name' 등록 실패"
                elif [[ -n "$cmd" && "$cmd" != "null" ]]; then
                    local gargs=()
                    while IFS= read -r a; do
                        [[ -n "$a" ]] || continue
                        gargs+=("$a")
                    done < <(echo "$server_json" | jq -r '.args // [] | .[]')

                    gemini mcp add -s user -t stdio "${gemini_env_args[@]}" "$server_name" "$cmd" "${gargs[@]}" >/dev/null 2>&1 \
                        && log "Gemini MCP '$server_name' 등록 (stdio)" \
                        || warn "Gemini MCP '$server_name' 등록 실패"
                fi
            fi
        fi

    done < <(jq -r '.mcpServers // {} | keys[]' "$claude_json")
}

print_status() {
    local generated_codex_file="$TEMP_DIR/status-codex-AGENTS.md"
    local generated_gemini_file="$TEMP_DIR/status-gemini-GEMINI.md"
    local generated_codex_hooks_file="$TEMP_DIR/status-codex-hooks.json"
    local generated_gemini_hooks_file="$TEMP_DIR/status-gemini-hooks.json"
    local codex_global_status
    local gemini_global_status
    local codex_hooks_status
    local gemini_hooks_status
    local count_line
    local available
    local total
    local project_dir
    local project_file
    local project_agents_file
    local unsupported_events

    build_global_agents_file "codex" "$generated_codex_file"
    build_global_agents_file "gemini" "$generated_gemini_file"
    build_external_hooks_file "codex" "$generated_codex_hooks_file"
    build_external_hooks_file "gemini" "$generated_gemini_hooks_file"

    codex_global_status="$(file_drift_status "$generated_codex_file" "$CODEX_AGENTS_FILE")"
    gemini_global_status="$(file_drift_status "$generated_gemini_file" "$GEMINI_AGENTS_FILE")"
    codex_hooks_status="$(file_drift_status "$generated_codex_hooks_file" "$CODEX_HOOKS_FILE")"
    gemini_hooks_status="$(file_drift_status "$generated_gemini_hooks_file" "$GEMINI_HOOKS_FILE")"

    echo "=== 외부 도구 동기화 상태 ==="
    echo ""
    echo "Codex 글로벌 AGENTS: $codex_global_status"
    echo "Gemini 글로벌 GEMINI: $gemini_global_status"
    echo "Codex hooks:         $codex_hooks_status"
    echo "Gemini hooks:        $gemini_hooks_status"
    echo ""

    count_line="$(count_available_links "$CLAUDE_SKILLS_DIR" "$AGENTS_SKILLS_DIR" "true")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Agent 스킬 (.agents): $available/$total 사용 가능"

    count_line="$(count_available_links "$CLAUDE_SHARED_DIR" "$AGENTS_SHARED_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Agent shared:        $available/$total 사용 가능"

    count_line="$(count_available_links "$CLAUDE_DIR/registry" "$AGENTS_REGISTRY_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Agent registry:      $available/$total 사용 가능"

    count_line="$(count_named_file_links "$CLAUDE_DIR/scripts" "$AGENTS_SCRIPTS_DIR" \
        llm-router.sh llm-router.py llm-call.sh gemini-wrapped.sh _lib_ini_call.py _nvm-path.sh)"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Agent scripts:       $available/$total 사용 가능"

    if [[ -L "$AGENTS_CACHE_LINK" && "$(readlink "$AGENTS_CACHE_LINK")" == "$CLAUDE_DIR/cache" ]]; then
        echo "Agent cache:         링크"
    else
        echo "Agent cache:         미연결"
    fi

    count_line="$(count_available_links "$CLAUDE_WORKFLOWS_DIR" "$CODEX_WORKFLOWS_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Codex workflows:     $available/$total 사용 가능"

    count_line="$(count_available_links "$CLAUDE_WORKFLOWS_DIR" "$GEMINI_WORKFLOWS_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Gemini workflows:    $available/$total 사용 가능"

    count_line="$(count_available_links "$CLAUDE_AGENTS_DIR" "$CODEX_AGENTS_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Codex agents:        $available/$total 사용 가능"

    count_line="$(count_available_links "$CLAUDE_AGENTS_DIR" "$GEMINI_AGENTS_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Gemini agents:       $available/$total 사용 가능"

    count_line="$(count_available_links "$CLAUDE_SHARED_DIR" "$CODEX_SHARED_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Codex shared:        $available/$total 사용 가능"

    count_line="$(count_available_links "$CLAUDE_SHARED_DIR" "$GEMINI_SHARED_DIR" "false")"
    available="${count_line%%$'\t'*}"
    total="${count_line##*$'\t'}"
    echo "Gemini shared:       $available/$total 사용 가능"

    echo ""
    echo "| 프로젝트 | AGENTS.md |"
    echo "|----------|-----------|"

    while IFS=$'\t' read -r project_dir project_file; do
        [[ -n "$project_dir" ]] || continue
        [[ -n "$project_file" ]] || continue

        project_agents_file="$project_dir/AGENTS.md"

        if [[ -f "$project_agents_file" ]]; then
            echo "| $(basename "$project_dir") | 존재 |"
        else
            echo "| $(basename "$project_dir") | 미생성 |"
        fi
    done < <(list_workspace_project_sources)

    unsupported_events="$(
        jq -r '.hooks | keys[]' "$CLAUDE_SETTINGS_FILE" 2>/dev/null \
            | grep -Ev '^(SessionStart|Stop|UserPromptSubmit)$' \
            || true
    )"

    echo ""
    echo "지원 외 Claude 훅 이벤트:"
    if [[ -n "$unsupported_events" ]]; then
        printf '%s\n' "$unsupported_events"
    else
        echo "없음"
    fi
}

parse_args() {
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
}

check_dependencies() {
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq가 필요합니다."
        exit 1
    fi
}

check_sources() {
    [[ -f "$CLAUDE_GLOBAL_FILE" ]] || {
        warn "글로벌 CLAUDE.md를 찾을 수 없습니다: $CLAUDE_GLOBAL_FILE"
        exit 1
    }

    [[ -f "$CLAUDE_SETTINGS_FILE" ]] || {
        warn "settings.json을 찾을 수 없습니다: $CLAUDE_SETTINGS_FILE"
        exit 1
    }
}

prepare_temp_dir() {
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sync-external.XXXXXX")"
    trap 'rm -rf "$TEMP_DIR"' EXIT
}

print_summary() {
    [[ "$QUIET" == "false" ]] || return 0

    echo ""
    echo "=== 동기화 완료 ==="
    echo "Codex 글로벌 AGENTS: $([[ "$GLOBAL_CODEX_CHANGED" -eq 1 ]] && echo "갱신" || echo "최신")"
    echo "Gemini 글로벌 GEMINI: $([[ "$GLOBAL_GEMINI_CHANGED" -eq 1 ]] && echo "갱신" || echo "최신")"
    echo "프로젝트 AGENTS: ${PROJECTS_CREATED}개 생성 / ${PROJECTS_SKIPPED}개 기존 / ${PROJECTS_SCANNED}개 확인"
    echo "Agent 스킬 (.agents/skills): ${AGENTS_SKILLS_AVAILABLE}/${AGENTS_SKILLS_TOTAL} 사용 가능 (신규 링크 ${AGENTS_SKILLS_LINKED}개)"
    echo "Agent shared: ${AGENTS_SHARED_AVAILABLE}/${AGENTS_SHARED_TOTAL} 사용 가능 (신규 링크 ${AGENTS_SHARED_LINKED}개)"
    echo "Agent registry: ${AGENTS_REGISTRY_AVAILABLE}/${AGENTS_REGISTRY_TOTAL} 사용 가능 (신규 링크 ${AGENTS_REGISTRY_LINKED}개)"
    echo "Agent scripts: ${AGENTS_SCRIPTS_AVAILABLE}/${AGENTS_SCRIPTS_TOTAL} 사용 가능 (신규 링크 ${AGENTS_SCRIPTS_LINKED}개)"
    echo "Codex workflows: ${CODEX_WORKFLOWS_AVAILABLE}/${CODEX_WORKFLOWS_TOTAL} 사용 가능 (신규 링크 ${CODEX_WORKFLOWS_LINKED}개)"
    echo "Gemini workflows: ${GEMINI_WORKFLOWS_AVAILABLE}/${GEMINI_WORKFLOWS_TOTAL} 사용 가능 (신규 링크 ${GEMINI_WORKFLOWS_LINKED}개)"
    echo "Codex agents: ${CODEX_AGENTS_AVAILABLE}/${CODEX_AGENTS_TOTAL} 사용 가능 (신규 링크 ${CODEX_AGENTS_LINKED}개)"
    echo "Gemini agents: ${GEMINI_AGENTS_AVAILABLE}/${GEMINI_AGENTS_TOTAL} 사용 가능 (신규 링크 ${GEMINI_AGENTS_LINKED}개)"
    echo "Codex shared: ${CODEX_SHARED_AVAILABLE}/${CODEX_SHARED_TOTAL} 사용 가능 (신규 링크 ${CODEX_SHARED_LINKED}개)"
    echo "Gemini shared: ${GEMINI_SHARED_AVAILABLE}/${GEMINI_SHARED_TOTAL} 사용 가능 (신규 링크 ${GEMINI_SHARED_LINKED}개)"
    echo "Codex hooks: $([[ "$CODEX_HOOKS_CHANGED" -eq 1 ]] && echo "갱신" || echo "최신")"
    echo "Gemini hooks: $([[ "$GEMINI_HOOKS_CHANGED" -eq 1 ]] && echo "갱신" || echo "최신")"
    echo ""
    echo "다시 실행:"
    echo "  ~/.claude/scripts/sync-external.sh"
    echo "  ~/.claude/scripts/sync-external.sh status"
    echo "  ~/.claude/scripts/sync-external.sh --dry-run"
}

schedule_regression_check() {
    [[ "$DRY_RUN" == "false" ]] || return 0
    [[ -x "$CLAUDE_DIR/scripts/moai-regression-check.py" ]] || return 0
    nohup "$CLAUDE_DIR/scripts/moai-regression-check.py" --quiet --live >/dev/null 2>&1 &
}

main() {
    parse_args "$@"
    check_dependencies
    check_sources
    prepare_temp_dir

    if [[ "$MODE" == "status" ]]; then
        print_status
        exit 0
    fi

    log "1/10 Codex 글로벌 AGENTS.md 동기화"
    sync_global_agents "codex"

    log "2/10 Gemini 글로벌 GEMINI.md 동기화"
    sync_global_agents "gemini"

    log "3/10 프로젝트 AGENTS.md 동기화"
    sync_workspace_agents

    log "4/10 스킬 심링크 동기화 (.agents/skills 멀티툴 표준)"
    sync_skills

    log "5/10 Agent 중앙 표면 동기화"
    sync_agents_control_plane

    log "6/10 Workflows 심링크 동기화"
    sync_workflows "codex"
    sync_workflows "gemini"

    log "7/10 Agents 디렉토리 심링크 동기화"
    sync_agents_dir "codex"
    sync_agents_dir "gemini"

    log "8/10 Shared 디렉토리 심링크 동기화"
    sync_shared_dir "codex"
    sync_shared_dir "gemini"

    log "9/10 Hooks 동기화"
    sync_hooks "codex"
    sync_hooks "gemini"
    repair_codex_project_moai_hooks

    log "10/10 MCP 서버 등록 동기화 (Claude → Codex/Gemini 단방향)"
    sync_mcp_servers

    schedule_regression_check
    print_summary
}

main "$@"
