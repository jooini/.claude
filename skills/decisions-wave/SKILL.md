---
name: decisions-wave
description: Decision Wave Tracker — claude-mem 7912 observations에서 결정 추출 → 시간축 토픽 wave + 번복 그래프. 같은 토픽이 여러 번 등장하면 결정 강화/번복 가능성 자동 감지.
---

# Decision Wave Tracker

`~/.claude-mem/claude-mem.db` 의 7912 observations 에서 결정 시그널만 추출하여 토픽별 시간축 wave 분석.

## 검출 시그널

**키워드** (영어+한국어):
- decision / selected / chose / rejected / instead of / switched / reverted / adopted / replaced / deprecated / migrated
- 채택 / 기각 / 번복 / 결정 / 선택 / 전환 / 롤백

**번복 패턴** (정규식):
- `switched to X (from|instead of) Y`
- `instead of X`
- `reverted X`
- `(deprecated|removed) X`

## 분석 차원

1. **토픽 wave**: 같은 토픽(Identity Hub / Keycloak / SSO / FastAPI 등)이 시간차 두고 N번 등장
2. **명시적 번복**: 정규식 매칭된 reversal/replace 신호
3. **프로젝트 분포**: 어디서 결정이 자주 일어나나

## 사용법

- `/decisions-wave` — 분석 + 리포트
- `/decisions-wave show` — 즉시 출력

## 출력

- `~/.claude/cache/decision-wave.md`
- `~/.claude/cache/decision-wave.json`

## 진짜 가치

- `/decisions` 는 **개별 결정**을 본다
- `/decisions-wave` 는 **결정의 강도와 일관성**을 본다
- 토픽 wave 5+ 는 "이 주제에서 자주 의사결정 흔들림" → 설계 미정착 신호

## 다른 도구와 시너지

- `/witness "토픽명"` 과 통합: wave가 있는 토픽으로 과거 사용자 정정 검색
- `/self-model` 의 "추정→정정" 패턴과 wave 토픽 교차 검증

## 한계

- 키워드 휴리스틱 — LLM 의미 분석 아님
- 토픽 추출은 대문자 명사 + 따옴표 위주 (놓치는 케이스 있음)
- 번복이 진짜 모순인지 정상 진화인지 자동 판별 못함
