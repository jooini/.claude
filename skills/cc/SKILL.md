---
name: cc
description: 변경사항을 분석하여 한글 커밋 메시지를 작성하고 커밋 + 푸시한다
argument-hint: "[커밋 메시지]"
disable-model-invocation: true
allowed-tools: Bash(git *)
---

# cc (commit & push)

변경사항을 분석하여 커밋하고 origin에 푸시하는 스킬.

## 실행 절차

### 1. 상태 확인

```bash
git status
git diff --stat
git diff --cached --stat
```

- 변경사항이 없으면 "커밋할 내용이 없습니다" 알림 후 중단
- staged 변경사항이 있으면 그것만, 없으면 tracked 파일 변경사항을 대상으로 한다

### 2. 변경사항 스테이징

- staged 파일이 이미 있으면 그대로 사용
- 없으면 변경된 파일을 `git add`로 스테이징 (untracked 파일은 제외, 필요 시 사용자에게 확인)
- `.env`, credentials 등 민감 파일은 절대 스테이징하지 않는다

### 3. 커밋 메시지 작성

`$ARGUMENTS`가 주어지면 그대로 사용한다.
없으면 `git diff --cached`를 분석하여 자동 작성한다:

- **한글**로 작성
- 1줄 요약 (70자 이내)
- 필요 시 빈 줄 후 상세 설명 추가
- Co-Authored-By 포함하지 않음
- conventional commit 접두사 사용 (feat, fix, refactor, chore, docs, test)

### 4. 커밋 실행

```bash
git commit -m "메시지"
```

### 5. 푸시

```bash
git push
```

- upstream이 설정되지 않은 경우 `git push -u origin {브랜치명}` 사용
- 푸시 결과를 사용자에게 보여준다
