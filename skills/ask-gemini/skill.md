---
name: ask-gemini
description: 중앙 LLM 라우터를 통해 Gemini/Antigravity provider에 질문하고 결과를 한국어로 요약한다. 코드 구조 질문, 문서 요약, UI 분석, 대규모 컨텍스트 탐색 등에 사용.
allowed-tools: Bash(~/.agents/scripts/llm-router.sh *), Bash(/Users/leonard/.agents/scripts/llm-router.sh *), Read, Glob, Grep
---

# Ask Gemini

Gemini/Antigravity provider 의견이 필요할 때 사용한다. provider CLI를 직접 실행하지 않고 `~/.agents/scripts/llm-router.sh`를 통해 호출한다.

## 중앙화 규칙

- 정책 정본: `~/.agents/registry/llm-routing.json`
- 실행 진입점: `~/.agents/scripts/llm-router.sh`
- provider 실행/telemetry: `~/.claude/scripts/llm-call.sh`
- handoff: `~/.agents/cache/llm-handoff/current.json`
- 직접 provider CLI 호출은 금지한다. 예외는 라우터/어댑터 자체 디버깅뿐이다.

## 사용 시점

- 코드 구조/아키텍처 빠른 스캔
- 긴 문서나 외부 레퍼런스 요약
- 스크린샷/UI 캡처 분석
- 아이디어 발산, 비교안 초안
- 파이프라인 밖에서 Gemini 관점이 필요할 때

## 실행 절차

### 1단계: 질문 정리

사용자 요청을 Gemini에 최적화된 질문으로 정리한다. 컨텍스트가 필요하면 관련 파일 내용을 함께 전달한다.

### 2단계: 라우터 실행

```bash
# Gemini provider 고정
~/.agents/scripts/llm-router.sh scan --caller ask-gemini --provider gemini --prompt "$QUESTION"

# 파일 컨텍스트 포함
cat [관련 파일들] | ~/.agents/scripts/llm-router.sh scan --caller ask-gemini --provider gemini --prompt -

# provider fallback까지 허용하는 일반 스캔
~/.agents/scripts/llm-router.sh scan --caller ask-gemini --prompt "$QUESTION"
```

### 3단계: 결과 정리

Gemini 출력을 그대로 붙이지 않는다.

```text
## Gemini 의견 요약

**요청 목적**: [왜 Gemini에 물었는지]
**핵심 답변**: [Gemini 결과 한국어 요약, 3-5줄]
**불확실/검증 필요**: [확인 필요한 부분]
**최종 판단**: [현재 세션 관점 권고]
```

## 규칙

- Gemini 답변을 검증 없이 사실로 단정하지 않는다.
- 코드 수정이 필요하면 현재 세션의 작업자가 직접 수정한다.
- 파이프라인 대상 작업이면 정규 파이프라인을 우선한다.
- 같은 질문을 Codex에도 중복 요청하지 않는다. 다중 리뷰가 필요하면 `llm-router.sh review`를 사용한다.
