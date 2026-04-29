# dev-data-collector — metrics

수집 지표 카탈로그. 새 지표 추가 시 Python 스크립트의 `aggregate()` / `render_markdown()` 동기화.

## 1. 커밋 지표

| ID | 설명 | 구현 |
|---|---|---|
| `total_commits` | 전체 커밋 수 | `git log --no-merges` 기반 카운트 |
| `total_insertions` | 전체 추가 라인 | `--numstat` 합산 |
| `total_deletions` | 전체 삭제 라인 | `--numstat` 합산 |
| `commits_by_repo` | 레포별 커밋 | 레포 루프 |
| `commits_by_group` | 프로젝트 그룹별 | `PROJECT_GROUPS` 매칭 |

## 2. 커밋 유형 분포

Conventional Commit prefix (대소문자 무시) 기준:

- `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `build`, `ci`, `perf`, `style`, `revert`
- 매칭 안 되면 `other`
- 정규식: `^(feat|fix|refactor|...)(\(|:|!)`

## 3. 커밋 메시지 언어 분포

- `ko`: 한글만
- `en`: 영문만
- `mixed`: 한글+영문 혼재
- `other`: 둘 다 없음 (이모지·숫자·기호 등)

## 4. 리듬

- 시간대: commit timestamp의 `hour` (로컬 타임존 반영 안 함 — `aI` 그대로)
- 요일: Monday=0..Sunday=6
- 월별: `YYYY-MM`

## 5. 파일 지표

- `file_change_counter`: `레포::파일경로` → 변경 횟수
- TOP-20 파일 출력
- 테스트 파일: `TEST_FILE_PATTERNS` fnmatch
- 문서 파일: `DOC_FILE_PATTERNS` fnmatch
- CI 파일: 경로 prefix 기반 (`.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`, `Jenkinsfile`, `.buildkite/`)
- 의존성 파일: `DEPS_FILES` 파일명 정확 일치

## 6. 파일 오버랩 (협업 시그널)

- 내가 건드린 파일 중 **동기간 타인 커밋이 있는 파일**
- 타인 = 저자 이메일이 다른 경우
- 출력: 레포 · 파일 · 내 커밋 수 · 타인 커밋 수 · 타인 이메일 목록
- 주의: 레포당 `git log` 추가 1회. 전체 100+ 레포 스캔 시 수 분 걸릴 수 있음

## 7. PR 지표 (GitHub)

- `gh` CLI 필요
- 쿼리는 `search/issues` API 사용 (GraphQL 대신)
- `since..until`은 ISO 날짜

## 8. Obsidian 활동

- Daily 노트 수: 파일명 앞 10글자가 기간 범위 내
- 단어 수: `text.split()` 기반 (대략값)
- Weekly: 파일명에 `weekly` 포함되는 노트 수

## 9. 재현 가능성 메타

스크립트가 출력에 기록:
- 저자 필터
- 스코프 패턴
- 기간 (ISO)
- 스캔한 레포 수 / 활성 레포 수
- 실제 사용된 git 명령 템플릿

## 지표 추가 가이드

1. `dev-data-collector.py`의 `aggregate()`에 수집 로직 추가
2. `render_markdown()`에 출력 섹션 추가 (기존 번호 바꾸지 말 것 — 기존 snapshot과의 파싱 호환성)
3. `schema.md`에 섹션 스펙 추가
4. 필요하면 sidecar JSON에도 기록
