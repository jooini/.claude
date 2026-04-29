# 개발 성장 원칙

본인 개발 성장을 강제하는 자동화 룰. 매 작업에 적용.

## 학습 자동화

- **모르는 개념 발화 시** → `learning-queue-capture.sh` hook이 자동 큐 추가
- **세션 종료 시** → `daily-learning-capture.sh` hook이 학습 노트 자동 생성
- **매주 일요일 14시** → `/deep-learn queue` 자동 실행 권장
- **모든 큰 결정 전** → `Skill(deep-research)` 의무 (마이그레이션/아키텍처)

## 답변 시 학습 모드 (질문성 발화일 때)

사용자가 "X가 뭐야?", "어떻게 동작?", "왜?" 발화 시 단순 답 금지. 다음 형식:

1. **한 줄 요약**
2. **핵심 원리** (왜 그렇게 동작)
3. **유사 개념과의 차이**
4. **함정/주의점** (실전)
5. **공식 문서 링크** (가능하면)

## 3중 LLM 활용 (성장 + 검증 동시)

큰 결정/비교/마이그레이션 시 **항상**:

- Gemini (1M 컨텍스트, 광범위 분석)
- Codex (세컨드 오피니언, 다른 관점)
- Gemma (로컬 빠른 검증)

→ 결과 통합 = 본인 학습 + 의사결정 품질

상세: `workflows/llm-routing.md`

## 회고 강제

- 매일: `/done` 으로 일일 보고서
- 매주 금요일 17시: `/retro 7` 자동 (학습 누적 분석)
- 매월: 학습 노트 메타 회고 (`Learning/concepts/` 검토)

## 결정 추적

- `decision-capture.sh` hook 자동 캡처
- `/decisions {검색어}` 로 과거 결정 검색
- 결정 시 **반드시 이유 명시** (자동 캡처용)

## 도메인 확장 권장

같은 스택 반복 = 정체. 매주 다른 영역 1시간:

- 시스템 (Rust/Go), AI/ML (임베딩), 알고리즘, 다른 언어
- 결과물 → `~/Workspace/weaversbrain/weaversbrain/Learning/portfolio/`

## 글쓰기 강제

배운 거 글로 정리. `~/Workspace/weaversbrain/weaversbrain/Posts/` 에 주 1회.
형식: 문제 → 시도 → 해결 → 일반화
