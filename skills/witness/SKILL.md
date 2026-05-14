---
name: witness
description: 시간차 증언대 — 현재 작업과 같은 문제를 과거에 어떻게 오판했는지 소환. /witness "작업 설명" 으로 과거 세션의 사용자 정정 + 옵시디언 실패 기록 + git revert 커밋을 통합 검색. "관련 문서"가 아닌 "과거의 나쁜 판단"만 추출.
---

# Witness — 시간차 증언대

작업 시작 시 과거의 나(또는 과거 Claude)가 같은 문제를 어떻게 잘못 판단했는지를 강제 소환한다.

## 일반 RAG와의 차이

| 비교축 | 일반 RAG | Witness |
|---|---|---|
| 무엇을 찾나 | 관련 문서 | 사용자 정정 + revert + 실패 기록 |
| 신호 종류 | 의미적 유사도 | "잘못/롤백/틀렸/deprecated" + 키워드 매칭 |
| 정렬 기준 | relevance | "이 작업에서 과거 실수했을 가능성" |
| 출력 | 정보 | 경고 |

## 자료원

1. **세션 로그**: `~/.claude/projects/-*/*.jsonl` — 과거 세션에서 사용자 정정 키워드("아니/틀렸/수정해") 직전 답변
2. **옵시디언**: `~/Workspace/weaversbrain/weaversbrain/{Projects,Plans,Learning,Sessions}/**/*.md` — "실패/롤백/장애/deprecated" 단서 포함 노트
3. **Git**: 현재 cwd의 `git log` 에서 revert/fix/hotfix/롤백 커밋

## 사용법

- `/witness "BFF timeout 설정 변경"` — 키워드 매칭으로 3채널 검색
- `/witness "phoneNumber unique" --project identity-hub` — 특정 프로젝트만
- `/witness "JWT validation" --top 5` — 상위 5개씩
- `/witness "..." --json` — JSON 출력 (다른 스킬 연계용)

## 절차

### 1. 키워드 추출
한글/영문 단어 2자 이상, 8개 이내. stop word 제거.

### 2. 3채널 병렬 검색
```bash
python3 ~/.claude/scripts/past-failure-witness.py "현재 작업 설명" --cwd "$PWD"
```

### 3. 결과 출력
3개 섹션으로 정리:
- 과거 세션 (사용자 정정 + 직전 답변)
- 옵시디언 실패 기록
- Git revert/fix 커밋

각 항목은 score 내림차순.

## 자동 호출 (선택)

UserPromptSubmit 훅에서 `--json` 모드로 호출 후 score > 0.5 인 항목이 있으면 stderr 경고:

```bash
# ~/.claude/hooks/witness-auto.sh (미배포)
RESULT=$(python3 ~/.claude/scripts/past-failure-witness.py "$USER_PROMPT" --json --top 3 2>/dev/null)
echo "$RESULT" | python3 -c "..." # score 체크 후 stderr 출력
```

## 주의

- 키워드 매칭 휴리스틱 — 의미적 검색 아님 (의도적: 정확한 단어 일치가 더 강한 신호)
- 옵시디언 노트가 많으면 시간 걸림 (max_files=200으로 제한)
- 과거 데이터가 적으면 "매칭 없음" 정상
