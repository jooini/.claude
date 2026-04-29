---
name: iterm-task
description: iTerm2 Badge에 현재 작업 태스크를 표시하거나 해제한다.
argument-hint: "[태스크 내용]"
disable-model-invocation: true
allowed-tools: Bash(osascript *), Bash(ps *)
---

# iTerm Task Display

iTerm2 Badge를 사용하여 터미널 배경에 현재 태스크를 표시한다. 묻지 않고 바로 실행한다.

## 사용법

- `/iterm-task 회원가입 버그 수정` — 태스크 설정
- `/iterm-task` (인자 없음) — 태스크 해제

## 실행 방법

Bash 도구로 osascript를 실행하여 iTerm2 Badge escape sequence를 Claude Code의 TTY에 직접 전송한다.

### 1단계: TTY 확인

```bash
TTY=$(ps -o tty= -p $(ps -o ppid= -p $$))
```

### 2단계: Badge 설정/해제

#### 태스크 설정 (`$ARGUMENTS`가 있을 때)

```bash
BADGE=$(echo -n "$ARGUMENTS" | base64)
osascript -e "do shell script \"echo -ne '\\\\033]1337;SetBadgeFormat=${BADGE}\\\\007' > /dev/${TTY}\""
```

#### 태스크 해제 (`$ARGUMENTS`가 없을 때)

```bash
osascript -e "do shell script \"echo -ne '\\\\033]1337;SetBadgeFormat=\\\\007' > /dev/${TTY}\""
```

## 왜 Badge인가

- Claude Code가 탭 타이틀을 "⠐ Claude Code"로 계속 덮어쓰므로 탭 타이틀 변경은 불가
- Badge는 Claude Code가 건드리지 않으므로 안정적으로 유지됨
- `osascript do shell script`으로 TTY에 직접 쓰면 Claude Code의 stdout 캡처를 우회

## 동작 원리

- `\e]1337;SetBadgeFormat=<base64>\a`: iTerm2 고유 escape sequence로 Badge 텍스트 설정
- Badge는 터미널 배경 우측에 반투명 텍스트로 표시됨
- 다른 탭/창/세션에 영향 없음
