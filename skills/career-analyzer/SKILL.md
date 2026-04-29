---
name: career-analyzer
description: "dev-data-collector가 만든 portrait.md 스냅샷을 읽고, 프레임워크(performance-cycle/brag-doc/staff-eng-path/external)에 따라 강점·약점·다음 과제가 담긴 해석 문서를 생성한다. 데이터 재수집 금지. '/analyze', '/analyze performance-cycle 2026-Q2', '/analyze brag-doc 2026-Q2 --audience=external' 등으로 트리거."
argument-hint: "[framework] [label] [--prev=LABEL] [--audience=internal|external] [--purpose=...]"
disable-model-invocation: true
allowed-tools: Read, Write, Glob
---

# career-analyzer

Collector 스냅샷을 해석해 narrative 문서를 만드는 에이전트.

## 사용법

```
/analyze                                              # 프레임워크 선택 프롬프트
/analyze performance-cycle 2026-Q2                    # 기본 프레임워크
/analyze performance-cycle 2026-Q2 --prev=2026-Q1     # 이전 분기와 비교
/analyze brag-doc 2026-Q2 --audience=external         # redaction 적용
/analyze staff-eng-path 2026-Q2                       # Staff 준비
/analyze external 2026-Q2                             # 면접/외부 공유용 self-assessment
```

## 절대 규칙 (위반 시 작업 중단)

1. **데이터 재수집 금지**. `Bash`, `Agent`, `Grep`, `Glob`을 써서 git/GitHub/레포를 직접 보지 않는다.
   - 입력은 **오직** Collector가 만든 `portrait.md` + `portrait.json` + 이전 snapshot + `Plans/focus-areas*.md`
   - 부족한 지표가 보이면 **작업을 멈추고** 사용자에게 "Collector의 metrics.md에 XX 추가 필요" 보고
2. **출처 없는 주장 금지**. 모든 수치·단정 문장 뒤에 `(source: portrait §N)` 주석 필수
3. **데이터에 없는 숫자 지어내기 금지**. 추정·반올림이 필요하면 근거 표시
4. **덮어쓰기 금지**. 같은 label이라도 프레임워크·audience 다르면 새 파일
5. **부정형 해명 금지** ("~이 아니다", "~는 안 했다"). 양성 사실만 서술

## 입력 경로

- 스냅샷: `~/Workspace/weaversbrain/weaversbrain/Reports/snapshots/{label}-portrait.md`
- JSON sidecar: `~/Workspace/weaversbrain/weaversbrain/Reports/snapshots/{label}-portrait.json`
- 이전 스냅샷 (optional): `--prev={prev_label}`로 지정된 것
- Focus areas: `~/Workspace/weaversbrain/weaversbrain/Plans/*focus-areas*.md` (가장 최근 파일)
- Goals 소스: 이전 사이클의 `{prev_label}-performance-cycle.md` §7

## 출력 경로 규칙

| 프레임워크 / audience | 파일명 |
|---|---|
| performance-cycle | `{label}-performance-cycle.md` |
| brag-doc / internal | `{label}-brag-doc-internal.md` |
| brag-doc / external | `{label}-brag-doc-external.md` |
| staff-eng-path | `{label}-staff-eng-path.md` |
| external | `{label}-assessment-external.md` |
| internal (기본) | `{label}-assessment-internal.md` |

저장: `~/Workspace/weaversbrain/weaversbrain/Reports/snapshots/{파일명}`

## 실행 절차

### 1단계: 인자 파싱

- 첫 번째 positional: 프레임워크 (`performance-cycle` 기본)
- 두 번째 positional: label (예: `2026-Q2`). 없으면 `Reports/snapshots/`에서 가장 최근 portrait 선택
- 옵션: `--prev`, `--audience`, `--purpose`

### 2단계: 입력 로드

1. `{label}-portrait.md` Read → 섹션별 내용 캡처
2. `{label}-portrait.json` Read → 구조화된 수치
3. `--prev` 있으면 이전 portrait도 Read
4. `Plans/` 최신 focus-areas 파일 Glob → Read (있으면)
5. 이전 사이클 performance-cycle 파일 있으면 §7 Goals 추출

### 3단계: 프레임워크 참조 로드

`references/frameworks/{framework}.md` 읽고 해당 구조로 출력. 각 프레임워크 문서는 섹션 목차/작성 원칙을 담는다.

공통 참조:
- `references/goals-tracking.md` — Goal 달성률 계산
- `references/narrative-principles.md` — 문장 원칙
- `references/redaction-rules.md` — audience=external일 때 적용
- `references/impact-templates.md` — Activity → Outcome 변환

### 4단계: 해석 작성

- 각 섹션의 모든 단정 문장에 `(source: portrait §N)` 주석
- 강점/약점은 **이전 대비 변화**로 표현 (이전 snapshot 있을 때)
- Goals 섹션은 `goals-tracking.md` 규칙 따름
- audience=external이면 `redaction-rules.md`로 post-process (레포명·팀원 이름·URL 마스킹)

### 5단계: 저장 & 안내

- 출력 경로에 Write
- 덮어쓰기 발생 시 기존 파일을 `-draft-YYYYMMDD-HHMM.md`로 백업
- obsidian:// URI 출력
- 후속 안내:
  > "이 해석이 맞다고 판단되면 Plans/focus-areas를 업데이트 제안하거나, brag-doc/staff-eng-path로 같은 snapshot 재해석 가능."

## 사용 가능한 도구

- `Read`: snapshot, frontmatter, references
- `Write`: 출력 파일
- `Glob`: 최신 focus-areas / 이전 snapshot 검색

**금지**: `Bash`, `Grep`, `Agent`. 데이터 재수집 유혹 차단.

## 입력

$ARGUMENTS

위 인자로 프레임워크·label·옵션을 파싱하고, portrait.md를 기반으로 해석 문서를 작성하세요. 재수집 금지.
