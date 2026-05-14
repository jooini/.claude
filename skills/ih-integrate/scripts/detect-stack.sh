#!/usr/bin/env bash
# detect-stack.sh — 대상 디렉토리의 스택을 추론해 한 단어로 출력.
# 출력: nextjs | express | fastapi | kotlin | unknown
set -euo pipefail

DIR="${1:-.}"

if [[ ! -d "$DIR" ]]; then
    echo "unknown"
    exit 0
fi

if [[ -f "$DIR/package.json" ]]; then
    if grep -qE '"next"\s*:' "$DIR/package.json"; then
        echo "nextjs"; exit 0
    fi
    if grep -qE '"express"\s*:|"@nestjs/' "$DIR/package.json"; then
        echo "express"; exit 0
    fi
fi

if [[ -f "$DIR/pyproject.toml" ]] && grep -qiE 'fastapi' "$DIR/pyproject.toml"; then
    echo "fastapi"; exit 0
fi

if [[ -f "$DIR/requirements.txt" ]] && grep -qiE '^fastapi' "$DIR/requirements.txt"; then
    echo "fastapi"; exit 0
fi

if [[ -f "$DIR/build.gradle.kts" ]] || [[ -f "$DIR/build.gradle" ]]; then
    if grep -rqE 'spring-boot' "$DIR"/build.gradle* 2>/dev/null; then
        echo "kotlin"; exit 0
    fi
fi

if [[ -f "$DIR/pom.xml" ]] && grep -qE 'spring-boot' "$DIR/pom.xml"; then
    echo "kotlin"; exit 0
fi

echo "unknown"
