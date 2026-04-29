---
name: create-mr
description: 현재 브랜치에서 타겟 브랜치로 GitLab Merge Request를 생성한다
argument-hint: "[target-branch]"
disable-model-invocation: true
allowed-tools: Bash(git *)
---

# create-mr

현재 브랜치의 커밋을 GitLab에 푸시하고 Merge Request를 생성하는 스킬.

## 실행 절차

### 1. 사전 확인

```bash
# 현재 브랜치
CURRENT_BRANCH=$(git branch --show-current)

# 타겟 브랜치: $ARGUMENTS가 있으면 사용, 없으면 main
TARGET_BRANCH="${ARGUMENTS:-main}"
```

- 현재 브랜치가 타겟 브랜치와 동일하면 중단하고 사용자에게 알린다.
- 커밋되지 않은 변경사항이 있으면 사용자에게 알린다.

### 2. 변경 내역 분석

```bash
# 타겟 브랜치 대비 커밋 목록
git log --oneline $TARGET_BRANCH..HEAD

# 변경 파일 목록
git diff --stat $TARGET_BRANCH..HEAD
```

커밋 내역을 분석하여 MR 제목과 설명을 작성한다:
- **제목**: 70자 이내, 변경 요약 (한글)
- **설명**: 주요 변경사항을 bullet point로 정리 (한글)

### 3. 푸시 및 MR 생성

`git push` 에 GitLab push option을 사용하여 MR을 생성한다:

```bash
git push -u origin $CURRENT_BRANCH \
  -o merge_request.create \
  -o merge_request.target=$TARGET_BRANCH \
  -o merge_request.title="MR 제목" \
  -o merge_request.description="MR 설명"
```

### 4. 결과 출력

푸시 결과에서 MR URL을 추출하여 사용자에게 보여준다.

## 주의사항

- 소스 브랜치는 머지 후에도 삭제하지 않는다
- push option은 GitLab 11.10+ 에서 지원
- 이미 MR이 존재하면 GitLab이 기존 MR을 업데이트한다
