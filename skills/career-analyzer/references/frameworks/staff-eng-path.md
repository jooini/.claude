# framework — staff-eng-path

Will Larson의 *Staff Engineer* 책 기준 4대 archetype으로 포지셔닝 분석.

## Archetypes

| archetype | 설명 | portrait에서 보는 시그널 |
|---|---|---|
| Tech Lead | 팀 단위 기술 방향 결정 | 특정 그룹에 집중된 commits, PR review 많음, docs 비중 높음 |
| Architect | 시스템 전체 구조 | 여러 그룹 걸친 commits, ADR/문서, CI·인프라 변경 |
| Solver | 난제 해결사 | refactor·fix 비중 높음, 여러 레포 crash-fix, 파일 TOP에 장기 파일 |
| Right-Hand | 리더 오른팔 | 커뮤니케이션 산출물(Obsidian/docs) 많음, 크로스팀 PR review |

## 구조

```markdown
---
date: "YYYY-MM-DD"
type: staff-eng-path
label: "{label}"
audience: "internal | external"
source_portrait: "{label}-portrait.md"
tags: [staff-engineer, career]
---

# Staff Engineer Path — {label}

## 1. Current Archetype Mix
(4개 archetype에 대한 현재 비중 — 수치 근거 필요)

| archetype | 비중 추정 | 근거 수치 (source: portrait §N) |
|---|---|---|
| Tech Lead | X% | commits in {group} Y%, PR reviews Z |
| Architect | ... | ... |
| Solver | ... | ... |
| Right-Hand | ... | ... |

## 2. Dominant Archetype & Gap
- 현재 우세 archetype: {X}
- Staff 승진에 필요한 archetype: {Y}
- Gap: 어떤 시그널이 부족한가

## 3. Scope 평가
- 개인 / 팀 / 여러 팀 / 조직 중 어디인가?
- 근거: portrait §9 (그룹 수), §4 (오버랩), §3 (PR review-received)

## 4. Impact 평가
- Activity → Outcome 변환 (impact-templates.md 참조)
- 측정 가능한 비즈니스 결과가 있는가?

## 5. Sponsorship 상태
- 누구에게 내 작업이 보이는가 (portrait §4 오버랩, §3 PR reviewed-by)
- 공개 산출물 수 (Obsidian weekly, 문서 변경)

## 6. 다음 분기 Staff-oriented 과제
- 현재 archetype mix를 Y로 이동하기 위한 3~5개 Goal
- 각 Goal은 portrait에서 측정 가능해야 함
```

## 작성 규칙

- archetype 비중은 **수치 근거 2개 이상** 필수
- "Staff 레벨이다/아니다" 단정 금지. 현 archetype과 gap만 서술
- external audience에서는 archetype 이름 그대로 유지 (업계 표준 용어)
- Scope 평가는 portrait §9에 있는 그룹 수·오버랩에 근거

## 주의

이 프레임워크는 **승진 준비 시 자료**로 쓰기 좋지만, "지금 Staff 준비 돼 있다" 같은 결론은 회사 맥락(reporting line, stakeholder 평가) 없이 말할 수 없다. 문서 마지막에 "이 프레임워크는 self-signal이며 조직 내 평가를 대체하지 않는다" 명시.
