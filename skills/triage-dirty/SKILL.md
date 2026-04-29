---
name: triage-dirty
description: "워크스페이스 전체 미커밋(dirty) 프로젝트를 Gemma가 분석해 우선순위/난이도/권고 조치 리포트 생성. /triage 트리거. 90개 이상 dirty 프로젝트 정리 로드맵 자동화."
argument-hint: "[분석할 상위 개수, 기본 20]"
disable-model-invocation: true
allowed-tools: Bash(python3 *)
---

# /triage — 미커밋 프로젝트 triage

워크스페이스 dirty 프로젝트를 Gemma가 분석해 **우선순위·난이도·권고 조치** 자동 생성.

## 실행

```bash
TRIAGE_TOP=$ARGUMENTS python3 ~/.claude/scripts/gemma-triage-dirty.py
```

`$ARGUMENTS` 비어있으면 기본 20개 분석.

## 리포트 내용

### 요약 테이블
각 dirty 프로젝트별:
- **우선순위**: 긴급 / 높음 / 중간 / 낮음
- **난이도**: 쉬움 / 보통 / 어려움
- **권고 조치**: 커밋 / 폐기 / 스태시 / 더 작업 필요
- **작업 추정**: 뭘 만들다 만 것 같은지 한 줄
- **예상 커밋 수**: 숫자

### 상세 분석
각 프로젝트별 Gemma 분석 원문 포함

### 분석 안 된 나머지
상위 N개 외 프로젝트 목록 (수동 확인용)

## 저장 경로

`~/.claude/cache/triage-dirty/{YYYY-MM-DD}.md`

## 사용 시점

- 미커밋 누적으로 답답할 때
- 주말 대청소 로드맵 필요할 때
- /health 리포트가 "미커밋 많음" 지적했을 때

## 호출 예시

```
/triage            # 상위 20개 (기본)
/triage 50         # 상위 50개 분석
```

## 소요 시간

- 20개 분석 시 ~5분 (Gemma 호출 × 20 + 데이터 수집)
- 50개 분석 시 ~12분

## 규칙

- 민감 파일 포함된 diff는 로컬 Gemma만 처리 (외부 유출 0)
- Gemma 분석은 코드 일부만 보고 추정 — 환각 가능 → 참고용
- 실제 정리는 사용자가 결정·실행 (자동 커밋/폐기 금지)

## 다음 단계 워크플로우

1. `/triage` 로 우선순위 파악
2. Top 3 프로젝트 선택
3. 각 프로젝트 `cd` 후 `git diff` 확인
4. Conventional Commits 형식으로 커밋 (gemma-commit-draft 훅 자동 동작)
5. GitLab push: `git push -o merge_request.create -o merge_request.target=main`
