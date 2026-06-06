#!/usr/bin/env bash
#
# addon.sh — Claude Code 애드온 매니저
#
# codex / agy / moai 를 "애드온처럼 붙였다 뗐다" 토글한다.
# 핵심 목표: moai 를 codex/agy 와 섞지 않고 격리해서,
#            나중에 moai 만 안전하게(원본 무손상) 걷어낼 수 있게 한다.
#
# 사용법:
#   addon.sh status                 # 3개 애드온 현황 + 어디 박혔는지
#   addon.sh agy   on|off           # GEMINI_CLI env + PATH 토글
#   addon.sh codex on|off           # codex 플러그인 enable 토글
#   addon.sh moai  on|off           # moai 바이너리 비활성/복원 (가역)
#   addon.sh moai  purge [--apply]  # moai 흔적 완전 제거 (기본 dry-run)
#
# 안전 원칙:
#   - settings.json 은 python 으로 파싱 후 백업 떠서 수정 (수기 sed 금지)
#   - moai purge 는 "# MoAI Execution Directive" 마커 있는 CLAUDE.md 만 대상
#   - git 에 원본이 있으면 삭제 대신 `git restore` 로 원본 복구
#   - 마커 없는 원본 CLAUDE.md 는 절대 건드리지 않음
#   - --apply 없으면 무조건 dry-run (무엇을 할지 보여주기만)

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
WORKSPACE="$HOME/Workspace"
LOCAL_BIN="$HOME/.local/bin"
MOAI_BIN="$LOCAL_BIN/moai"
MOAI_MARKER="# MoAI Execution Directive"

c_g="\033[32m"; c_y="\033[33m"; c_r="\033[31m"; c_b="\033[34m"; c_d="\033[2m"; c_0="\033[0m"

die() { echo -e "${c_r}오류: $*${c_0}" >&2; exit 1; }
[ -f "$SETTINGS" ] || die "settings.json 없음: $SETTINGS"

backup_settings() {
    local ts bak
    ts=$(python3 -c "import datetime;print(datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))")
    bak="$SETTINGS.bak-$ts"
    cp "$SETTINGS" "$bak"
    echo -e "  ${c_d}백업: $bak${c_0}"
}

# settings.json 의 한 값을 안전하게 읽기 (python)
settings_get() {
    python3 - "$1" <<'PY'
import json,sys
d=json.load(open(sys.argv[0] if False else "/Users/leonard/.claude/settings.json"))
path=sys.argv[1].split('.')
cur=d
for k in path:
    cur=cur.get(k) if isinstance(cur,dict) else None
    if cur is None: break
print(cur if cur is not None else "")
PY
}

# ── 현황 ──────────────────────────────────────────────
cmd_status() {
    echo -e "${c_b}=== Claude Code 애드온 현황 ===${c_0}\n"

    # agy
    local gcli path_has
    gcli=$(python3 -c "import json;print(json.load(open('$SETTINGS'))['env'].get('GEMINI_CLI',''))")
    path_has=$(python3 -c "import json;print('$LOCAL_BIN' in json.load(open('$SETTINGS'))['env'].get('PATH',''))")
    if [ "$gcli" = "agy" ]; then
        echo -e "  ${c_g}● agy   ON${c_0}   GEMINI_CLI=agy"
        if [ "$path_has" = "True" ]; then
            echo -e "         ${c_d}PATH 에 ~/.local/bin 포함 → 'agy' 직접 호출 가능${c_0}"
        else
            echo -e "         ${c_y}⚠ PATH 에 ~/.local/bin 없음 → which agy 실패 (절대경로만 됨)${c_0}"
            echo -e "         ${c_d}'addon agy on' 으로 PATH 고침${c_0}"
        fi
    else
        echo -e "  ${c_d}○ agy   OFF  GEMINI_CLI=${gcli:-unset}${c_0}"
    fi

    # codex
    local codex_en
    codex_en=$(python3 -c "import json;print(json.load(open('$SETTINGS')).get('enabledPlugins',{}).get('codex@openai-codex',False))")
    if [ "$codex_en" = "True" ]; then
        echo -e "  ${c_g}● codex ON${c_0}   enabledPlugins[codex@openai-codex]=true"
    else
        echo -e "  ${c_d}○ codex OFF${c_0}"
    fi

    # moai
    if [ -x "$MOAI_BIN" ]; then
        local ver; ver=$("$MOAI_BIN" --version 2>/dev/null | head -1 || echo "?")
        echo -e "  ${c_g}● moai  ON${c_0}   $MOAI_BIN ($ver)"
    elif [ -f "$MOAI_BIN.disabled" ]; then
        echo -e "  ${c_y}◐ moai  비활성${c_0} (바이너리 .disabled — 'addon moai on' 복원)"
    else
        echo -e "  ${c_d}○ moai  없음${c_0}"
    fi

    # moai 침습 범위 요약
    local n_moai n_proj
    n_moai=$(grep -rl "^$MOAI_MARKER" "$WORKSPACE"/*/CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')
    n_proj=$(find "$WORKSPACE" -maxdepth 2 -name ".moai" -type d 2>/dev/null | wc -l | tr -d ' ')
    echo -e "\n  ${c_d}moai 침습: CLAUDE.md ${n_moai}개 점령 · .moai 디렉토리 ${n_proj}개 프로젝트${c_0}"
    echo -e "  ${c_d}제거: 'addon moai purge' (dry-run) → 'addon moai purge --apply'${c_0}"
}

# ── agy ───────────────────────────────────────────────
cmd_agy() {
    case "${1:-}" in
        on)
            backup_settings
            python3 - <<PY
import json
p="$SETTINGS"; d=json.load(open(p))
env=d.setdefault("env",{})
env["GEMINI_CLI"]="agy"
parts=env.get("PATH","").split(":")
if "$LOCAL_BIN" not in parts:
    parts.insert(0,"$LOCAL_BIN")          # 맨 앞에 추가 → agy/moai/ini 직접 호출
    env["PATH"]=":".join(p for p in parts if p)
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
print("  GEMINI_CLI=agy + PATH 에 ~/.local/bin 추가")
PY
            echo -e "  ${c_g}agy ON${c_0} — 새 세션부터 'agy' 직접 호출 가능"
            ;;
        off)
            backup_settings
            python3 - <<PY
import json
p="$SETTINGS"; d=json.load(open(p))
env=d.setdefault("env",{})
env["GEMINI_CLI"]="gemini"   # 폴백 CLI 로 되돌림
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
print("  GEMINI_CLI=gemini (폴백). PATH 는 유지(다른 도구 공유)")
PY
            echo -e "  ${c_y}agy OFF${c_0} — Gemini 호출이 폴백 CLI 로"
            ;;
        *) die "사용법: addon agy on|off" ;;
    esac
}

# ── codex ─────────────────────────────────────────────
cmd_codex() {
    local val
    case "${1:-}" in
        on)  val=true ;;
        off) val=false ;;
        *) die "사용법: addon codex on|off" ;;
    esac
    backup_settings
    python3 - <<PY
import json
p="$SETTINGS"; d=json.load(open(p))
d.setdefault("enabledPlugins",{})["codex@openai-codex"]=$val
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
print("  enabledPlugins[codex@openai-codex]=$val")
PY
    echo -e "  codex ${1^^} — 변경 적용은 Claude Code 재시작 후"
}

# ── moai on/off (가역, 바이너리만) ───────────────────────
cmd_moai_toggle() {
    case "${1:-}" in
        on)
            if [ -f "$MOAI_BIN.disabled" ]; then
                mv "$MOAI_BIN.disabled" "$MOAI_BIN"
                echo -e "  ${c_g}moai ON${c_0} — 바이너리 복원"
            elif [ -x "$MOAI_BIN" ]; then
                echo -e "  ${c_d}이미 ON${c_0}"
            else
                die "moai 바이너리 없음. 재설치 필요"
            fi
            ;;
        off)
            if [ -x "$MOAI_BIN" ]; then
                mv "$MOAI_BIN" "$MOAI_BIN.disabled"
                echo -e "  ${c_y}moai OFF${c_0} — 바이너리 .disabled 로 (파일·.moai 디렉토리는 보존)"
                echo -e "  ${c_d}완전 제거는 'addon moai purge'${c_0}"
            else
                echo -e "  ${c_d}이미 OFF/없음${c_0}"
            fi
            ;;
        *) die "사용법: addon moai on|off" ;;
    esac
}

# ── moai purge (완전 제거, codex/agy/원본 무손상) ─────────
cmd_moai_purge() {
    local apply=0
    [ "${1:-}" = "--apply" ] && apply=1

    if [ $apply -eq 0 ]; then
        echo -e "${c_y}=== DRY-RUN === (실제 제거는 'addon moai purge --apply')${c_0}\n"
    else
        echo -e "${c_r}=== APPLY === 실제로 제거합니다${c_0}\n"
    fi

    local ts bak_root
    ts=$(python3 -c "import datetime;print(datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))")
    bak_root="$CLAUDE_DIR/backups/moai-purge-$ts"

    local n_del=0 n_restore=0 n_dir=0 n_skip=0

    echo -e "${c_b}[1] moai 마커 CLAUDE.md 처리${c_0}"
    for f in "$WORKSPACE"/*/CLAUDE.md; do
        [ -f "$f" ] || continue
        local dir proj first
        dir=$(dirname "$f"); proj=$(basename "$dir")
        first=$(head -1 "$f")
        if [ "$first" != "$MOAI_MARKER" ]; then
            n_skip=$((n_skip+1)); continue          # 원본 → 절대 보존
        fi
        # moai 가 만든 CLAUDE.md. git 원본 있나?
        if git -C "$dir" cat-file -e HEAD:CLAUDE.md 2>/dev/null; then
            echo -e "  ${c_g}restore${c_0} $proj ${c_d}(git 원본 복구)${c_0}"
            if [ $apply -eq 1 ]; then
                git -C "$dir" restore CLAUDE.md 2>/dev/null || git -C "$dir" checkout -- CLAUDE.md
            fi
            n_restore=$((n_restore+1))
        else
            echo -e "  ${c_r}delete ${c_0} $proj ${c_d}(git 원본 없음 → 삭제)${c_0}"
            if [ $apply -eq 1 ]; then
                mkdir -p "$bak_root/CLAUDE.md/$proj"
                cp "$f" "$bak_root/CLAUDE.md/$proj/CLAUDE.md"
                rm -f "$f"
            fi
            n_del=$((n_del+1))
        fi
    done

    echo -e "\n${c_b}[2] .moai 디렉토리 + .claude/rules/moai 제거${c_0}"
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        local proj; proj=$(basename "$(dirname "$d")")
        echo -e "  ${c_r}rm dir${c_0} $proj/.moai"
        if [ $apply -eq 1 ]; then
            mkdir -p "$bak_root/moai-dirs/$proj"
            cp -R "$d" "$bak_root/moai-dirs/$proj/.moai" 2>/dev/null || true
            rm -rf "$d"
        fi
        n_dir=$((n_dir+1))
    done < <(find "$WORKSPACE" -maxdepth 2 -name ".moai" -type d 2>/dev/null)

    while IFS= read -r d; do
        [ -z "$d" ] && continue
        local proj; proj=$(echo "$d" | sed "s#$WORKSPACE/##;s#/.claude.*##")
        echo -e "  ${c_r}rm dir${c_0} $proj/.claude/rules/moai"
        if [ $apply -eq 1 ]; then
            mkdir -p "$bak_root/rules-moai/$proj"
            cp -R "$d" "$bak_root/rules-moai/$proj/moai" 2>/dev/null || true
            rm -rf "$d"
        fi
        n_dir=$((n_dir+1))
    done < <(find "$WORKSPACE" -maxdepth 4 -path "*/.claude/rules/moai" -type d 2>/dev/null)

    echo -e "\n${c_b}[3] moai 바이너리 + 글로벌 흔적${c_0}"
    for t in "$MOAI_BIN" "$MOAI_BIN.disabled" "$HOME/.moai" "$CLAUDE_DIR/workflows/.moai"; do
        if [ -e "$t" ]; then
            echo -e "  ${c_r}rm${c_0}     $t"
            if [ $apply -eq 1 ]; then
                mkdir -p "$bak_root/global"
                cp -R "$t" "$bak_root/global/$(basename "$t")" 2>/dev/null || true
                rm -rf "$t"
            fi
        fi
    done

    echo -e "\n${c_b}=== 요약 ===${c_0}"
    echo -e "  CLAUDE.md:  ${c_g}원본복구 $n_restore${c_0} · ${c_r}삭제 $n_del${c_0} · ${c_d}원본보존(건드림X) $n_skip${c_0}"
    echo -e "  디렉토리:   ${c_r}$n_dir${c_0} (.moai + rules/moai)"
    if [ $apply -eq 1 ]; then
        echo -e "  백업:       ${c_d}$bak_root${c_0}"
        echo -e "  ${c_g}완료. codex/agy 무손상.${c_0}"
    else
        echo -e "\n  ${c_y}실제 제거: addon moai purge --apply${c_0}"
    fi
}

# ── 라우팅 ────────────────────────────────────────────
main() {
    local cmd="${1:-status}"; shift || true
    case "$cmd" in
        status) cmd_status ;;
        agy)    cmd_agy "$@" ;;
        codex)  cmd_codex "$@" ;;
        moai)
            local sub="${1:-}"; shift || true
            case "$sub" in
                on|off) cmd_moai_toggle "$sub" ;;
                purge)  cmd_moai_purge "$@" ;;
                *) die "사용법: addon moai on|off|purge [--apply]" ;;
            esac
            ;;
        -h|--help|help)
            grep -E "^#( |$)" "$0" | sed -E 's/^#( |$)//'
            ;;
        *) die "알 수 없는 명령: $cmd (status|agy|codex|moai)" ;;
    esac
}
main "$@"
