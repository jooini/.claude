---
name: build-spi
description: Keycloak SPI/Provider를 빌드하고 로컬 Docker에 반영하여 테스트하는 절차를 자동 실행한다. "/build-spi", "SPI 빌드", "프로바이더 빌드" 등으로 트리거.
allowed-tools: Bash, Read, Glob, Grep
---

# Build SPI

Keycloak SPI/Provider 빌드 → Docker 반영 → 검증까지 일괄 실행.

## 사용 시점

- SPI/Provider 코드 수정 후 빌드 & 테스트
- 새 Provider 추가 후 Docker 반영 확인
- 테마 변경 후 빌드 & 확인

## 실행 절차

### 1단계: 프로젝트 위치 확인

```bash
cd ~/Workspace/identity-keycloak
```

### 2단계: 변경 대상 파악

`git diff --name-only`로 변경 파일 확인 → 빌드 대상 결정:

| 변경 위치 | 빌드 명령 |
|----------|----------|
| `providers-src/keycloak-kakao-*` | `make build-kakao` |
| `providers-src/keycloak-naver-*` | `make build-naver` |
| `providers-src/keycloak-legacy-*` | `make build-legacy` |
| `providers-src/keycloak-jit-*` | `make build-jit` |
| `providers-src/keycloak-md5*` | `make build-md5` |
| `frontend/` (테마 CSS/JS) | `cd frontend && npm run build:maxai` |
| `themes/` (FTL 템플릿) | 빌드 불필요, Docker 재시작만 |
| 전체/불명확 | `make build` |

### 3단계: 빌드 실행

변경 대상에 맞는 빌드 명령 실행. Makefile 타겟 확인 후 실행.

```bash
# 전체 빌드
make build

# 또는 특정 프로바이더만
make build-kakao
```

### 4단계: 로컬 Docker 반영

```bash
make local
```

이 명령은:
1. Docker 이미지 재빌드
2. 컨테이너 재시작
3. providers/ 디렉토리의 JAR 파일 반영

### 5단계: 검증

```bash
# Keycloak 로그 확인 (프로바이더 로드 성공 여부)
docker logs identity-keycloak 2>&1 | tail -50

# 프로바이더 목록 확인
docker exec identity-keycloak /opt/keycloak/bin/kc.sh show-config 2>&1 | grep -i provider || true

# 헬스체크
curl -s http://localhost:8080/health/ready | head -5
```

### 6단계: 결과 보고

```
## SPI 빌드 결과

| 항목 | 상태 |
|------|------|
| 빌드 대상 | [프로바이더명] |
| 빌드 결과 | 성공/실패 |
| Docker 반영 | 성공/실패 |
| 프로바이더 로드 | 확인됨/실패 |
| 헬스체크 | 정상/비정상 |
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| JAR 로드 실패 | 의존성 누락 | Fat JAR 확인, `shadowJar` 태스크 사용 |
| 테마 캐시 | Keycloak 캐시 | `docker exec ... /opt/keycloak/bin/kc.sh` 재시작 또는 `--spi-theme-cache-themes=false` |
| 빌드 실패 (Kotlin) | JDK 버전 | Java 17 확인 (`java -version`) |

## 규칙

- 프로덕션 배포는 이 스킬 범위 밖 → `make deploy` 전에 사용자 확인 필수
- 빌드 실패 시 에러 로그 전체 출력하여 분석
