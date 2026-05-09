---
name: ask-codex
description: 파이프라인 밖에서 Codex CLI에 임시 질문을 보내고 결과를 한국어로 요약한다. 구현 대안, 에러 분석, 패치 검토, 세컨드 오피니언 등에 사용.
allowed-tools: Bash(codex *), Read, Glob, Grep
---

# Ask Codex

파이프라인을 돌리기엔 과한 간단한 질문을 Codex CLI에 던지고, 결과를 정리한다.

## 사용 시점

- 파이프라인 밖에서 Codex 의견이 필요할 때
- Claude 수정안의 대안 확인
- 에러/버그의 다른 관점 분석
- 구현 방향 비교, 패치 초안 검토
- 테스트 아이디어 수집

## 실행 절차

### 1단계: 질문 정리

사용자 요청을 구현 중심 질문으로 정리한다.
관련 코드가 있으면 컨텍스트에 포함한다.

### 2단계: Codex CLI 실행

```bash
# 분석/의견 요청 (read-only sandbox에서 실행)
cd ~/.claude && codex exec --skip-git-repo-check "$QUESTION"

# 코드 컨텍스트 포함
cd ~/.claude && codex exec --skip-git-repo-check "$QUESTION" < <(cat [관련 파일들])
```

> 자동 추적: 모든 codex 호출이 `~/.codex/state_5.sqlite`의 `threads` 테이블에 기록됨.
> `/usage`로 누적 토큰/세션 조회 가능.

⚠️ **잘못된 호출 패턴 주의**:
- `codex -a "..."`는 `--ask-for-approval` 플래그로 해석됨 → 에러
- `--write` 플래그 사용 금지 — 코드 수정은 Claude가 직접
- trusted directory 체크 우회: `--skip-git-repo-check` (~/.claude 등 비-git 디렉토리에서)

### 3단계: 결과 정리

Codex 출력을 그대로 붙이지 않는다. 반드시 아래 형식으로 정리:

```
## Codex 의견 요약

**요청 목적**: [왜 Codex에 물었는지]

**핵심 답변**: [Codex 결과 한국어 요약, 3-5줄]

**주의/검증 필요**: [Codex가 틀렸거나 확인 필요한 부분]

**Claude 최종 판단**: [Claude 관점에서의 권고]
```

## 규칙

- Codex 답변을 검증 없이 확정안으로 사용하지 않는다
- 코드 수정이 필요하면 Claude가 직접 수정한다 (Codex 결과는 참고만)
- `--write` 플래그 사용 금지 — 읽기 전용 분석만
- 파이프라인 대상 작업이면 이 스킬 대신 파이프라인을 실행한다
- 같은 질문을 Gemini에도 중복 요청하지 않는다
