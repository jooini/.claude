# framework — performance-cycle

기본 프레임워크. 업계 perf review (Google PSC / Meta PSC / Amazon annual)와 정합되는 구조.

## 섹션 구조

출력 파일 구조 (순서 고정):

```markdown
---
date: "YYYY-MM-DD"
type: performance-cycle
label: "{label}"
prev: "{prev_label or null}"
audience: "internal | external"
source_portrait: "{label}-portrait.md"
tags: [performance-cycle, retrospective]
---

# Performance Cycle — {label}

## 1. Executive Summary
- 한 줄 요약 (사이클 전체 톤)
- 지난 사이클 대비 톤 변화 (prev 있을 때)

## 2. 지난 과제 달성률
(이전 사이클 goals §7에서 추출 → 현재 수치로 자동 점검. Hit/Partial/Miss)

### Goal 1: {title}
- 기준값 / 목표값 / 현재값
- 달성률: X%
- 분류: ✅ Hit / 🟡 Partial / ❌ Miss
- (Partial/Miss 시) 원인 분석 1~2줄

## 3. 강점 (지난 대비 변화 포함)
- {강점 1} — 근거 수치 (source: portrait §N) · 지난 대비 유지/강화/약화

## 4. 약점 (지난 대비 변화 포함)
- {약점 1} — 근거 수치 (source: portrait §N) · 지난 대비 개선/정체/악화

## 5. 업무 스타일 시그니처
- {관찰 패턴}: 예) refactor 비중 X%, 문서 변경 Y건, 요일 편중 …

## 6. 역할의 범위
- 현재 포지션 맵: 개인 기여자 / 프로젝트 리드 / 크로스팀 / …
- Scope 증가/감소 근거 (source: portrait §N)

## 7. 다음 사이클 과제 (Goals)
(SMART 형식. goals-tracking.md 참조)

### Goal: {title}
- 근거 focus-area: {파일·섹션}
- 측정 지표: {metric_id from metrics.md}
- 기준값 (baseline): {현재 snapshot 값}
- 목표값 (target): {다음 사이클까지 목표}
- 타입: 정량 / 정성
```

## 작성 규칙

- **모든 단정 문장** 뒤 `(source: portrait §N)` 또는 `(source: prev §N)` 주석
- 강점/약점은 **이전 대비 변화**로 표현 (없으면 현재만, "지난 대비" 생략)
- §2 지난 과제 달성률은 **이전 사이클의 §7 Goals**을 입력으로 받아 계산
- §7 신규 Goals은 `Plans/focus-areas-*.md`의 체크포인트에서 3~5개 추출
- 같은 goal을 연속 2회 Miss하면 원인을 묻는 섹션을 반드시 추가 (`## 2.x 연속 미달 분석`)

## Partial/Miss 원인 분석 체크리스트

- 우선순위가 바뀌었나? (focus-areas 갱신 여부)
- 측정 지표가 현실과 맞았나? (metrics.md 수정 필요?)
- 일정 자체가 비현실적이었나?
- 외부 요인(팀·고객·시장) 변경?

## 연속 2회 Miss 이후 정책

1회 더 재설정보다 **goal 포기 + 다른 영역 교체** 권장. narrative에 "이번 사이클에서 goal X는 포기한다. 이유: {이유}. 대신 Y로 교체한다" 명시.

## 톤 가이드

- 직설적·수치 중심. 자기 홍보/자기 비판 최소화.
- 비교 표현은 OK ("2.7배 많다"). 가치 판단은 소수 (" 과하다/부족하다"). 이유 없으면 비교만 남기고 판단 생략.
- external 버전은 redaction 후 회사명·레포명·팀원 실명 모두 익명화.
