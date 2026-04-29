---
name: decisions
description: 자동 캡처된 설계/리뷰 결정을 검색하고 표시한다. decision-capture.sh 훅이 Obsidian Vault에 저장한 결정 기록을 탐색. "/decisions [검색어]", "결정 검색", "이전 결정" 등으로 트리거.
---

# Decisions — 결정 기록 검색

`~/Workspace/weaversbrain/weaversbrain/decisions/` 에 자동 캡처된 결정 기록을 검색.

## 사용법

- `/decisions` — 최근 10개 결정 표시
- `/decisions JWT` — "JWT" 키워드 포함 결정 검색
- `/decisions weavers-sso` — 특정 프로젝트 결정만
- `/decisions 7` — 최근 7일 결정

## 절차

### 1. 디렉토리 확인

```bash
DECISIONS_DIR="$HOME/Workspace/weaversbrain/weaversbrain/decisions"
[ ! -d "$DECISIONS_DIR" ] && echo "결정 기록 없음" && exit 0
```

### 2. 검색

인자 패턴별 처리:
- 인자 없음 → 최근 파일 10개 (`ls -t | head -10`)
- 숫자 → 최근 N일 (`find ... -mtime -N`)
- 문자열 → 파일명 + 본문 grep (Grep 도구로)

### 3. 결과 출력

각 결정에 대해:
- 파일 경로 (Obsidian URI: `obsidian://open?vault=weaversbrain&file=decisions/...`)
- 날짜·시간·프로젝트·에이전트
- 결정 본문 (요약 첫 3줄)

```markdown
## 검색 결과: {N}건

### 1. {프로젝트} — {토픽} ({날짜})
- 에이전트: {agent_type}
- 결정:
  > {첫 번째 결정 라인}
  > {두 번째 결정 라인}
- 열기: `obsidian://open?vault=weaversbrain&file=decisions/{파일명(확장자제외)}`

### 2. ...
```

### 4. 인덱스 표시

`INDEX.md` 가 있으면 첫 20줄 함께 표시 (전체 인덱스 확인용).

## 통합 활용

- 새 작업 시작 전 `/decisions {토픽}` 으로 과거 동일 토픽 결정 확인
- 리뷰어에게 컨텍스트 전달 시 관련 과거 결정 첨부
- 분기별 회고 시 `/decisions 90` 으로 분기 결정 모음

## 주의

- 결정 기록은 `decision-capture.sh` 훅이 자동 추출 (정확도 100%는 아님)
- 노이즈 결정(잘못 캡처) 발견 시 파일 직접 삭제
- 중요한 결정은 INDEX.md 에서 제목 수동 수정 권장
