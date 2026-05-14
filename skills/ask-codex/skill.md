---
name: ask-codex
description: 파이프라인 밖에서 Codex에 임시 질문을 보내고 결과를 한국어로 요약한다. 구현 대안, 에러 분석, 패치 검토, 세컨드 오피니언 등에 사용.
allowed-tools: mcp__codex-cli__codex, mcp__codex-cli__ping, Bash(codex *), Read, Glob, Grep
---

# Ask Codex

파이프라인을 돌리기엔 과한 간단한 질문을 Codex에 던지고, 결과를 정리한다.

## 사용 시점

- 파이프라인 밖에서 Codex 의견이 필요할 때
- Claude 수정안의 대안 확인
- 에러/버그의 다른 관점 분석
- 구현 방향 비교, 패치 초안 검토
- 테스트 아이디어 수집

## 실행 절차

### 1단계: 질문 정리

사용자 요청을 구현 중심 질문으로 정리한다.
관련 코드가 있으면 컨텍스트에 포함한다 (파일 경로/스니펫을 prompt에 직접 첨부).

### 2단계: Codex MCP 호출 (기본 경로)

`mcp__codex-cli__codex` 도구를 호출한다.

| 파라미터 | 기본값 | 비고 |
|----------|--------|------|
| `prompt` | (필수) | 질문 + 컨텍스트. 한국어 결론 요청 명시 |
| `reasoningEffort` | `low` (가벼운 의견) / `medium` (분석) / `high` (세컨드 오피니언) | 깊이 vs 시간 |
| `sandbox` | `read-only` | ask-codex는 읽기만 — 수정 금지 |
| `model` | `gpt-5.3-codex` (기본) | 명시 안 하면 기본값 |
| `workingDirectory` | 프로젝트 루트 | 컨텍스트 분석 시 |
| `sessionId` | (선택) | 대화 연속 필요 시만 |

**호출 예** — Skill 결과 형식이 아닌 Claude의 도구 호출 형식:
- `mcp__codex-cli__codex(prompt="...", reasoningEffort="low", sandbox="read-only")`
- 컨텍스트 포함: prompt에 파일 경로(`@path/to/file.py`)나 스니펫을 직접 임베드

> 자동 추적: 모든 호출이 `~/.codex/state_5.sqlite` 의 `threads` 테이블에 기록됨.
> `/usage` 로 누적 토큰/세션 조회 가능.

### 3단계: 폴백 — CLI 직접 호출 (MCP 장애 시만)

`mcp__codex-cli__ping` 응답 없거나 MCP 호출 실패 시:

```bash
cd ~/.claude && codex exec --skip-git-repo-check "$QUESTION"
cd ~/.claude && codex exec --skip-git-repo-check "$QUESTION" < <(cat [관련 파일들])
```

⚠️ **CLI 폴백 주의**:
- `codex -a "..."` → `--ask-for-approval` 플래그로 해석됨 (에러)
- `--write` 플래그 금지 — 읽기 전용
- 비-git 디렉토리(`~/.claude` 등)에서 `--skip-git-repo-check` 필요
- stdout 빈 응답 자주 발생 (콜드스타트/제어문자 문제) → 폴백은 임시방편

### 4단계: 결과 정리

Codex 출력을 그대로 붙이지 않는다. 반드시 아래 형식으로 정리:

```
## Codex 의견 요약

**요청 목적**: [왜 Codex에 물었는지]

**핵심 답변**: [Codex 결과 한국어 요약, 3-5줄]

**주의/검증 필요**: [Codex가 틀렸거나 확인 필요한 부분]

**Claude 최종 판단**: [Claude 관점에서의 권고]
```

## 규칙

- **MCP 우선** — `mcp__codex-cli__codex` 가 기본. CLI는 MCP 장애 시 폴백
- Codex 답변을 검증 없이 확정안으로 사용하지 않는다
- 코드 수정이 필요하면 Claude가 직접 수정한다 (Codex 결과는 참고만)
- MCP `sandbox: "read-only"` 고정 — 수정 권한 위임 금지
- 파이프라인 대상 작업이면 이 스킬 대신 파이프라인 실행 (`workflows/codex.md` 참조)
- 같은 질문을 Gemini에도 중복 요청하지 않는다
