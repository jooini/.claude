---
name: ask-gemma
description: 호환성 유지용. 중앙 LLM 라우터의 local-only route를 통해 Gemma 모델에 질문하고 결과를 한국어로 정리한다.
allowed-tools: Bash(~/.agents/scripts/llm-router.sh *), Bash(/Users/leonard/.agents/scripts/llm-router.sh *), Read, Glob, Grep
---

# Ask Gemma

`ask-gemma`는 호환성 유지용이다. 일반 로컬 질의는 `ask-ollama`를 우선 사용한다.

## 중앙화 규칙

- 실행 진입점: `~/.agents/scripts/llm-router.sh`
- local-only route: `private --provider gemma`
- provider 실행/telemetry: `~/.claude/scripts/llm-call.sh`
- 직접 provider CLI/API 호출은 금지한다.

## 실행 절차

### 1단계: 모델 선택

기본 모델은 `gemma4:e4b`다. 사용자가 `26b`, `31b`, `고품질`을 명시한 경우에만 더 큰 Gemma 모델을 쓴다.

### 2단계: 라우터 실행

```bash
# 기본 Gemma
~/.agents/scripts/llm-router.sh private --caller ask-gemma --provider gemma --model gemma4:e4b --prompt "$QUESTION"

# 고품질 명시 요청
~/.agents/scripts/llm-router.sh private --caller ask-gemma --provider gemma --model gemma4:26b --prompt "$QUESTION"
```

### 3단계: 결과 정리

```text
## Gemma Local 의견

**요청 목적**: [왜 로컬 Gemma에 물었는지]
**핵심 답변**: [3-5줄 한국어 요약]
**신뢰도/한계**: [검증 필요 지점]
**최종 판단**: [현재 세션 관점 권고]
```

## 규칙

- 민감 정보는 `private` route만 사용한다.
- 외부 provider fallback을 임의로 열지 않는다.
- 큰 컨텍스트는 피하고, 필요하면 질문을 나눈다.
