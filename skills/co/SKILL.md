---
name: co
description: git checkout을 실행하여 브랜치를 전환한다
argument-hint: "<branch-name>"
disable-model-invocation: true
allowed-tools: Bash(git *)
---

# co (checkout)

브랜치를 전환하는 스킬.

## 실행 절차

### 1. 사전 확인

- `$ARGUMENTS`가 없으면 "브랜치명을 입력해주세요" 알림 후 중단
- 커밋되지 않은 변경사항이 있으면 사용자에게 알리고 stash 여부를 확인한다

### 2. 브랜치 전환

```bash
git checkout $ARGUMENTS
```

- 로컬에 브랜치가 없으면 원격 브랜치를 추적하여 전환한다: `git checkout -b $ARGUMENTS origin/$ARGUMENTS`
- 전환 결과를 사용자에게 보여준다
