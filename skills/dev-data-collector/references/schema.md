# dev-data-collector — output schema

`portrait.md` 파일의 고정 스키마. Analyzer가 이를 파싱해서 해석을 만든다.

## Frontmatter

```yaml
---
date: "YYYY-MM-DD"                 # 생성 날짜
type: portrait                     # 고정
period: "YYYY-QN" | "YYYY" | "FROM_TO"
range: "YYYY-MM-DD..YYYY-MM-DD"
generated_at: "ISO8601"
generated_by: "dev-data-collector vX.Y"
tags: [portrait, retrospective, dev-data-collector]
---
```

## 섹션 순서 (변경 금지)

| § | 제목 | 내용 |
|---|---|---|
| 헤더 | `# Developer Portrait — {label}` | 기간·저자·총 커밋 |
| 1 | 레포별 커밋 볼륨 | 표: repo, group, commits, insertions, deletions, share |
| 2 | 작업 유형 분포 | 표: type, commits, share |
| 2.1 | 커밋 메시지 언어 분포 | 표: language, commits, share |
| 3 | PR & 리뷰 활동 | 리스트 or "gh 없음" |
| 4 | 파일 오버랩 | 표: repo, file, my_commits, others_commits, others_authors (TOP 20) |
| 5 | 파일 TOP-20 | 표: repo, file, touches |
| 6.1 | 요일별 리듬 | 표: weekday, commits |
| 6.2 | 시간대별 리듬 | 표: hour, commits |
| 6.3 | 월별 리듬 | 표: month, commits |
| 7 | 메타 자산 | 리스트: 문서/테스트/CI/의존성 변경 카운트 |
| 8 | Obsidian 활동 | 리스트: Daily 수, 단어 수, weekly 수 |
| 9 | 프로젝트 그룹별 요약 | 표: group, commits, ins, del, share, repos |
| 10 | 원본 데이터 출처 | 재현용 git 명령 템플릿, 저자 필터, 스코프 |

## JSON Sidecar (`{label}-portrait.json`)

프로그램 파싱용. Analyzer가 표를 파싱하지 않고 이 JSON을 읽어도 됨.

```json
{
  "label": "2026-Q2",
  "since": "2026-04-01",
  "until": "2026-06-30",
  "author": "is.joo@speakingmaxapp.com",
  "scope": null,
  "total_commits": 0,
  "by_group": {"identity-hub": {"commits": 0, "ins": 0, "del": 0, "repos": []}},
  "type_counter": {"feat": 0, "fix": 0},
  "lang_counter": {"ko": 0, "en": 0},
  "meta": {"test_file_changes": 0, "doc_file_changes": 0, "ci_file_changes": 0, "deps_file_changes": 0},
  "obsidian": {"daily_notes": 0, "total_words": 0, "reports_weekly": 0},
  "github": {"available": false}
}
```

## 호환성 정책

- 기존 섹션 번호·제목 **변경 금지** (Analyzer parser 깨짐)
- 신규 섹션은 **끝에 추가** (§11, §12...)
- 표 컬럼은 **추가는 끝에**, 기존 컬럼 이름/순서 유지
- 호환성 깨뜨릴 변경이 불가피하면 schema 버전 업 (`generated_by` 필드에 반영)
