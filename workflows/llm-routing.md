# LLM 라우팅 규칙

세 LLM(Gemma/Gemini/Codex)을 언제 어떻게 호출할지 정의. CLAUDE.md "도구 역할 분담" 섹션의 상세 매핑.

---

## Gemma (로컬 Ollama, leonard.local:11434)

**역할**: 프라이빗·로컬·빠른 브레인스토밍 담당

**다음 상황에서 반드시 활용**:
- 세컨드 오피니언이 필요한 판단/설계 결정
- 민감 데이터(사내/고객 정보) 포함 질의 — 외부 API 차단 대상
- 간단한 아이디어 발산/브레인스토밍 초기 단계
- 오프라인/프라이빗 질의
- 코드 리뷰 보조 및 설명 생성 (외부 전송 부적합)

**호출 방법**: `/ask-gemma` 스킬 또는 `Skill(ask-gemma)` 직접 사용

---

## Gemini / Antigravity CLI (1M 토큰 컨텍스트) — Phase 0 필수

> **2026-06-18 전환**: 무료/Pro/Ultra 사용자 대상 `gemini` CLI 요청 처리 종료 → **Antigravity CLI (`agy`)** 가 새 기본값.
> `settings.json` env에 `GEMINI_CLI=agy` 지정. 모든 호출 지점은 `${GEMINI_CLI:-agy}` 또는 wrapper(`~/.claude/scripts/gemini-wrapped.sh`)를 통해 자동 전환됨.
> 엔터프라이즈 API 키 사용자는 기존 `gemini`를 `GEMINI_CLI=gemini`로 계속 사용 가능.
> **호환성 차이**: `agy`는 `--output-format stream-json` 미지원 → 토큰 메타 로깅 불가. wrapper가 duration/exit_code만 기록.

**역할**: 광범위 스캔·영향 분석

**다음 상황에서 반드시 먼저 호출**:
- 코드 구조/아키텍처/의존성 파악 (문서 작성 포함)
- 대규모 코드베이스 스캔 — 3파일 이상 수정·리팩터·영향 범위 분석
- 업그레이드/마이그레이션 영향 분석 (의존성 변경, 프레임워크 버전 전환)
- 3중 리뷰 (code-reviewer + codex + gemini 병렬)
- 최종 통합 검증
- UI/스크린샷 분석, 문서 요약

**호출 방법**: `/ask-gemini` 스킬 또는 `Skill(ask-gemini)` 직접 사용

**Phase 0 규칙**: 결과는 파일 저장 후 요약만 메인 컨텍스트에 전달 (전문 주입 금지)

**금지**:
- 3파일 이상 수정하면서 Gemini 스캔 건너뛰기
- Grep/Read만으로 구조 파악 끝내기

---

## Codex (CLI 또는 MCP)

**역할**: 구현·패치·세컨드 오피니언

**다음 상황에서 호출**:
- 구현 대안 검증
- 에러/버그 다른 관점 분석
- 패치 초안 검토
- Claude 수정안의 세컨드 오피니언

**호출 방법**: `/ask-codex` 스킬 또는 `codex exec` CLI (MCP 미사용 — 2026-05-30)

---

## 3중 LLM 병렬 활용 (큰 결정/비교/마이그레이션)

큰 결정 시 항상 3중 호출 후 결과 통합:
- Gemini (1M 컨텍스트, 광범위 분석)
- Codex (세컨드 오피니언, 다른 관점)
- Gemma (로컬 빠른 검증)

→ 시간 압축: `run_in_background: true` 또는 한 메시지에 동시 호출

---

## 역할 분담 요약

| LLM | 강점 | 사용처 |
|-----|------|--------|
| **Gemini** | 1M 토큰 컨텍스트 | 광범위 스캔, 영향 분석 |
| **Codex** | 코드 특화 | 구현, 패치, 세컨드 오피니언 |
| **Gemma** | 로컬, 프라이빗, 빠름 | 민감 데이터, 브레인스토밍 |
