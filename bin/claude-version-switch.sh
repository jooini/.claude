#!/bin/zsh
# claude-version-switch.sh — malformed-toolcall 회귀(2.1.157+) 비상 전환 스크립트
#
# 배경: streaming stop_sequence truncation 회귀가 2.1.157+ 에서 도입됨(포렌식 #12952).
# 클라이언트 완화책은 2.1.156(회귀 전 빌드) 다운그레이드뿐. env 토글로는 못 끔.
# 메모리: malformed-toolcall-streaming-regression.md
#
# 사용:
#   claude-version-switch.sh status      # 현재 버전 + 가용 버전
#   claude-version-switch.sh downgrade    # → 2.1.156 (회귀 전, malformed 없음)
#   claude-version-switch.sh restore      # → 최신(2.1.159 등)
#   claude-version-switch.sh <버전>       # 특정 버전 지정
#
# ⚠️ 전환은 symlink 만 바꾼다. 현재 실행 중인 세션엔 즉시 적용 안 됨 — 다음 claude 실행부터 적용.
# ⚠️ 2.1.156 다운그레이드 시 상실: loop keepalive(/loop 재예약), plugin 자동동기화, Pewter Owl.

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
        print -r -- "clean 버전: $CLEAN_VERSION (회귀 전, malformed 없음)"
        print -r -- "가용 버전 :"
        list_versions | sed 's/^/  - /'
        print -r -- "symlink   : $LINK -> $(current_target)"
        ;;
    downgrade)
        [ -x "$VER_DIR/$CLEAN_VERSION" ] || err "clean 버전 $CLEAN_VERSION 없음. 다운그레이드 불가."
        print -r -- "[*] malformed 회귀 완화를 위해 $CLEAN_VERSION 로 다운그레이드합니다."
        print -r -- "    상실 기능: loop keepalive, plugin 자동동기화, Pewter Owl."
        switch_to "$CLEAN_VERSION"
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
