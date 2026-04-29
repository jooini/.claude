---
name: pr-preview
description: "PR 올리기 전 셀프 Q&A. Gemma가 까칠한 시니어 리뷰어 입장에서 10개 질문 생성 (설계/엣지케이스/테스트/보안/유지보수). /pr-preview 로 호출. 부끄러운 PR 방지, 리뷰 round-trip 절감."
argument-hint: "[base_branch|--staged]"
disable-model-invocation: true
allowed-tools: Bash(bash *)
---

# /pr-preview — PR 셀프 Q&A

PR 올리기 전 Gemma가 리뷰어 역할로 날카로운 질문 10개 던진다. 답 못 하는 게 있으면 그게 취약점.

## 실행

```bash
bash ~/.claude/scripts/gemma-pr-preview.sh $ARGUMENTS
```

## 사용 예

### 기본 — origin/main(또는 master) 대비
```
cd <프로젝트>
/pr-preview
```

### base 브랜치 지정
```
/pr-preview develop
/pr-preview origin/release-1.2
```

### staged 변경만
```
/pr-preview --staged
```

## 출력 형식

```
## Q1. [설계 의도] 왜 Repository 패턴 대신 직접 쿼리?
   난이도: ★★
   힌트: 기존 UserService 구조와 비교

## Q2. [엣지 케이스] userId가 None이면?
   난이도: ★★★
   힌트: auth_dependency 반환값 체크

## Q3. [테스트] 이 로직 테스트 하나 지금 작성해봐
   난이도: ★★
   힌트: pytest + mock

...
```

## 질문 카테고리 (10개)

| # | 카테고리 | 질문 수 |
|---|----------|---------|
| 1 | 설계 의도 | 2 |
| 2 | 엣지 케이스 (null/빈배열/동시성/네트워크) | 3 |
| 3 | 테스트 | 2 |
| 4 | 보안/성능 | 1 |
| 5 | 유지보수 | 1 |
| 6 | 제거 가능성 | 1 |

## 워크플로우

1. 구현 완료 → `git commit`
2. `/pr-preview` → 질문 10개 받음
3. 답 못 하는 것 → 그 부분 보완
4. 다시 커밋 → `/pr-preview` 재실행
5. 다 답변 되면 → PR 올림

## 안전장치

- diff 800줄 초과 시 앞부분만 사용 (프롬프트 한도)
- git 리포 아니면 종료
- base 자동 감지: origin/main → origin/master → origin/develop

## 한계

- Gemma가 코드 컨텍스트 깊이는 부족 — 프로젝트 전체 이해 못 함
- 질문 품질은 diff 품질에 비례 — 작은 diff일수록 구체적
- 보안 심각도 판정은 Claude/Codex가 나음 (이건 보조용)

## 관련 스킬

- `/weekly-learning` — 주간 학습 리포트
- `/go` — PR 전 검증 파이프라인
- `/review` — 공식 PR 리뷰
