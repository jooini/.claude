---
name: self-model
description: Claude 자신의 프로젝트별 실패 패턴 분석 및 조회. /self-model 로 현재 프로젝트의 자기 모델 보기, /self-model rebuild 로 252+ 세션 재분석. 추정/완료선언/사용자정정/반복수정 패턴 추적.
---

# Self-Model — Claude 자기반성 블랙박스

`~/.claude/projects/-Users-leonard-Workspace-{project}/*.jsonl` 의 252+ 세션 로그에서 Claude 자신의 실패 패턴을 추출하여 프로젝트별 자기 모델을 만든다.

## 검출 패턴

1. **추정 후 정정** — assistant가 "아마/추정/~인 듯" → 사용자가 "아니/틀렸/수정해" 정정
2. **테스트 안 돌리고 완료 선언** — "완료/끝났/성공" 발화 직전 30분 내 test/pytest/jest 미실행
3. **사용자 정정 패턴** — 사용자 정정 키워드 직전 assistant 답변
4. **반복 수정** — 한 세션 내 같은 파일 3회 이상 Edit/Write

## 사용법

- `/self-model` — 현재 프로젝트(cwd 기반) Self-Model 출력
- `/self-model rebuild` — 모든 프로젝트 재분석 (~/.claude/scripts/analyze-self-failures.py 실행)
- `/self-model {project}` — 특정 프로젝트 모델 (예: `/self-model identity-hub`)
- `/self-model global` — 전체 요약 (`_global.md`)
- `/self-model dry` — 파일 저장 없이 통계만

## 절차

### 1. 인자 파싱
- 인자 없음 → 현재 cwd 기반 프로젝트 추출
- `rebuild` → analyze-self-failures.py 실행 후 현재 프로젝트 출력
- `global` → `~/.claude/self-model/_global.md` 출력
- `dry` → `analyze-self-failures.py --dry-run` 실행
- 그 외 → `~/.claude/self-model/{인자}.md` 출력

### 2. 실행

```bash
# rebuild
python3 ~/.claude/scripts/analyze-self-failures.py

# 단일 프로젝트
python3 ~/.claude/scripts/analyze-self-failures.py --project identity-hub

# 출력
cat ~/.claude/self-model/{project}.md
```

### 3. 출력
Self-Model 파일이 있으면 그 내용 출력. 없으면 `rebuild` 실행 안내.

## 자동 주입 훅 (옵션)

`~/.claude/hooks/self-reflection-inject.sh` 가 UserPromptSubmit 훅에 등록되어 있으면, 답변 전 체크리스트가 stderr로 자동 주입됨.

활성화 방법: `~/.claude/settings.json` 의 `hooks.UserPromptSubmit` 배열에 추가:

```json
{
  "matcher": "",
  "hooks": [
    {"type": "command", "command": "/Users/leonard/.claude/hooks/self-reflection-inject.sh"}
  ]
}
```

## 주의

- 30일 초과된 모델은 stale 경고. `/self-model rebuild` 권장
- 분석은 프로젝트당 최근 50세션 (`--max-sessions`로 변경)
- 패턴 검출은 휴리스틱 — 거짓 양성 가능. 빈도가 의미 있음
