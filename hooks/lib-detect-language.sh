#!/bin/zsh
# 공통 언어/프레임워크 감지 함수
# 사용법: source lib-detect-language.sh && detect_language "/path/to/project"
# 결과: DETECTED, FRAMEWORK, DOCKER 변수 설정

detect_language() {
    local CWD="$1"
    DETECTED=""
    FRAMEWORK=""
    DOCKER=""

    if [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/requirements.txt" ] || [ -f "$CWD/setup.py" ]; then
        DETECTED="Python"
        if grep -q "fastapi" "$CWD/pyproject.toml" 2>/dev/null || grep -q "fastapi" "$CWD/requirements.txt" 2>/dev/null; then
            FRAMEWORK="FastAPI"
        elif grep -q "django" "$CWD/pyproject.toml" 2>/dev/null || grep -q "django" "$CWD/requirements.txt" 2>/dev/null; then
            FRAMEWORK="Django"
        elif grep -q "flask" "$CWD/pyproject.toml" 2>/dev/null || grep -q "flask" "$CWD/requirements.txt" 2>/dev/null; then
            FRAMEWORK="Flask"
        fi
    elif [ -f "$CWD/build.gradle" ] || [ -f "$CWD/build.gradle.kts" ] || [ -f "$CWD/settings.gradle.kts" ] || [ -f "$CWD/settings.gradle" ]; then
        local GRADLE_FILE=$(find "$CWD" -maxdepth 2 -name "build.gradle.kts" -o -name "build.gradle" 2>/dev/null | head -1)
        if [ -n "$GRADLE_FILE" ] && grep -q "kotlin" "$GRADLE_FILE" 2>/dev/null; then
            DETECTED="Kotlin"
        elif [ -f "$CWD/settings.gradle.kts" ]; then
            DETECTED="Kotlin"
        else
            DETECTED="Java"
        fi
        if [ -n "$GRADLE_FILE" ] && grep -q "spring" "$GRADLE_FILE" 2>/dev/null; then
            FRAMEWORK="Spring Boot"
        elif [ -n "$GRADLE_FILE" ] && grep -q "keycloak" "$GRADLE_FILE" 2>/dev/null; then
            FRAMEWORK="Keycloak SPI"
        fi
    elif [ -f "$CWD/pom.xml" ]; then
        DETECTED="Java"
        if grep -q "spring" "$CWD/pom.xml" 2>/dev/null; then
            FRAMEWORK="Spring Boot"
        fi
    elif [ -f "$CWD/composer.json" ]; then
        DETECTED="PHP"
        if grep -q "codeigniter" "$CWD/composer.json" 2>/dev/null; then
            FRAMEWORK="CodeIgniter"
        elif grep -q "laravel" "$CWD/composer.json" 2>/dev/null; then
            FRAMEWORK="Laravel"
        fi
    elif [ -f "$CWD/package.json" ]; then
        if [ -f "$CWD/next.config.js" ] || [ -f "$CWD/next.config.mjs" ] || [ -f "$CWD/next.config.ts" ]; then
            DETECTED="TypeScript"
            FRAMEWORK="Next.js"
        elif [ -f "$CWD/vite.config.ts" ] || [ -f "$CWD/vite.config.js" ]; then
            DETECTED="TypeScript"
            FRAMEWORK="Vite"
        elif [ -f "$CWD/tsconfig.json" ]; then
            DETECTED="TypeScript"
            FRAMEWORK="Node.js"
        else
            DETECTED="JavaScript"
            FRAMEWORK="Node.js"
        fi
    elif [ -f "$CWD/go.mod" ]; then
        DETECTED="Go"
    elif [ -f "$CWD/Cargo.toml" ]; then
        DETECTED="Rust"
    elif [ -f "$CWD/Gemfile" ]; then
        DETECTED="Ruby"
    fi

    if [ -f "$CWD/docker-compose.yml" ] || [ -f "$CWD/docker-compose.yaml" ] || [ -f "$CWD/compose.yml" ]; then
        DOCKER=" + Docker Compose"
    fi
}
