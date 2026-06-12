---
name: deep-learn
description: "주간 심층 학습. 학습 큐(`Learning/learning-queue.md`)에 누적된 의문을 일괄 분석하여 학습 노트 생성. 또는 특정 주제 직접 입력 가능. /deep-learn [주제] 또는 /deep-learn queue로 실행."
allowed-tools: Bash(~/.agents/scripts/llm-router.sh *), Bash(/Users/leonard/.agents/scripts/llm-router.sh *), Bash(grep *), Bash(head *), Read, Write, Edit, Grep, Glob, Skill
---

# Deep Learn — 주간 심층 학습

학습 큐에 누적된 의문을 깊이 파고들어 학습 노트로 변환한다. **개발자 성장을 위한 핵심 도구**.

## 사용법

- `/deep-learn` — 학습 큐 모두 처리 (기본)
- `/deep-learn queue` — 학습 큐 모두 처리
- `/deep-learn FastAPI Annotated DI` — 특정 주제 직접 분석
- `/deep-learn weekly` — 이번 주 자주 본 패턴 자동 추출 + 분석

## 절차

### 1단계: 분석 대상 결정

**케이스 A: 학습 큐 모드 (기본)**

`~/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md` 의 미체크 항목(`- [ ]`) 모두 추출.

```bash
QUEUE="$HOME/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md"
grep "^- \[ \]" "$QUEUE" | head -10
```

10개씩 배치 처리. 너무 많으면 우선순위(최근 + 빈도)순.

**케이스 B: 직접 주제**

`$ARGUMENTS`로 받은 주제 그대로 분석.

**케이스 C: weekly 모드**

이번 주 메트릭에서 자주 나온 키워드 추출:
```bash
METRICS="$HOME/.claude/cache/metrics"
# 최근 7일 description 컬럼 추출 → 빈도 분석
```

### 2단계: 3중 LLM 분석 (병렬)

각 주제마다 **Gemini + Codex + Gemma 가용한 모두** 동시 호출한다. provider CLI를 직접 실행하지 않고 중앙 라우터 또는 라우터 기반 ask 스킬만 사용한다.

#### Gemini (1M 컨텍스트)
```bash
~/.agents/scripts/llm-router.sh scan --caller deep-learn --provider gemini --prompt "다음 개념을 심층 분석해줘:
주제: [주제]

다음 형식으로 답변:
## 핵심 원리
## 작동 방식 (내부)
## 유사 개념과의 차이
## 함정/주의점 (실전)
## 다른 언어/프레임워크에서는?
## 공식 문서 링크
## 더 깊이 가려면 (책/논문/소스코드)"
```

#### Codex (세컨드 오피니언)
```
Skill(ask-codex)
"이 개념을 다른 관점에서 설명해줘:
- 만약 직접 구현한다면?
- 트레이드오프는?
- 안티패턴은?"
```

#### Gemma (로컬 빠른 검증)
```
Skill(ask-gemma)
"이 개념의 핵심 1줄 요약 + 가장 흔한 오해 1개"
```

### 3단계: Claude 통합 + 검증

3개 답변을 받아서:
1. **공통 사실** — 모두 일치하는 것
2. **차이/충돌** — 도구별 다른 의견
3. **본인 판단** — Claude 메타 결론

차이 있으면 **공식 문서로 검증** (WebFetch 또는 사용자가 알려준 소스).

### 4단계: 학습 노트 생성

저장 위치:
```
~/Workspace/weaversbrain/weaversbrain/Learning/concepts/{주제-slug}.md
```

형식:
```markdown
---
date: YYYY-MM-DD
type: concept
topic: {주제}
sources: [Gemini, Codex, Gemma, Claude]
---

# {주제}

## 한 줄 요약
{Gemma 빠른 요약}

## 핵심 원리
{Gemini 분석}

## 작동 방식
{Gemini + Codex 통합}

## 유사 개념과의 차이
{Gemini}

## 함정/실전 주의점
{Codex 안티패턴 + Gemini 함정}

## 본인이 놓치고 있던 것
{Claude 메타 분석 — 사용자가 평소 이해와 차이}

## 코드 예시
{실전 코드}

## 다음 단계
- [ ] 관련 개념: ...
- [ ] 더 깊이: ...

## 출처
- Gemini: ...
- Codex: ...
- 공식 문서: ...
```

### 5단계: 학습 큐 업데이트

처리한 항목을 `- [x]` 로 마킹. 학습 노트 링크 추가:

```markdown
- [x] **2026-04-28 20:10** [개념 의문] FastAPI Annotated DI가 뭐야?
  → [[concepts/fastapi-annotated-di]]
```

### 6단계: 1달 후 복습 큐 추가

`~/Workspace/weaversbrain/weaversbrain/Learning/review-queue.md` 에 추가:
```
- [ ] {1개월 후 날짜}: {주제} (학습일 YYYY-MM-DD)
```

매월 자동 알림 (cron 또는 SessionStart hook).

## 자동화

### 매주 일요일 자동 실행 (cron 추천)

```bash
# crontab 추천 추가
0 14 * * 0 /Users/leonard/.local/bin/claude --skill deep-learn queue
```

또는 launchd plist:
- 일요일 14시 (학습 시간 블록)
- 학습 큐 미처리 항목 일괄 분석
- 결과를 Obsidian Learning/concepts/ 누적

## 주의

- **3중 LLM 호출 = 토큰 소비 큼** — 매주 1회 정도 권장
- **공식 문서 검증 필수** — LLM이 헛소리할 수 있음
- **본인 코드와 연결** — 추상 이론 X, 실제 사용한 패턴 분석
- **일주일 후 다시 보기** — 한 번 읽고 끝나면 학습 X

## 활용 예시

```
# 일요일 자동 (큐 처리)
/deep-learn

# 새로 만난 개념 즉시 학습
/deep-learn Rust ownership vs GC

# 이번 주 패턴 분석
/deep-learn weekly

# 큰 결정 전 깊이 학습
/deep-learn 마이그레이션: SQLAlchemy 1.x → 2.x
```

## 관련 도구

- `Skill(ask-gemini)` — 1M 토큰
- `Skill(ask-codex)` — 세컨드 오피니언
- `Skill(ask-gemma)` — 로컬 프라이빗
- `Skill(deep-research)` — 더 깊은 조사 (라이브러리 비교 등)
- WebFetch — 공식 문서 가져오기
