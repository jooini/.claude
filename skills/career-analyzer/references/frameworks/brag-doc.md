# framework — brag-doc

Julia Evans 스타일 "brag document". LinkedIn post, resume bullet, 컨퍼런스 CFP 초안 seed.

## 철학

자기 업적을 **짧은 bullet**로 정리. 기억보다 기록에 의존. 분기마다 쌓아서 이직/리뷰 시 seed로 사용.

## 구조

```markdown
---
date: "YYYY-MM-DD"
type: brag-doc
label: "{label}"
audience: "internal | external"
source_portrait: "{label}-portrait.md"
tags: [brag-doc]
---

# Brag Doc — {label}

## Shipped
- [Project] 한 줄 성과 (수치) — (source: portrait §N)
- ...

## Impact
- 내 작업으로 X가 Y% 변했다 (수치 근거) — (source: portrait §N)
- ...

## Cross-functional
- 누구와 협업했고 뭘 얻었다 (파일 오버랩 근거) — (source: portrait §4)
- ...

## Tech Growth
- 새로 배우거나 깊어진 기술 (근거: 레포·언어·커밋 유형)
- ...

## Mentoring / Leadership
- 리뷰·문서·멘토링 활동 (PR reviewed-by count, 문서 변경 수)
- ...

## Speaking / Writing / Public
- 공개 발표, 블로그, OSS 기여 (Obsidian weekly 수, 공개 PR)
- ...
```

## Bullet 작성 규칙

- **Subject + Verb + Object + Outcome** 순서
- Outcome 수치 필수 (정량 or 정성)
- 5~20단어
- 동사는 과거형·능동태 ("Shipped X", "Reduced Y", "Led Z")
- **금지**: "helped", "worked on", "assisted" 같은 모호한 동사

## 예시 (leonard 맥락)

### 좋은 예
- `Shipped identity-hub-frontend v16 migration, +6286 / -726 lines, 15 commits in 1 week (source: portrait §1)`
- `Reduced SSO callback error rate by gating duplicate auth code exchange (commit c3be846-e23696e) (source: portrait §5)`

### 나쁜 예
- `Worked on SSO things` (Subject-only, 수치 없음)
- `Helped team ship a lot of stuff` (모호, 과장)

## External audience (`--audience=external`)

`redaction-rules.md` 적용:
- `identity-hub*` → "SSO platform"
- `maxai-*` → "EdTech platform"
- 팀원 실명 → "backend engineer", "frontend engineer"
- 사내 URL 도메인 마스킹
- 커밋 SHA 제거 (bullet 뒤 주석만)

## Tech Growth 섹션 가이드

portrait §2 작업 유형 분포 + §9 프로젝트 그룹별 요약을 교차해서:
- `feat`+`refactor` 비중이 높은 그룹 → "{그룹} 도메인 작업량 증가"
- 새로 등장한 그룹(이전 snapshot에 없던) → "새 영역 진입"
- 언어 분포(portrait §2.1)가 바뀌었다면 "커뮤니케이션 축 이동"
