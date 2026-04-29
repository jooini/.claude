# framework — external (면접/공개용 self-assessment)

외부 공유용 자가 평가. 회사명·레포명·팀원 익명화. 이직/면접/블로그 seed.

## 구조

```markdown
---
date: "YYYY-MM-DD"
type: assessment-external
label: "{label}"
audience: external
source_portrait: "{label}-portrait.md"
tags: [self-assessment, external]
---

# Self-Assessment — {label} (external)

## Context
- 재직 중인 조직 규모, 역할, 주요 도메인 (2~3줄. 회사명 없이)

## 지난 {period}에 한 일
- 도메인 X에서 Y를 deliver (수치, 규모) — (source: portrait §N)
- 도메인 A의 레거시를 B로 마이그레이션 (수치) — (source: portrait §N)
- ...

## 사용한 기술
- 언어·프레임워크·도구 (portrait §9 그룹에서 추론)

## 성장한 영역
- 이번 기간 동안 처음 다룬 것 / 깊어진 것 (근거 수치)

## 다음에 하고 싶은 것
- 배우고 싶은 영역, 맡고 싶은 역할 (focus-areas와 정렬)

## 근거 요약 (익명화된 metrics)
- 커밋 N, PR N, 도메인 수 M, ...
```

## Redaction 체크리스트 (작성 전 필수)

- [ ] 회사명 모두 제거 (weaversbrain, speakingmax 등)
- [ ] 레포명 일반화 (`identity-hub` → "SSO platform")
- [ ] 팀원 실명 → 역할명
- [ ] 사내 URL → 도메인 마스킹 or 제거
- [ ] 커밋 SHA 제거
- [ ] Jira/Issue 번호 제거
- [ ] 고객/파트너 회사명 제거

## 작성 톤

- 과장 금지. "큰 규모" 같은 형용사보다 수치.
- 단정 금지. "운영 경험", "담당 경험" 같은 중립 표현.
- 이전 사이클 대비 변화가 있으면 우선 표시 ("X에서 Y로 확대").

## 공개 발행 전 체크포인트

1. `redaction-rules.md`로 자동 스캔
2. 사람이 1회 더 리뷰
3. 고용주 공개 정책 확인 (NDA 범위)
