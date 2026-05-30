---
name: codex-impl
description: Codex CLI로 대안 구현을 생성합니다. developer 에이전트와 병렬 실행용.
disable-model-invocation: true
allowed-tools: Bash(codex *), Bash(ls *), Bash(cat *), Read, Glob, Grep
---

# codex-impl

Codex CLI(기본 모델 gpt-5.5, config.toml)로 동일 태스크의 대안 구현을 생성한다.
developer 에이전트와 병렬로 실행하여 두 결과를 비교, 최선안을 채택.

## 실행 절차

### 1단계: Gemini 스캔 결과 확인

`~/.claude/cache/gemini/`에서 현재 프로젝트의 스캔 결과를 확인.

```bash
PROJECT=$(basename $(pwd))
SCAN="$HOME/.claude/cache/gemini/${PROJECT}-scan.md"
[ -f "$SCAN" ] && cat "$SCAN"
```

### 2단계: Codex로 대안 구현 실행

$ARGUMENTS에서 구현 태스크를 파악하고 Codex에 넘긴다.

```bash
# codex exec 사용 — 'codex -a' 는 --ask-for-approval 오해석 버그.
# PATH 에 codex 없으면 절대경로: $HOME/.nvm/versions/node/v22.22.0/bin/codex
codex exec --skip-git-repo-check --write "다음 태스크를 구현해줘:
[태스크 설명]

프로젝트 컨텍스트:
[Gemini 스캔 결과 요약]

기존 코드 패턴을 따르고, 테스트도 함께 작성할 것."
```

`--write` 플래그로 Codex가 직접 파일을 수정하게 한다(config.toml full-auto + 기본 모델 gpt-5.5).

### 3단계: 결과 저장

Codex 실행 결과를 `~/.claude/cache/codex/{PROJECT}-parallel-impl.md`에 저장.

### 4단계: 비교 안내

```
[Codex parallel-impl 완료]
developer 구현과 비교하여 최선안을 채택하세요.
채택 기준: 코드 품질, 기존 패턴 일관성, 테스트 통과율
```

## 입력

$ARGUMENTS

위 절차에 따라 대안 구현을 생성하세요.
