---
name: bisect
description: "git bisect를 자동화하여 버그를 유발한 커밋을 찾는 스킬. /bisect 로 실행하면 정상 커밋과 버그 커밋 사이를 자동 이분 탐색한다."
argument-hint: "[정상 커밋 해시 또는 날짜] [검증 명령]"
---

# bisect

git bisect를 자동화하여 버그를 유발한 정확한 커밋을 특정한다.

## 실행 절차

### 1단계: 정보 수집

필요한 정보:
- **bad**: 현재 HEAD (버그 있는 상태, 기본값)
- **good**: 마지막으로 정상이었던 커밋
- **test**: 버그 존재 여부를 판별하는 명령

#### good 커밋 결정

`$ARGUMENTS`에 해시가 있으면 사용. 없으면:

```bash
# 최근 커밋 히스토리 보여주기
git log --oneline -20
```

사용자에게 "마지막으로 정상이었던 커밋이 어디야?" 질문.

날짜로 입력 시:
```bash
git log --oneline --before="{날짜}" -1
```

#### test 명령 결정

`$ARGUMENTS`에 명령이 있으면 사용. 없으면 자동 탐지:

```bash
# 테스트 파일 존재 여부로 판단
if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
    echo "pytest {관련 테스트 파일}"
elif [ -f "package.json" ]; then
    echo "npm test"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "gradle test"
elif [ -f "composer.json" ]; then
    echo "vendor/bin/phpunit"
fi
```

테스트가 없으면 사용자에게 검증 방법 질문.

### 2단계: bisect 실행

```bash
# 현재 상태 백업
ORIGINAL_BRANCH=$(git branch --show-current)

# bisect 시작
git bisect start
git bisect bad {bad_commit}
git bisect good {good_commit}
```

### 3단계: 자동 탐색

bisect run으로 자동 실행:

```bash
git bisect run {test_command}
```

또는 test 명령이 복잡한 경우 수동 루프:

```bash
while true; do
    CURRENT=$(git rev-parse --short HEAD)
    echo "테스트 중: $CURRENT"

    # 테스트 실행
    {test_command}
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        RESULT=$(git bisect good 2>&1)
    else
        RESULT=$(git bisect bad 2>&1)
    fi

    # 완료 확인
    if echo "$RESULT" | grep -q "is the first bad commit"; then
        echo "$RESULT"
        break
    fi
done
```

### 4단계: 결과 분석

원인 커밋 발견 시:

```bash
# 원인 커밋 상세 정보
git show --stat {원인커밋}
git show {원인커밋}
```

```
🎯 bisect 완료
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
원인 커밋: {해시} {메시지}
작성자: {작성자}
날짜: {날짜}
변경 파일:
  - {파일1}
  - {파일2}

탐색 범위: {good}..{bad} ({N}개 커밋)
탐색 횟수: {실제 테스트 횟수}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 5단계: 정리 + 후속 조치

```bash
# bisect 종료, 원래 브랜치로 복귀
git bisect reset
git checkout {ORIGINAL_BRANCH}
```

후속 조치 제안:
- 원인 커밋의 변경 내용 분석
- `/debug`로 이어서 수정할지 제안
- `git revert {원인커밋}` 가능 여부 판단

## 주의사항

- bisect 중 uncommitted 변경이 있으면 stash 먼저
- bisect reset 실패 시 수동 복구 안내
- 테스트 명령이 환경 의존적이면 (DB, Docker 등) 사전 확인
- 머지 커밋이 많은 경우 `--first-parent` 옵션 고려
