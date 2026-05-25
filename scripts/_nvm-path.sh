#!/bin/sh
# nvm-path: nvm 안의 node/npx/gemini 호출 시 PATH 보강
# Claude Code Bash tool 등 nvm 미소싱 환경 대응 — moai 업데이트로 settings.json env.PATH가 재생성돼도 무영향.
# 사용: source ~/.claude/scripts/_nvm-path.sh
# 우선순위: v22.22.0 > v22.4.1 (필요 시 추가)

for v in v22.22.0 v22.4.1; do
    if [ -x "/Users/leonard/.nvm/versions/node/$v/bin/node" ]; then
        case ":$PATH:" in
            *":/Users/leonard/.nvm/versions/node/$v/bin:"*) ;;
            *) export PATH="/Users/leonard/.nvm/versions/node/$v/bin:$PATH" ;;
        esac
        break
    fi
done
