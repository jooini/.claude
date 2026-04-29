#!/bin/bash
# docs/feature/ 구조 스캐폴딩 스크립트
# 사용법: scaffold-docs.sh <project-path> <project-name> <module1> [module2 ...]
# 기존 파일은 건드리지 않음 (신규만 생성)

set -euo pipefail

PROJECT_PATH="$1"
PROJECT_NAME="$2"
shift 2
MODULES=("$@")

DOCS_BASE="${PROJECT_PATH}/docs/feature"
TODAY=$(date +%Y-%m-%d)

mkdir -p "${DOCS_BASE}/core"
mkdir -p "${DOCS_BASE}/error"
mkdir -p "${DOCS_BASE}/testing"
mkdir -p "${DOCS_BASE}/integration"

for mod in "${MODULES[@]}"; do
    mkdir -p "${DOCS_BASE}/${mod}"
done

# --- 헬퍼: 파일 없을 때만 생성 ---
write_if_new() {
    local filepath="$1"
    local content="$2"
    if [ ! -f "$filepath" ]; then
        echo "$content" > "$filepath"
        echo "  + $(basename "$(dirname "$filepath")")/$(basename "$filepath")"
    fi
}

# --- README.md (네비게이션) ---
NAV_MODULES=""
for mod in "${MODULES[@]}"; do
    NAV_MODULES="${NAV_MODULES}| ${mod} | [overview](${mod}/01-overview.md) | [api](${mod}/02-api.md) | [test](testing/${mod}-test-checklist.md) | [integration](integration/${mod}-integration.md) |
"
done

write_if_new "${DOCS_BASE}/README.md" "# ${PROJECT_NAME} Feature Documentation

## 모듈 × 카테고리 매트릭스

| Module | Overview | API | Test | Integration |
|--------|----------|-----|------|-------------|
| core | [overview](core/01-overview.md) | - | [guide](testing/01-test-guide.md) | - |
${NAV_MODULES}
## 카테고리

- **core/** — 전 모듈 공통 기반
- **error/** — 에러 케이스 카탈로그
- **testing/** — 테스트 가이드 및 체크리스트
- **integration/** — 외부 시스템 연동 가이드

## 문서 규칙

- 파일명: \`NN-kebab-case.md\`
- 변경 이력: 각 디렉토리 \`CHANGELOG.md\`에 기록
- API 문서: 엔드포인트/메서드 단위로 상세 기술
"

# --- core ---
write_if_new "${DOCS_BASE}/core/01-overview.md" "# ${PROJECT_NAME} Core Overview

## 프로젝트 개요

> TODO: 프로젝트 목적, 기술 스택, 아키텍처 개요 작성

## 디렉토리 구조

> TODO: 주요 디렉토리 설명

## 설정

> TODO: 환경 변수, 설정 파일 설명
"

write_if_new "${DOCS_BASE}/core/CHANGELOG.md" "# Core Changelog

## ${TODAY}

- 문서 구조 초기화
"

# --- 각 모듈 ---
for mod in "${MODULES[@]}"; do
    write_if_new "${DOCS_BASE}/${mod}/01-overview.md" "# ${mod} Overview

## 개요

> TODO: ${mod} 모듈의 목적과 책임 범위

## 주요 기능

> TODO: 핵심 기능 목록

## 의존성

> TODO: 다른 모듈과의 관계
"

    write_if_new "${DOCS_BASE}/${mod}/02-api.md" "# ${mod} API Reference

## 엔드포인트 목록

> TODO: API 엔드포인트 상세

## 데이터 모델

> TODO: 요청/응답 스키마

## 에러 코드

> TODO: 모듈별 에러 코드 정의
"

    write_if_new "${DOCS_BASE}/${mod}/CHANGELOG.md" "# ${mod} Changelog

## ${TODAY}

- 문서 구조 초기화
"
done

# --- error ---
write_if_new "${DOCS_BASE}/error/01-common-error.md" "# 공통 에러 케이스

## 에러 코드 체계

> TODO: 에러 코드 네이밍 규칙, HTTP 상태 코드 매핑

## 공통 에러

| 코드 | HTTP | 설명 | 대응 |
|------|------|------|------|
| | | | |
"

write_if_new "${DOCS_BASE}/error/02-known-issues.md" "# Known Issues

## 현재 알려진 이슈

> TODO: 알려진 버그, 제한사항, 워크어라운드
"

write_if_new "${DOCS_BASE}/error/03-error-message-guide.md" "# 에러 메시지 가이드

## 클라이언트 표시용 메시지 매핑

> TODO: 내부 에러 코드 → 사용자 표시 메시지 매핑 테이블
"

# --- testing ---
write_if_new "${DOCS_BASE}/testing/01-test-guide.md" "# 테스트 가이드

## 테스트 환경 설정

> TODO: 테스트 실행 방법, 환경 변수, 의존성

## 테스트 구조

> TODO: 테스트 디렉토리 구조, 네이밍 규칙

## CI/CD 연동

> TODO: 자동 테스트 파이프라인 설명
"

IDX=2
for mod in "${MODULES[@]}"; do
    PADDED=$(printf "%02d" $IDX)
    write_if_new "${DOCS_BASE}/testing/${PADDED}-${mod}-test-checklist.md" "# ${mod} 테스트 체크리스트

## 기능 테스트

- [ ] TODO: 핵심 기능별 테스트 항목

## 엣지 케이스

- [ ] TODO: 경계값, 에러 시나리오

## 통합 테스트

- [ ] TODO: 다른 모듈과의 연동 테스트
"
    IDX=$((IDX + 1))
done

# --- integration ---
IDX=1
for mod in "${MODULES[@]}"; do
    PADDED=$(printf "%02d" $IDX)
    write_if_new "${DOCS_BASE}/integration/${PADDED}-${mod}-integration.md" "# ${mod} Integration Guide

## 연동 개요

> TODO: 외부 시스템과의 연동 방식

## 설정

> TODO: 연동에 필요한 설정값

## 시퀀스 다이어그램

> TODO: 주요 플로우 시퀀스

## 트러블슈팅

> TODO: 자주 발생하는 연동 이슈와 해결법
"
    IDX=$((IDX + 1))
done

echo ""
echo "✅ ${PROJECT_NAME} docs/feature/ 스캐폴딩 완료"
echo "   경로: ${DOCS_BASE}"
echo "   모듈: ${MODULES[*]}"
