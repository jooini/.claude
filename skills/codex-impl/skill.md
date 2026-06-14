---
name: codex-impl
description: 중앙 LLM 라우터를 통해 Codex provider에 대안 구현을 요청한다. developer 에이전트와 병렬 실행용.
disable-model-invocation: true
allowed-tools: Bash(~/.agents/scripts/llm-router.sh *), Bash(/Users/leonard/.agents/scripts/llm-router.sh *), Read, Glob, Grep
---

# codex-impl

Codex provider로 동일 태스크의 대안 구현을 생성한다. 직접 provider CLI를 실행하지 않고 `~/.agents/scripts/llm-router.sh implement --provider codex`를 사용한다.

## 실행 절차

### 1단계: 사전 스캔 결과 확인

`~/.agents/cache/gemini/`에서 현재 프로젝트의 스캔 결과를 확인한다.

```bash
PROJECT=$(basename "$(pwd)")
SCAN="$HOME/.claude/cache/gemini/${PROJECT}-scan.md"
[ -f "$SCAN" ] && sed -n '1,220p' "$SCAN"
```

### 2단계: Codex provider로 대안 구현 요청

```bash
~/.agents/scripts/llm-router.sh implement --caller codex-impl --provider codex --prompt "다음 태스크의 구현안을 제안해줘:
[태스크 설명]

프로젝트 컨텍스트:
[Gemini 스캔 결과 요약]

기존 코드 패턴을 따르고, 필요한 테스트를 함께 제안할 것.
파일을 직접 수정하지 말고 패치/절차를 제안할 것."
```

### 3단계: 결과 저장

결과는 `~/.agents/cache/codex/{PROJECT}-parallel-impl.md`에 저장한다.

### 4단계: 비교

현재 세션의 구현과 Codex 구현안을 비교해 채택한다.

채택 기준:
- 기존 패턴 일관성
- 테스트 가능성
- 변경 범위
- 위험도

## 입력

$ARGUMENTS

위 절차에 따라 대안 구현을 생성한다.
