---
name: ask-ollama
description: 중앙 LLM 라우터의 local-only route를 통해 로컬 Ollama/Gemma provider에 질문하고 결과를 한국어로 정리한다. 민감 데이터, 오프라인/프라이빗 질의, 짧은 요약에 사용.
allowed-tools: Bash(~/.agents/scripts/llm-router.sh *), Bash(/Users/leonard/.agents/scripts/llm-router.sh *), Read, Glob, Grep
---

# Ask Ollama

로컬 Ollama/Gemma 계열 모델에 질문할 때 사용한다. `ini`나 Ollama REST API를 직접 호출하지 않고 `~/.agents/scripts/llm-router.sh private --provider gemma`를 통해 호출한다.

## 중앙화 규칙

- 정책 정본: `~/.agents/registry/llm-routing.json`
- 실행 진입점: `~/.agents/scripts/llm-router.sh`
- provider 실행/telemetry: `~/.claude/scripts/llm-call.sh`
- handoff: `~/.agents/cache/llm-handoff/current.json`
- 로컬-only route: `private --provider gemma`
- 직접 provider CLI/API 호출은 금지한다. 예외는 라우터/어댑터 자체 디버깅뿐이다.

## 모델 선택

provider는 항상 `gemma`로 두고, 모델만 `--model`로 override한다.

| 입력 신호 | 모델 |
|---|---|
| 코드, 구현, 디버그, 리팩터, SQL | `qwen2.5-coder:14b` |
| 한국어, 번역, 요약, 문서, 일반 질의 | `qwen3.5:9b` |
| 빠르게, 간단히 | `gemma4:e4b` |
| 깊이, 정확하게, 고품질 | `gemma4:26b` |
| 사용자가 모델 명시 | 사용자 지정 우선 |

## 실행 절차

### 1단계: 질문과 모델 정리

사용자 요청에서 모델 명시가 있으면 그대로 쓴다. 없으면 위 표에 따라 모델을 고른다.

### 2단계: 라우터 실행

```bash
# 일반/한국어 기본
~/.agents/scripts/llm-router.sh private --caller ask-ollama --provider gemma --model qwen3.5:9b --prompt "$QUESTION"

# 코딩 질의
~/.agents/scripts/llm-router.sh private --caller ask-ollama --provider gemma --model qwen2.5-coder:14b --prompt "$QUESTION"

# 빠른 질의
~/.agents/scripts/llm-router.sh private --caller ask-ollama --provider gemma --model gemma4:e4b --prompt "$QUESTION"

# stdin 입력
cat [관련 파일들] | ~/.agents/scripts/llm-router.sh private --caller ask-ollama --provider gemma --model qwen3.5:9b --prompt -
```

### 3단계: 결과 정리

원문 그대로 붙이지 않는다.

```text
## Ollama Local 의견

**선택 모델**: [모델명]
**선택 사유**: [왜 이 모델을 골랐는지]
**핵심 답변**: [3-5줄 한국어 요약]
**신뢰도/한계**: [검증 필요 지점]
**최종 판단**: [현재 세션 관점 권고]
```

## 규칙

- 민감 정보는 `private` route만 사용한다.
- 외부 provider fallback을 임의로 열지 않는다.
- 로컬 모델의 사실 주장은 교차 검증한다.
- 코드 수정은 결과를 참고만 하고 현재 세션의 작업자가 직접 수행한다.
- 서버가 office-only라 외부망에서 `expected_offline`이면 장애로 단정하지 않는다.
