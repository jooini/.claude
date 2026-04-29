---
name: save-history
description: 현재 세션의 작업 내용을 구조화된 히스토리 문서로 저장합니다.
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(basename *), Bash(date *), Bash(ls *), Read, Write, Glob
---

# save-history

현재 세션의 작업 내역을 Obsidian Vault에 저장한다.

## 실행 절차

### 1단계: 정보 수집 (병렬)

```bash
basename $(pwd)
git branch --show-current
git log --oneline --since="00:00" --format="%h %s"
git diff --stat HEAD~$(git log --oneline --since="00:00" | wc -l)..HEAD 2>/dev/null
git status --short
```

### 2단계: 대화 컨텍스트 분석

현재 대화에서 추출:
- 작업 목록 + 완료 여부
- 발생 이슈 + 해결 방법
- 미해결 사항 / 다음에 할 일

### 3단계: 태그 생성

파일명, 작업 내용, 프로젝트에서 관련 태그를 생성한다. 아래 태그 풀에서 선택:

| 카테고리 | 태그 |
|---------|------|
| 주제 | api, auth, database, docker, infra, frontend, backend |
| 활동 | debugging, deployment, migration, review, testing, integration |
| 성격 | architecture, guide, performance, security, fallback |
| 도구 | keycloak, sdk, nginx, terraform |

- 최소 2개, 최대 6개
- `session` 태그는 항상 포함
- 내용과 무관한 태그는 넣지 않는다

### 4단계: 문서 생성

경로: `~/Workspace/weaversbrain/weaversbrain/Sessions/YYYY-MM/YYYY-MM-DD-{프로젝트명}.md`
(같은 날 같은 프로젝트 파일 존재 시 `-2`, `-3` 증번)

```markdown
---
date: "YYYY-MM-DD"
project: {프로젝트명}
type: session
tags: [{태그1}, {태그2}, session]
---

# {주요 작업 제목}

**프로젝트:** `{프로젝트 경로}` | **브랜치:** `{브랜치명}`

## 작업 요약

| # | 작업 | 상태 |
|---|------|------|
| 1 | {작업 내용} | 완료 / 진행 중 |

## 상세 내역

### 1. {작업 제목}

**변경 파일:**
- `path/to/file.py` — 변경 설명

**핵심 변경:**
```diff
+ 추가된 코드
- 삭제된 코드
```

## 커밋

```
{hash} {커밋 메시지}
```

## 이슈 및 해결

| 이슈 | 원인 | 해결 |
|------|------|------|
| {이슈} | {원인} | {해결} |

(없으면 "없음")

## 미해결 / TODO

- [ ] {미완료 작업}

(없으면 "없음")
```

### 5단계: 저장 확인

1. 파일 저장
2. 저장 경로 + 핵심 요약 3줄 출력

## 주의사항

- 실제 한 작업만 기록. 추측 금지.
- 코드 전체 복사 금지. 핵심 diff만 간결하게.
- 민감 정보 (SSH 키, IP, 토큰 등) 마스킹.
- frontmatter 필드에 따옴표 사용하지 않는다 (date 제외).
