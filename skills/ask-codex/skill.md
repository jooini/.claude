---
name: ask-codex
description: 파이프라인 밖에서 Codex에 임시 질문을 보내고 결과를 한국어로 요약한다. 구현 대안, 에러 분석, 패치 검토, 세컨드 오피니언 등에 사용.
allowed-tools: Bash(codex exec *), Bash(/Users/leonard/.nvm/versions/node/v22.22.0/bin/codex exec *), Read, Glob, Grep
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

### 2단계: Codex CLI 호출 (기본 경로)

`codex exec` 를 Bash로 호출한다. **MCP(`mcp__codex-cli__codex`)는 이 환경에서 세션 로드 안 됨("No such tool") — CLI 가 1순위다** (2026-05-30 검증).

```bash
# 기본 (codex 가 PATH 에 있을 때)
codex exec --skip-git-repo-check "$QUESTION"

# PATH 누락 시 절대경로 (which codex 는 'not found' 를 stdout 으로 뱉어 변수 오염시키므로 절대경로 직접 사용)
/Users/leonard/.nvm/versions/node/v22.22.0/bin/codex exec --skip-git-repo-check "$QUESTION"

# 파일 컨텍스트 포함 (heredoc 금지 — 파일은 인자나 stdin 으로)
codex exec --skip-git-repo-check "$QUESTION" < 관련파일.txt
```

호출 가이드:
- **effort**: 기본 config.toml 의 `xhigh` 사용. 가벼운 질문이면 `-c model_reasoning_effort=low` 로 낮춤
- **model**: config.toml 기본 `gpt-5.5`. 단순 반복이면 `-c model=gpt-5.4` 로 비용 절감
- **읽기 전용**: ask-codex 는 분석만 — `--write` 금지 (config 의 full-auto 와 무관하게 수정 위임 안 함)
- **출력 정리**: `2>&1 | grep -v "^hook:" | tail -N` 로 hook 노이즈/배너 제거 후 결론만 취함
- **타임아웃**: `timeout 120` 권장. xhigh 추론은 길어질 수 있음

> 자동 추적: 모든 호출이 `~/.codex/state_5.sqlite` 와 `~/.codex/history.jsonl` 에 기록됨.
> `/usage` 로 누적 토큰/세션 조회 가능.

### 3단계: 주의사항 (CLI 호출 함정)

- `codex -a "..."` → `--ask-for-approval` 플래그로 오해석됨. 반드시 `codex exec "..."` 형태
- 비-git 디렉토리(`~/.claude` 등)에서 `--skip-git-repo-check` 필수
- 프롬프트에 위험 키워드(DROP/rm 등) 직접 넣으면 danger-keyword 훅 오탐 가능 → 우회 표현 사용
- write 모드(`--write` 또는 sandbox 미지정)면 codex 가 실제 파일 수정/명령 실행함 — 분석엔 read-only 의도 유지

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

- **CLI 우선** — `codex exec` 가 기본. `mcp__codex-cli__codex` MCP는 이 환경에서 세션 로드 안 됨(검증 2026-05-30). MCP 호출 시도 금지
- Codex 답변을 검증 없이 확정안으로 사용하지 않는다
- 코드 수정이 필요하면 Claude가 직접 수정한다 (Codex 결과는 참고만). 단 대량 구현 위임은 `codex:rescue`/파이프라인 사용
- 분석 용도는 `--write` 금지 — 읽기 전용 의도 유지
- 파이프라인 대상 작업이면 이 스킬 대신 파이프라인 실행 (`workflows/codex.md` 참조)
- 같은 질문을 Gemini에도 중복 요청하지 않는다
