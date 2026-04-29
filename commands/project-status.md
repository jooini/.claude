# /project-status - 다중 프로젝트 상태 확인

4개 프로젝트의 git 브랜치, 미커밋 변경사항, 최근 커밋을 한눈에 확인한다.

## 사용법

- `/project-status` - 전체 프로젝트 상태

## 인자

$ARGUMENTS

## 대상 프로젝트

| 프로젝트 | 경로 |
|----------|------|
| maxai-b2c-backend | `~/Workspace/maxai-b2c-backend` |
| identity-hub | `~/Workspace/identity-hub` |
| identity-keycloak | `~/Workspace/identity-keycloak` |
| maxai-docker | `~/Workspace/maxai-docker` |
| keycloak-kakao-social-provider | `~/Workspace/keycloak-kakao-social-provider` |
| identity-hub-python-sdk | `~/Workspace/identity-hub-python-sdk` |

## 수행 작업

### 각 프로젝트별로 아래 명령 실행 (Bash 병렬 호출)

```bash
# 현재 브랜치
git -C {path} branch --show-current

# 미커밋 변경사항 (파일 수만)
git -C {path} status --short

# 최근 커밋 3개
git -C {path} log --oneline -3

# 원격 브랜치와 차이
git -C {path} log --oneline HEAD..origin/develop 2>/dev/null | wc -l
git -C {path} log --oneline origin/develop..HEAD 2>/dev/null | wc -l
```

### 출력 형식

```
=== 프로젝트 상태 ===

[maxai-b2c-backend]
  브랜치: feature/sso
  미커밋: 3 files (M: 2, ?: 1)
  최근 커밋:
    abc1234 feat: SSO 로그인 구현
    def5678 fix: 422 이메일 검증
    ghi9012 refactor: Auth 분리
  원격 동기화: ↑2 (push 필요)

[identity-hub]
  브랜치: feature/migration-check
  미커밋: 없음
  최근 커밋:
    9ab207a feat: 마이그레이션 체크 API
    445e215 feat: Admin 인증 모듈
    ...
  원격 동기화: ✅ 동기화됨

[identity-keycloak]
  브랜치: main
  미커밋: 없음
  ...

[maxai-docker]
  브랜치: feature/20260202-identity-only
  미커밋: 5 files ⚠️
  ...

--- 요약 ---
  push 필요: maxai-b2c-backend (↑2)
  미커밋 있음: maxai-docker (5 files)
  전체 깨끗: identity-hub, identity-keycloak
```

경로가 존재하지 않는 프로젝트는 "(디렉토리 없음)"으로 표시하고 스킵한다.
