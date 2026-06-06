#!/bin/zsh
# claude-version-switch.sh — Claude Code 버전 전환 스크립트
#
# ☠️☠️ DEAD PATH 경고 (2026-06-02): `downgrade`(→2.1.156) 는 더 이상 유효하지 않다.
#   (1) 2.1.156 은 디스크에서 삭제됨 — ~/.local/share/claude/versions/ 에 158/159/160 만 존재.
#       → downgrade 서브커맨드는 자체 가드(69행)에서 "clean 버전 없음"으로 실패함.
#   (2) malformed-toolcall 의 근본원인은 2.1.157+ 클라 streaming 회귀가 아니라
#       **Opus 4.8 모델 레이어 회귀**로 재귀속됨(공식 #63604/#64076 이 2.1.156 에서도 재현 = 반증).
#       즉 2.1.156 으로 내려도 malformed 안 고쳐짐.
#   ✅ malformed 비상 완화책 = 바이너리 다운그레이드가 아니라 **모델 다운그레이드**:
#        /model claude-opus-4-7   (또는 settings.json env ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-7)
#      maintainer 문서화 #63604 "Opus 4.8→4.7 전환 시 즉시 정상화". loop keepalive/plugin sync/Pewter Owl 유지.
#   메모리: malformed-toolcall-streaming-regression.md (2026-06-02 재귀속)
#
# status/restore/<버전> 서브커맨드는 일반 버전 전환용으로 여전히 동작. downgrade 만 죽음.
#
# 사용:
#   claude-version-switch.sh status      # 현재 버전 + 가용 버전
#   claude-version-switch.sh downgrade    # ☠️ DEAD: 2.1.156 없음 + malformed 안 고침. /model claude-opus-4-7 쓸 것
#   claude-version-switch.sh restore      # → 최신
#   claude-version-switch.sh <버전>       # 특정 버전 지정
#
# ⚠️ 전환은 symlink 만 바꾼다. 현재 실행 중인 세션엔 즉시 적용 안 됨 — 다음 claude 실행부터 적용.

set -u

VER_DIR="$HOME/.local/share/claude/versions"
LINK="$HOME/.local/bin/claude"
CLEAN_VERSION="2.1.156"   # 회귀 전 마지막 clean 빌드

err() { print -r -- "[error] $*" >&2; exit 1; }

current_target() {
    readlink "$LINK" 2>/dev/null
}

current_version() {
    local t
    t=$(current_target)
    [ -n "$t" ] && basename "$t" || echo "unknown"
}

latest_version() {
    ls -1 "$VER_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

list_versions() {
    ls -1 "$VER_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V
}

switch_to() {
    local v="$1"
    local bin="$VER_DIR/$v"
    [ -x "$bin" ] || err "버전 $v 바이너리 없음/실행불가: $bin"
    # 무결성: 실제로 버전 문자열을 출력하는지 검증
    local got
    got=$("$bin" --version 2>/dev/null | head -1)
    print -r -- "$got" | grep -q "$v" || err "버전 $v 무결성 검증 실패 (got: $got)"
    ln -sf "$bin" "$LINK" || err "symlink 갱신 실패"
    print -r -- "[ok] claude → $v 로 전환됨"
    print -r -- "     검증: $("$LINK" --version 2>/dev/null | head -1)"
    print -r -- "     ⚠️ 현재 세션엔 미적용 — 새 claude 실행부터 반영됨"
}

cmd="${1:-status}"

case "$cmd" in
    status)
        print -r -- "현재 버전 : $(current_version)"
        print -r -- "최신 버전 : $(latest_version)"
        print -r -- "malformed : Opus 4.8 모델 레이어 회귀라 버전 다운그레이드로 안 고쳐짐 → /model claude-opus-4-7 쓸 것"
        print -r -- "가용 버전 :"
        list_versions | sed 's/^/  - /'
        print -r -- "symlink   : $LINK -> $(current_target)"
        ;;
    downgrade)
        print -r -- "☠️ [DEAD] 2.1.156 바이너리 다운그레이드는 malformed 를 고치지 못합니다." >&2
        print -r -- "    이유: malformed 근본원인은 Opus 4.8 모델 레이어 회귀(#63604/#64076 은 2.1.156 에서도 재현)." >&2
        print -r -- "    또한 2.1.156 은 디스크에서 삭제됨(현재 가용: $(list_versions | tr '\n' ' '))." >&2
        print -r -- "" >&2
        print -r -- "    ✅ malformed 비상 완화책 = 모델 다운그레이드:" >&2
        print -r -- "         세션 한정:  /model claude-opus-4-7" >&2
        print -r -- "         영구 핀  :  settings.json env ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-7" >&2
        err "downgrade 비활성화됨 — 위 모델 다운그레이드를 사용하세요."
        ;;
    restore)
        switch_to "$(latest_version)"
        ;;
    [0-9]*)
        switch_to "$cmd"
        ;;
    *)
        err "알 수 없는 명령: $cmd (status|downgrade|restore|<버전>)"
        ;;
esac
