---
name: badge
description: 현재 tmux 패널에 뱃지(이름)를 설정/삭제/조회한다. `/badge [텍스트]` 형태로 호출, 인자 없으면 현재 뱃지 표시, `-d`로 삭제, `-l`로 전체 목록.
---

# badge

현재 tmux 패널에 뱃지(이름)를 설정한다.

## 사용법

`/badge [텍스트]` 형태로 호출한다.

## 실행

```bash
# 뱃지 설정
badge {텍스트}

# 뱃지 삭제
badge -d

# 전체 패널 뱃지 목록
badge -l
```

인자 없이 `/badge`만 호출하면 현재 패널의 뱃지를 표시한다.

## 예시

- `/badge speech-hub` → 현재 패널에 "speech-hub" 표시
- `/badge 개발서버` → 현재 패널에 "개발서버" 표시
- `/badge -d` → 뱃지 삭제
