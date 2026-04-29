---
name: weekly-learning
description: "주간 학습 리포트 — 지난 7일 zsh_history + git log 분석 → Gemma가 학습 패턴/반복 실수/주요 테마 추출. /weekly-learning 으로 호출. --save 옵션 Obsidian 저장."
argument-hint: "[--days N] [--save] [--raw]"
disable-model-invocation: true
allowed-tools: Bash(python3 *)
---

# /weekly-learning — 주간 개발 학습 리포트

터미널 히스토리와 Git 활동을 분석해서 "이번 주 뭘 배웠는지" Gemma가 정리.

## 실행

```bash
python3 ~/.claude/scripts/gemma-weekly-learning.py $ARGUMENTS
```

## 사용 예

### 기본 (지난 7일)
```
/weekly-learning
```

### 기간 지정
```
/weekly-learning --days 14
/weekly-learning --days 30
```

### Obsidian 저장
```
/weekly-learning --save
```
→ `~/Workspace/weaversbrain/weaversbrain/00-inbox/YYYY-MM-DD-HHMM-weekly-learning.md`

### Gemma 호출 없이 원본 데이터만
```
/weekly-learning --raw
```

## 리포트 구성

1. **이번 주 새로 배운 것** — 신규 명령어 중 흥미로운 것 2~3개 설명
2. **반복되는 패턴 진단** — 개선 필요한 것 지적
3. **이번 주 주요 작업 테마** — Top 명령어 + Git 활동 기반
4. **다음 주 개선 제안** — 실행 가능한 1~2개

## 부록 (자동 첨부)

- Top 15 명령어 (빈도순)
- 신규 명령어 전체 리스트
- 패턴 카운트 (git push 재시도, cd 왕복, rm -rf, docker restart, 오타 수정)

## 감지 패턴

| 패턴 | 설명 |
|------|------|
| `git_push_fail` | push 후 pull/rebase 재시도 |
| `cd_oscillation` | 같은 디렉토리 3회+ 왕복 |
| `rm_rf` | 강제 삭제 사용 |
| `docker_restart` | 도커 재시작 반복 |
| `typo_fix` | 직전 명령과 유사 (오타) |

## 정기 실행 (선택)

매주 일요일 자동:
```bash
# ~/.claude/scripts/gemma-cron.plist 에 추가
0 20 * * 0  python3 ~/.claude/scripts/gemma-weekly-learning.py --save
```

## 데이터 소스

- `~/.zsh_history` — 명령어 히스토리
- `~/Workspace/*/.git` — 프로젝트별 커밋
- 호출 기록: `~/.claude/cache/gemma-calls.jsonl`

## 한계

- zsh_history latin-1 디코딩 — 한글 깨질 수 있음
- 신규 명령어 판정은 "이전 히스토리에 없음" 기준 (실제 처음 배운 건지는 추측)
- 패턴 감지는 휴리스틱 — 완벽하지 않음

## 관련 스킬

- `/pr-preview` — PR 올리기 전 셀프 Q&A
- `/gemma-log tail` — 최근 Gemma 호출 확인
