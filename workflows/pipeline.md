# 에이전트 파이프라인 상세

> CLAUDE.md에서 `@~/.claude/workflows/pipeline.md` 로 참조됨.
> 파이프라인 키워드(backend, frontend 등) 지정 시에만 이 문서를 로드한다.

## Phase 0: Gemini 스캔 (2-pass 분석)

> 모든 파이프라인의 최초 단계. S 규모에서도 실행.
> Gemini CLI의 1M 토큰 컨텍스트를 활용해 대규모 코드베이스를 한 번에 스캔.

### 실행 방법

```bash
# 프로젝트 디렉토리에서 실행. 대상 경로와 질문을 상황에 맞게 조정.
gemini -p "다음 코드베이스를 분석하고 요약해줘:
1. 디렉토리 구조와 주요 모듈
2. 수정 대상 파일들의 현재 구현 상태
3. 관련 의존성과 호출 관계
4. 잠재적 영향 범위
대상: [수정 대상 파일/디렉토리 경로]" < <(find [대상경로] -type f \( -name '*.py' -o -name '*.ts' -o -name '*.php' -o -name '*.java' -o -name '*.kt' \) | head -200 | xargs cat)
```

### 결과 활용
- Gemini 스캔 결과를 `gemini_scan` 변수로 저장
- 이후 모든 단계(researcher, planner, developer)의 프롬프트에 컨텍스트로 주입
- Claude Code는 Gemini 요약을 기반으로 **깊은 추론/분석**에 집중 (전체 스캔 중복 금지)

### 규모별 Gemini 스캔 범위

| 규모 | 스캔 범위 | 질문 초점 |
|------|----------|----------|
| **S** | 수정 대상 파일 + 직접 의존 파일 | 현재 구현 상태, 호출자/피호출자 |
| **M** | 수정 대상 모듈 전체 | 모듈 구조, 의존 관계, 테스트 커버리지 |
| **L** | 프로젝트 전체 (또는 관련 패키지 전체) | 아키텍처 개요, 모듈 간 결합도, 영향 범위 |

## 규모 판별

| 규모 | 기준 | 적용 |
|------|------|------|
| **S** | 수정 대상 파일 1~2개 | Gemini 스캔 → developer (researcher·planner 생략) |
| **M** | 수정 대상 파일 3~5개 | Gemini 스캔 → researcher 심화 분석 |
| **L** | 수정 대상 파일 6개+ 또는 아키텍처 변경 | Gemini 스캔 → researcher + planner 필수 |

### 자동 판별

`auto-scale-detect.sh` 훅이 UserPromptSubmit 시 git diff 변경 파일 수를 카운트하여 `[규모 자동 판별] X — 변경 파일 N개` 컨텍스트를 주입한다.
- 사용자가 "L 규모로", "S 규모로" 명시 시 자동 판별 스킵 (사용자 의도 우선)
- 아키텍처 키워드(아키텍처/architecture/모듈 분리/breaking change) 감지 시 무조건 L
- 변경 파일 0건 시 "S(추정)" — 신규 작업으로 간주

## backend 파이프라인

> 트리거: "backend", "백엔드"

0. **Gemini 스캔** → 코드베이스 초기 분석 (결과를 이후 단계에 컨텍스트로 전달)
1. **(M/L)** researcher(general-purpose) → Gemini 스캔 결과 기반 심화 분석
2. **(L)** planner(Plan) → Gemini + researcher 결과 기반 구현 전략
3. 병렬 구현:
   - developer(backend-developer) → 코드 작성
   - **(M/L)** codex:parallel-impl → 동일 태스크 대안 구현 (developer와 비교용)
   - **(M/L)** Gemini 테스트 생성 → 구현 대상의 테스트 코드 선행 작성
4. **(M/L)** 구현 비교: developer vs codex 결과 중 최선안 채택 (Claude Code가 판단)
5. 병렬: tester(code-tester) → lint/build/test + Gemini 엣지케이스 테스트 생성 (실패 시 3→5 반복, 최대 3회)
   - **3→5 루프 3회 실패 시**: codex:rescue foreground로 자동 에스컬레이션
   - Gemini 생성 테스트는 tester 통과 후 추가 실행
6. Gemini 리뷰 프리스캔 → 전체 diff를 Gemini에 넘겨 broad issue 탐지
7. code-review-graph:review-delta → 영향 범위 분석
8. 병렬 리뷰: code-reviewer + codex:review(--wait) + Gemini 심층 리뷰 + **Gemma 프리스캔(로컬)** + qa + (조건부: ops-lead, superpowers:code-reviewer) — 6+7의 결과를 컨텍스트로 전달
   - **보안/DB 변경 포함 시**: codex:review 대신 codex:adversarial-review(--wait) 실행
   - Gemini 심층 리뷰: 변경 파일 + 관련 모듈 전체를 1M 컨텍스트로 로드하여 모듈 간 일관성/누락 검출
   - Gemma 프리스캔: 로컬 Ollama(`leonard.local:11434`, `gemma4:e4b`) 세컨드 오피니언. code-reviewer 호출 시 훅으로 자동 실행됨. 수동 호출 필요 시 `Skill(ask-gemma)`
9. 재수정 (최대 3회)
10. **Gemini 최종 통합 검증** → 전체 diff + 관련 파일을 한번에 로드, 파일 간 일관성/import 누락/타입 불일치 체크
11. 사용자 확인 → 완료 보고
12. API 변경 감지 시: `say -v Yuna "프론트랑 대화가 필요해요"`

## frontend 파이프라인

> 트리거: "frontend", "프론트"

0. **Gemini 스캔** → 코드베이스 초기 분석
1. **(M/L)** researcher → Gemini 스캔 결과 기반 심화 분석
2. **(L)** planner → Gemini + researcher 결과 기반 구현 전략
3. 병렬 구현:
   - developer(frontend-developer) → 코드 작성
   - **(M/L)** codex:parallel-impl → 동일 태스크 대안 구현
   - **(M/L)** Gemini 테스트 생성 → 컴포넌트/E2E 테스트 선행 작성
4. **(M/L)** 구현 비교: developer vs codex 결과 중 최선안 채택
5. 병렬: tester(code-tester) → lint/build/test + Gemini 엣지케이스 테스트 생성 (최대 3회)
   - **3→5 루프 3회 실패 시**: codex:rescue foreground로 자동 에스컬레이션
   - Gemini 생성 테스트는 tester 통과 후 추가 실행
6. Gemini 리뷰 프리스캔 → 전체 diff broad issue 탐지
7. code-review-graph:review-delta → 영향 범위 분석
8. 병렬 리뷰: code-reviewer + codex:review(--wait) + Gemini 심층 리뷰 + **Gemma 프리스캔(로컬)** + designer + qa + (조건부: superpowers:code-reviewer) — 6+7의 결과를 컨텍스트로 전달
   - **보안 변경 포함 시**: codex:review 대신 codex:adversarial-review(--wait) 실행
   - Gemini 심층 리뷰: 변경 파일 + 관련 모듈 전체를 1M 컨텍스트로 로드하여 모듈 간 일관성/누락 검출
   - Gemma 프리스캔: 로컬 Ollama 세컨드 오피니언. code-reviewer 호출 시 훅으로 자동 실행
9. 재수정 (최대 3회)
10. **Gemini 최종 통합 검증** → 전체 diff + 관련 파일 한번에 로드, 파일 간 일관성/import 누락/타입 불일치 체크
11. 사용자 확인 → 완료 보고

## fullstack 파이프라인

> 트리거: "fullstack", "풀스택"

0. **Gemini 스캔** → 프론트/백 코드베이스 동시 스캔 (1M 토큰으로 양쪽 한번에)
1. researcher 병렬 (프론트/백) → Gemini 스캔 결과 기반 심화 분석
2. planner → Gemini + researcher 결과 기반 통합 전략
3. 병렬 구현:
   - backend-developer + frontend-developer (Claude Code)
   - codex:parallel-impl → 백엔드 또는 프론트 중 핵심 모듈 대안 구현
   - Gemini 테스트 생성 → 프론트/백 테스트 선행 작성
4. 구현 비교: Claude vs Codex 최선안 채택
5. 병렬: tester → 프론트/백 각각 + Gemini 엣지케이스 테스트 생성 (최대 3회)
   - **3→5 루프 3회 실패 시**: codex:rescue foreground로 자동 에스컬레이션
   - Gemini 생성 테스트는 tester 통과 후 추가 실행
6. Gemini 리뷰 프리스캔 → 전체 diff broad issue 탐지
7. code-review-graph:review-delta → 영향 범위 분석 (프론트/백 각각)
8. 병렬 리뷰: code-reviewer + codex:review(--wait) + Gemini 심층 리뷰 + **Gemma 프리스캔(로컬)** + designer + qa + (조건부: ops-lead) — 6+7의 결과를 컨텍스트로 전달
   - **보안/DB 변경 포함 시**: codex:review 대신 codex:adversarial-review(--wait) 실행
   - Gemini 심층 리뷰: 변경 파일 + 관련 모듈 전체를 1M 컨텍스트로 로드하여 모듈 간 일관성/누락 검출
   - Gemma 프리스캔: 로컬 Ollama 세컨드 오피니언. code-reviewer 호출 시 훅으로 자동 실행
9. 재수정 (최대 3회)
10. **Gemini 최종 통합 검증** → 프론트/백 전체 diff + 관련 파일 한번에 로드, API 계약/타입 일관성 체크
11. 사용자 확인 → 완료 보고

## data 파이프라인

> 트리거: "data", "데이터", "쿼리"

0. **Gemini 스캔** → 관련 모델/쿼리/스키마/인덱스 전체 분석
1. data-analyst → Gemini 스캔 결과 기반 쿼리/분석 설계
2. 병렬:
   - tester → 실행 검증
   - codex:query-validate → 쿼리 성능/정합성 독립 검증
3. Gemini 리뷰 프리스캔 → 스키마 변경 영향 범위 탐지
4. code-review-graph:review-delta → 영향 범위 분석
5. 병렬 리뷰: code-reviewer + codex:review(--wait) + Gemini 심층 리뷰 + **Gemma 프리스캔(로컬)** → 성능/정확성 리뷰 (3+4의 결과를 컨텍스트로 전달)
   - **DB 스키마/마이그레이션 변경 시**: codex:adversarial-review(--wait) 추가 실행
   - Gemini 심층 리뷰: 스키마 전체 + 관련 쿼리/모델을 1M 컨텍스트로 로드하여 정합성 검증
   - Gemma 프리스캔: 로컬 Ollama 세컨드 오피니언. code-reviewer 호출 시 훅으로 자동 실행
6. **Gemini 최종 통합 검증** → 전체 변경사항의 스키마/쿼리/모델 일관성 체크
7. 사용자 확인

## product 파이프라인

> 트리거: "기획", "PRD", "요구사항"

1. po → PRD/요구사항 작성
2. 병렬: designer + qa → UI/UX + 수용 기준
3. 사용자 확인

## code-review-graph 연동

> 모든 파이프라인의 리뷰 단계에서 자동 적용

- **리뷰 전**: `code-review-graph:review-delta` 실행 → 변경된 코드의 영향 범위(impact radius) 분석
- **리뷰어에게 전달**: 분석 결과를 code-reviewer, qa 등 리뷰 에이전트 프롬프트에 컨텍스트로 포함
- **그래프 업데이트**: 편집/커밋 시 훅으로 자동 업데이트되므로 수동 빌드 불필요
- **수동 빌드**: 브랜치 전환, 대규모 리팩토링 후 `/code-review-graph:build-graph` 실행

## 조건부 에이전트

| 조건 | 추가 에이전트 |
|------|-------------|
| 설계 문서 존재 | superpowers:code-reviewer |
| Docker/CI/환경변수 변경 | ops-lead |
| UI 컴포넌트 변경 | designer |
| DB/쿼리 변경 | data-analyst |
| 기능 개발 완료 | po |
| 코드 변경 리뷰 시 | code-review-graph:review-delta |

## Gemini 통합 전략

### Phase 0 스캔 (필수, 전 규모)
- 모든 파이프라인 최초 단계에서 실행
- 결과를 이후 모든 단계에 컨텍스트로 전달
- Claude Code는 Gemini 요약 기반으로 동작 (전체 재스캔 금지)

### Gemini 테스트 선행 생성 (M/L 규모)
- developer 구현과 **병렬**로 Gemini가 테스트 코드 선행 작성
- 실행 방법:
  ```bash
  gemini -p "다음 기능에 대한 테스트 코드를 작성해줘:
  [기능 설명 + Gemini 스캔 결과에서 추출한 인터페이스 정보]
  테스트 프레임워크: [pytest/jest/phpunit 등 프로젝트에 맞게]
  기존 테스트 패턴을 따를 것." < <(cat [기존 테스트 파일들])
  ```
- developer가 작성한 코드에 맞게 Claude Code가 최종 조정

### Gemini 리뷰 프리스캔 (전 규모)
- 리뷰 단계 직전에 전체 diff를 Gemini에 넘겨 broad issue 탐지
- 실행 방법:
  ```bash
  gemini -p "다음 코드 변경사항을 리뷰해줘. 큰 문제점 위주로:
  1. 로직 오류 / 엣지 케이스 누락
  2. 성능 이슈
  3. 보안 취약점
  4. 기존 코드와의 일관성 문제" < <(git diff [base]..HEAD)
  ```
- 결과를 code-reviewer + codex:review 프롬프트에 컨텍스트로 포함
- Gemini 프리스캔은 넓고 얕게, code-reviewer/codex는 좁고 깊게

### Gemini 심층 리뷰 (3중 병렬 리뷰, 전 규모)
- code-reviewer, codex:review와 **병렬**로 실행
- 변경 파일 + 관련 모듈 전체를 1M 컨텍스트로 한번에 로드
- 개별 파일이 아닌 **모듈 간 일관성** 관점에서 리뷰 (Claude/Codex와 차별화)
- 실행 방법:
  ```bash
  gemini -p "다음 코드 변경사항과 관련 모듈 전체를 리뷰해줘:
  1. 변경된 파일 간 인터페이스 일관성
  2. 모듈 경계에서의 타입/계약 불일치
  3. 변경에 의해 영향받지만 수정되지 않은 파일
  4. 누락된 import/export/의존성
  변경사항:" < <(git diff [base]..HEAD && cat [관련 모듈 파일들])
  ```
- 결과를 재수정 판단의 입력으로 사용

### Gemini 최종 통합 검증 (전 규모, 신규)
- 모든 리뷰/재수정 완료 후, 사용자 확인 직전에 실행
- 전체 diff + 관련 파일을 한번에 로드하여 최종 점검
- 체크 항목: 파일 간 일관성, import 누락, 타입 불일치, API 계약 위반, 미완성 TODO
- 실행 방법:
  ```bash
  gemini -p "최종 검증: 다음 전체 변경사항에서 놓친 문제가 있는지 확인해줘:
  1. 파일 간 인터페이스 불일치
  2. 누락된 import/export
  3. 타입 불일치
  4. 미완성 TODO/FIXME
  5. 테스트에서 커버되지 않은 새 분기" < <(git diff [base]..HEAD)
  ```
- 문제 발견 시 재수정 루프 진입 (최대 1회 추가)

### Gemini 리팩토링 맵핑 (조건부)
- 대규모 리팩토링/마이그레이션 시 활성화
- 전체 코드베이스에서 변경 대상 패턴을 모두 찾아 목록화
- Claude Code가 실제 변환 로직을 설계하고 실행

## Codex 통합 전략

### codex:review (필수)
- code-reviewer와 **병렬 실행** (기존 순차 → 병렬로 변경)
- 모든 파이프라인의 리뷰 단계에서 자동 포함, 규모 무관

### codex:parallel-impl (M/L 규모, 신규)
- M/L 규모에서 developer와 **병렬**로 동일 태스크의 대안 구현 실행
- 실행: `codex -a "다음 태스크를 구현해줘: [태스크 설명 + Gemini 스캔 결과]" --write`
- developer 구현 완료 후 Claude Code가 양쪽 결과를 비교하여 최선안 채택
- 채택 기준: 코드 품질, 테스트 통과율, 기존 패턴 일관성

### codex:query-validate (data 파이프라인, 신규)
- data-analyst가 작성한 쿼리를 Codex가 독립적으로 검증
- 실행: `codex -a "다음 SQL 쿼리의 정합성/성능을 검증해줘: [쿼리]" --wait`
- 인덱스 활용, N+1 문제, 데드락 가능성 등 체크

### codex:adversarial-review (조건부)
- 다음 조건 중 하나 이상 해당 시 codex:review **대체** 실행:
  - 보안 관련 변경 (인증, 권한, 토큰, 암호화)
  - DB 스키마/마이그레이션 변경
  - 인프라/Docker/CI 변경
  - API 인터페이스 변경 (breaking change 가능성)

### codex:rescue (자동 에스컬레이션)
- developer→tester 루프 3회 실패 시 자동 트리거
- **foreground**로 실행 (background 금지 — 결과 수집 불가)
- Codex 결과 수신 후 tester로 재검증

### M/L 규모 듀얼 브레인 (기존 L → M/L로 확대)
- M/L 규모 작업에서 developer가 구현을 시작할 때:
  - codex:parallel-impl로 동일 태스크의 대안 구현을 병렬 실행
  - developer 구현 완료 후 양쪽 결과를 비교하여 최선안 채택
  - 채택되지 않은 쪽의 좋은 아이디어는 리뷰 단계에서 반영 여부 판단

## Gemma 통합 전략 (로컬 Ollama)

### 역할 분담
- **Gemini**: 광범위 스캔 + 영향 분석 (1M 컨텍스트)
- **Codex**: 구현 + 패치 + 적대적 리뷰 (세컨드 브레인)
- **Gemma**: **로컬 세컨드 오피니언 + 민감 코드 리뷰** (외부 API 차단 대상)

### 호출 경로
- **자동 (훅)**: `code-reviewer` 서브에이전트 호출 시 `~/.claude/hooks/gemma-review-prescan.sh` 자동 실행
  - 대상: `git diff HEAD` (최대 500줄)
  - 타임아웃: 30초, 연결체크 3초
  - 캐시: `~/.claude/cache/gemma/{프로젝트}-review-prescan.md` (5분)
  - 서버 다운 시 즉시 스킵 (파이프라인 블로킹 없음)
- **수동**: `Skill(ask-gemma)` 또는 `/ask-gemma` 슬래시로 직접 호출

### Gemma 프리스캔 사용 시점 (리뷰 단계)
- code-reviewer + codex:review + Gemini 심층 리뷰와 **병렬** 실행 (4중 리뷰)
- 훅이 자동 동작하므로 별도 수동 호출 불필요
- 훅 실패/서버 다운 시 수동으로 `Skill(ask-gemma)` 호출 권장 (민감 코드일 때만)

### Gemma 적합 작업
- **민감 코드**: 인증/세션/JWT/개인정보 코드 — 외부 API 전송 금지 대상
- **간단한 세컨드 오피니언**: 3파일 미만 소규모 판단
- **아이디어 발산**: 설계 브레인스토밍 초기 단계
- **오프라인/프라이빗**: 네트워크 단절 대비

### Gemma 한계
- 8B + Q4 양자화 → Claude/Codex/Gemini 대비 환각·누락 빈도 높음
- 런타임 버그(race condition, 메모리 누수) 실측 불가
- 크로스파일 영향 분석은 Gemini(1M) 담당
- 비즈니스 로직 정합성 최종 판단은 Claude가 반드시 재검증

### 모델 고정
- **항상 `gemma4:e4b` (8B, Q4_K_M)** — 사용자가 "31b로" "고품질로" 명시 요청 시만 `gemma4:31b` 사용
- `keep_alive: "30m"` 필수 — 모델 메모리 상주로 재호출 즉답
