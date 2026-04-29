---
name: gemma-log
description: "Gemma 호출 기록 조회. /gemma-log 로 오늘 요약, /gemma-log tail 최근 호출, /gemma-log search <키워드>, /gemma-log stats 통계. 내 PC에서 Gemma가 뭘 처리했는지 확인."
argument-hint: "[tail|stats|search <키워드>|--date YYYY-MM-DD]"
disable-model-invocation: true
allowed-tools: Bash(python3 *)
---

# /gemma-log — Gemma 호출 기록 조회

Gemma가 언제, 어떤 훅에서, 무슨 요청 처리했는지 본다.

## 실행

```bash
python3 ~/.claude/scripts/gemma-call-log.py $ARGUMENTS
```

## 사용 예

### 오늘 요약 (기본)
```
/gemma-log
```

**출력**: 오늘 호출 수, 훅별 분포, 결과물 파일 위치

### 최근 호출 전문
```
/gemma-log tail
/gemma-log tail -n 20
```

**출력**: 마지막 10건 (입력/출력 미리보기 포함)

### 키워드 검색
```
/gemma-log search JWT
/gemma-log search 커밋
```

**출력**: 매칭 호출들의 관련 문맥

### 전체 통계
```
/gemma-log stats
```

**출력**: 훅별 호출 수, 날짜별 추이, 총 토큰

### 특정 날짜
```
/gemma-log --date 2026-04-22
```

## 로그 구조

저장 위치: `~/.claude/cache/gemma-calls.jsonl`

레코드 예시:
```json
{
  "timestamp": "2026-04-23T07:50:29Z",
  "caller": "gemma-commit-draft",
  "model": "gemma4:e4b",
  "status": "ok",
  "duration_ms": 897,
  "prompt_preview": "다음 staged 변경사항을...",
  "response_preview": "fix: 로그인 버그 수정...",
  "input_tokens": 230,
  "output_tokens": 85,
  "done_reason": "stop"
}
```

## 한계

- **기존 훅들이 직접 curl 호출** — 이들은 로그에 안 남음
- **`gemma-logger.sh` 래퍼 경유 호출만** 기록됨
- 신규 만드는 훅/스킬은 래퍼 사용 권장

## 래퍼 사용법 (신규 훅 작성 시)

```bash
RESULT=$(~/.claude/scripts/gemma-logger.sh "my-hook-name" "gemma4:e4b" "프롬프트" 800 0.3)
```

## 전체 기존 훅을 로깅하려면

`gemma-logger.sh` 사용하도록 기존 훅 9개 수정 필요 — 별도 작업.

지금은 신규 호출만 기록. 수동 `/ask-gemma` 호출 같은 건 훅 수정 필요.
