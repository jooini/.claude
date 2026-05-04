#!/usr/bin/env bash
# 통합 동기화 스크립트로 위임. 이전 sync-codex.sh의 기능은 sync-external.sh에 통합됨.
exec "$(dirname "$0")/sync-external.sh" "$@"
