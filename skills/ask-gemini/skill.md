---
name: ask-gemini
description: 파이프라인 밖에서 Gemini CLI에 임시 질문을 보내고 결과를 한국어로 요약한다. 코드 구조 질문, 문서 요약, UI 분석, 대규모 컨텍스트 탐색 등에 사용.
allowed-tools: Bash(gemini *), Read, Glob, Grep
---

# Ask Gemini

파이프라인을 돌리기엔 과한 간단한 질문을 Gemini CLI에 던지고, 결과를 정리한다.

## 사용 시점

- 파이프라인 밖에서 Gemini 의견이 필요할 때
- 코드 구조/아키텍처 빠른 스캔
- 긴 문서/PDF/외부 레퍼런스 요약
- 스크린샷/UI 캡처 분석
- 아이디어 발산, 비교안 초안

## 실행 절차

### 1단계: 질문 정리

사용자 요청을 Gemini에 최적화된 한 줄 질문으로 정리한다.
컨텍스트가 필요하면 관련 파일을 stdin으로 파이프한다.

### 2단계: Gemini CLI 실행

```bash
# 단순 질문
gemini -p "$QUESTION"

# 파일 컨텍스트 포함
gemini -p "$QUESTION" < <(cat [관련 파일들])

# 대규모 스캔
gemini -p "$QUESTION" < <(find [대상경로] -type f \( -name '*.py' -o -name '*.ts' -o -name '*.kt' \) | head -200 | xargs cat)
```

### 3단계: 결과 정리

Gemini 출력을 그대로 붙이지 않는다. 반드시 아래 형식으로 정리:

```
## Gemini 의견 요약

**요청 목적**: [왜 Gemini에 물었는지]

**핵심 답변**: [Gemini 결과 한국어 요약, 3-5줄]

**불확실/검증 필요**: [Gemini가 틀렸거나 확인 필요한 부분]

**Claude 최종 판단**: [Claude 관점에서의 권고]
```

## 규칙

- Gemini 답변을 검증 없이 사실로 단정하지 않는다
- 코드 수정이 필요하면 Claude가 직접 수정한다 (Gemini 결과는 참고만)
- 파이프라인 대상 작업이면 이 스킬 대신 파이프라인을 실행한다
- 같은 질문을 Codex에도 중복 요청하지 않는다
