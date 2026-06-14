---
name: ask-codex
description: 중앙 LLM 라우터를 통해 Codex provider에 임시 질문을 보내고 결과를 한국어로 요약한다. 구현 대안, 에러 분석, 패치 검토, 세컨드 오피니언 등에 사용.
allowed-tools: Bash(~/.agents/scripts/llm-router.sh *), Bash(/Users/leonard/.agents/scripts/llm-router.sh *), Read, Glob, Grep
---

# Ask Codex

Codex provider 의견이 필요할 때 사용한다. Codex CLI를 직접 실행하지 않고 `~/.agents/scripts/llm-router.sh`를 통해 호출한다.

## 중앙화 규칙

- 정책 정본: `~/.agents/registry/llm-routing.json`
- 실행 진입점: `~/.agents/scripts/llm-router.sh`
- provider 실행/telemetry: `~/.claude/scripts/llm-call.sh`
- handoff: `~/.agents/cache/llm-handoff/current.json`
- 직접 provider CLI 호출은 금지한다. 예외는 라우터/어댑터 자체 디버깅뿐이다.

## 사용 시점

- 구현 방향 비교
- 패치 초안 검토
- 에러/버그의 다른 관점 분석
- 테스트 아이디어 수집
- 파이프라인 밖에서 Codex 의견이 필요할 때

## 실행 절차

### 1단계: 질문 정리

사용자 요청을 구현 중심 질문으로 정리한다. 관련 파일 경로와 필요한 스니펫을 prompt에 포함한다.

### 2단계: 라우터 실행

```bash
# Codex provider 고정, 분석 전용
~/.agents/scripts/llm-router.sh implement --caller ask-codex --provider codex --prompt "$QUESTION"

# 파일 컨텍스트 포함
cat [관련 파일들] | ~/.agents/scripts/llm-router.sh implement --caller ask-codex --provider codex --prompt -

# provider fallback까지 허용하는 구현 handoff
~/.agents/scripts/llm-router.sh implement --caller ask-codex --prompt "$QUESTION"
```

### 3단계: 결과 정리

Codex 출력을 그대로 붙이지 않는다.

```text
## Codex 의견 요약

**요청 목적**: [왜 Codex에 물었는지]
**핵심 답변**: [Codex 결과 한국어 요약, 3-5줄]
**주의/검증 필요**: [확인 필요한 부분]
**최종 판단**: [현재 세션 관점 권고]
```

## 규칙

- 분석 용도다. 파일 수정 위임이 필요하면 `codex-impl` 또는 정규 파이프라인을 사용한다.
- Codex 답변을 검증 없이 확정안으로 사용하지 않는다.
- 코드 수정이 필요하면 현재 세션의 작업자가 직접 수정한다.
- 같은 질문을 Gemini에도 중복 요청하지 않는다. 다중 리뷰가 필요하면 `llm-router.sh review`를 사용한다.
