# 참고 — LLM 위임 효과 측정 지표

> CLAUDE.md 본문에서 분리. 룰(자동 위임 트리거 표)은 CLAUDE.md 에 유지, 측정 방법론은 여기.

## 실측 근거 (시계열)

- **2026-05-25**: 14일 사용량 Claude 99.5% / Codex 0.7% / Gemini 0.05%. 위임 hook 이 권유만 하던 시기. **50줄+ Edit/Write 차단형(exit 2) 전환 동기** — 우회 키워드 "직접 구현해" / "직접 작성해"
- **2026-06-07**: moai-adk v2.14.0 도입(5/25~) 후 Codex 세션 ~16/일 → ~8/일 반감. moai workflow 가 Codex/Gemini 위임을 내부 Claude 에이전트(manager-tdd/expert-backend)로 흡수했지만 명시적 외부 위임 트리거 부재. moai workflow 진입 시에도 외부 위임 트리거 표 적용 결정. `/usage 7` 회복 확인 권고

## 지표 (2026-06-01 재설계)

### 주지표 = 조건 충족률 (비율 아님)

"위임 트리거 조건(50줄+ 구현 / 신규파일 100줄+ / 3파일+ 조사 / 세컨드오피니언·리뷰)이 발생했을 때 실제로 위임됐는가" 의 충족률.

단순 질의·짧은 패치까지 위임 강요하지 않으므로 전체 Claude 비율 99%대는 정상일 수 있음.

### 참고지표

- 주간 `/usage` 로 Codex/Gemini 누적 토큰·호출 추세 (절대 비율 목표 아님)
- 실측 14일: Codex 104회 / Gemini~agy 30회 — 위임 인프라 작동 중

### 폐기 지표

- ~~"Claude 70%" 절대 비율 목표~~ (측정 지표로 부적절, 14일 미동 확인 2026-06-01)

## 위임 우회 조건 (정당한 직접 작성)

다음 경우만 50줄+ 직접 작성 허용 (위임 hook 우회 시 사용자 확인):

- 사용자가 명시적으로 "직접" 키워드 사용
- 긴급 hotfix (5분 내 운영 복구 필요)
- 1줄짜리 반복 패턴 (예: import 50개 일괄 정리 — 이건 codemod 가 더 빠름)
- Claude 의 판단/통합/최종 정리 단계 (Codex 결과물 머지)

## 관측 인프라

- `hook-outcomes/*.jsonl` 누적 — `/hook-health [N일]` 로 집계
- 위임 hook 3종 (`delegation-enforcer`, `error-codex-remind`, `gemini-dependency-impact`) outcome_log 계측 완료 (커밋 a6196d2)
- 새 LLM hook 은 outcome_log 필수

**관련 메모**: [[llm-observability-map]]
