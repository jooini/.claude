#!/bin/sh
# nvm-path: nvm 안의 node/npx/gemini 호출 시 PATH 보강
# Claude Code Bash tool 등 nvm 미소싱 환경 대응 — moai 업데이트로 settings.json env.PATH가 재생성돼도 무영향.
# 사용: source ~/.claude/scripts/_nvm-path.sh
# 버전/사용자명 무관: $HOME + nvm alias default 자동 해석, 없으면 최신 설치본 fallback.

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -d "$NVM_DIR/versions/node" ] || return 0 2>/dev/null || exit 0

_nvm_bin=""

# 1순위: default alias 해석
if [ -f "$NVM_DIR/alias/default" ]; then
    _nvm_def=$(cat "$NVM_DIR/alias/default" 2>/dev/null)
    case "$_nvm_def" in
        v*)
            [ -x "$NVM_DIR/versions/node/$_nvm_def/bin/node" ] && _nvm_bin="$NVM_DIR/versions/node/$_nvm_def/bin"
            ;;
        *)
            # "22" 같은 메이저 → 해당 메이저의 최신 설치본
            _nvm_match=$(ls "$NVM_DIR/versions/node" 2>/dev/null | grep "^v${_nvm_def}\." | sort -V | tail -1)
            [ -n "$_nvm_match" ] && [ -x "$NVM_DIR/versions/node/$_nvm_match/bin/node" ] && _nvm_bin="$NVM_DIR/versions/node/$_nvm_match/bin"
            ;;
    esac
fi

# 2순위: 가장 최신 설치본 fallback
if [ -z "$_nvm_bin" ]; then
    _nvm_latest=$(ls "$NVM_DIR/versions/node" 2>/dev/null | sort -V | tail -1)
    [ -n "$_nvm_latest" ] && [ -x "$NVM_DIR/versions/node/$_nvm_latest/bin/node" ] && _nvm_bin="$NVM_DIR/versions/node/$_nvm_latest/bin"
fi

# PATH 주입 (중복 방지)
if [ -n "$_nvm_bin" ]; then
    case ":$PATH:" in
        *":$_nvm_bin:"*) ;;
        *) export PATH="$_nvm_bin:$PATH" ;;
    esac
fi

unset _nvm_bin _nvm_def _nvm_match _nvm_latest
