#!/bin/zsh
cat > /dev/null
afplay "$(dirname "$0")/sounds/fanfare.wav" &
say -v Yuna "작업 완료" < /dev/null &
