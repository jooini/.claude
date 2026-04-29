# /deploy-status - 배포 상태 확인

GitLab CI 파이프라인 상태와 AWS CodeDeploy 배포 상태를 한눈에 확인한다.

## 사용법

- `/deploy-status` - 전체 프로젝트 배포 상태
- `/deploy-status identity-hub` - 특정 프로젝트만

## 인자

$ARGUMENTS

## 프로젝트 정보

| 프로젝트 | GitLab 경로 | ECR Repository |
|----------|------------|----------------|
| identity-hub | (GitLab에서 확인) | `weaversbrain/identity-hub` |
| maxai-b2c-backend | (GitLab에서 확인) | `weaversbrain/maxai-b2c-backend` |
| identity-keycloak | (GitLab에서 확인) | `weaversbrain/identity-keycloak` |
| maxai-docker | (GitLab에서 확인) | - (S3 → CodeDeploy) |

ECR: `083876261616.dkr.ecr.ap-northeast-2.amazonaws.com`
S3 버킷: `wb-maxai`
CodeDeploy 앱: `maxai-docker-app`
CodeDeploy 그룹: `maxai-docker-dev-group`

## 수행 작업

### 1단계: 로컬 Git 상태 확인

각 프로젝트 디렉토리에서:
```bash
git -C {project_path} branch --show-current
git -C {project_path} log --oneline -3
git -C {project_path} status --short
```

프로젝트 경로:
- `~/Workspace/identity-hub/`
- `~/Workspace/maxai-b2c-backend/`
- `~/Workspace/identity-keycloak/`
- `~/Workspace/maxai-docker/`

### 2단계: 원격 브랜치 비교

```bash
git -C {project_path} fetch origin --dry-run 2>&1
git -C {project_path} log HEAD..origin/develop --oneline 2>/dev/null
```

### 3단계: dev 서버 배포 버전 확인

SSH → dev2-backend에서 실행 중인 이미지 태그 확인:
```bash
ssh dev2-backend "docker ps --format '{{.Image}}' | sort"
```

### 4단계: 결과 출력

```
=== 배포 상태 ===

[identity-hub]
  로컬 브랜치: feature/xxx
  최근 커밋: abc1234 feat: 어쩌고
  미커밋 변경: 2 files
  dev 서버 이미지: identity-hub:def5678
  로컬 vs 서버: ⚠️ 불일치

[maxai-b2c-backend]
  로컬 브랜치: feature/sso
  최근 커밋: 123abcd fix: 머시기
  미커밋 변경: 없음
  dev 서버 이미지: maxai-b2c-backend:latest
  로컬 vs 서버: ✅ 일치
```
