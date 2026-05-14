---
name: hook-audit
description: 79개 Claude Code 훅의 충돌/중복/경쟁 감지. /hook-audit 으로 의미론적 클러스터링, 쓰기 경쟁, 중복 등록 검출. 시스템 latency 분석과 정리 후보 자동 추천.
---

# Hook Audit — Hook Collider

`~/.claude/hooks/*.sh` 와 `~/.claude/settings.json` 의 훅 등록 상태를 분석해 충돌/중복을 감지한다.

## 분석 차원

1. **중복 등록**: 같은 훅이 같은 이벤트에 2번 이상 등록 (settings.json 실수)
2. **트리거 키워드 클러스터**: 같은 이벤트에서 같은 트리거(commit/error/edit/agent)에 반응하는 훅 3개+
3. **외부 CLI 호출 클러스터**: 같은 이벤트에서 gemma/gemini/codex CLI를 여러 훅이 동시 호출
4. **쓰기 경쟁**: 같은 파일에 여러 훅이 append/write
5. **크기 이상치**: 가장 큰 훅 5개 (리팩터 후보)

## 사용법

- `/hook-audit` — 분석 실행 + 리포트 생성
- `/hook-audit show` — 리포트 즉시 출력
- `/hook-audit json` — JSON 형식

## 절차

### 1. 분석 실행

```bash
python3 ~/.claude/scripts/hook-collider.py
```

### 2. 결과 출력

- 마크다운 리포트: `~/.claude/cache/hook-audit.md`
- JSON 데이터: `~/.claude/cache/hook-audit.json`

### 3. 권장 조치 적용

리포트 하단의 권장 조치 섹션 확인:
- 🔴 중복 등록 → settings.json 정리
- 🟠 트리거 클러스터 → 통합 검토
- 🟡 CLI 캐싱 / 쓰기 큐 도입

## 출력 형식

```bash
cat ~/.claude/cache/hook-audit.md
```

또는 사용자 요청에 따라 특정 섹션 발췌.

## 자동 재실행

훅이 추가/제거될 때마다 다시 실행 권장. 또는 cron으로 주간 재실행:

```bash
# crontab 예: 매주 월요일 9시
0 9 * * 1 /usr/bin/python3 /Users/leonard/.claude/scripts/hook-collider.py
```
