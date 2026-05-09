---
name: md-trace
description: Claude Code 라우팅 메타 관측성. /md-trace 는 v2(3패널 대시보드) 기본 — 적중률·죽은 룰·Heatmap·타임라인. /md-trace sankey 는 v1(요청→md Sankey). /md-trace 30 으로 N일.
---

# /md-trace — 메타 라우팅 관측성

CLAUDE.md의 라우팅 규칙 (workflows/skills/agents/memory)이 실제로 의도대로 동작하는지 검증하는 도구. `/usage`(토큰), `/trace`(훅)와 함께 메타 관측성 3종 세트.

## v2 (기본) — 3패널 대시보드

PO + 디자이너 합동 재설계 결과(2026-05-08). 다음 4가지 질문에 답한다:
- (a) 어떤 요청 카테고리가 어떤 컨텍스트를 끌어왔나 → **Heatmap**
- (b) 어떤 룰이 잘 작동/안 작동하나 → **적중률 KPI + 갭 패널**
- (c) 어떤 .md가 죽었나 (Read 0회) → **죽은 룰 패널 (탭)**
- (d) 시간 추이 → **카테고리 lane 타임라인**

KPI 헤더(첫 3초 답): 적중률 % · 죽은 룰 N · 활성 룰 N · 총 .md 참조

```bash
python3 ~/.claude/scripts/md-trace-v2.py --days 14 --scope config --open
```

기본 scope=`config` (`workflows + skills + agents + memory + CLAUDE.md`). v2의 1차 KPI는 **라우팅 적중률** 단 하나 — `/usage`·`/trace`와 데이터·뷰 겹치지 않음.

## v1 (legacy) — Sankey

요청 → .md 흐름 단순 매핑. 첫 결과물이었고, 단순 매핑만 보고 싶을 때 유효.

```bash
python3 ~/.claude/scripts/md-trace-v1.py --days 14 --scope claude --open
# 또는 (호환)
python3 ~/.claude/scripts/md-trace.py --days 14 --scope claude --open
```

리포트 안에서 슬라이더로 높이/폰트 조정, 좌우↔세로 토글, 패널 드래그 리사이즈 가능.

## 사용 시나리오

| 발화 | 동작 |
|---|---|
| `/md-trace` | v2 (3패널 대시보드, 14일, scope=config) |
| `/md-trace 30` | v2, 30일 |
| `/md-trace all` | v2, 프로젝트 docs 포함 전체 scope |
| `/md-trace open` | 생성 즉시 브라우저로 |
| `/md-trace sankey` | v1 (Sankey) 호출 |
| `/md-trace sankey 30 stack big` | v1, 30일, 세로 레이아웃, 큰 폰트 |

## 실행 절차

### 1단계: 인자 파싱

사용자 발화에서:
- `sankey` → v1 사용 (`md-trace-v1.py`)
- 그 외 → v2 사용 (`md-trace-v2.py`, 기본)
- 정수 N → `--days N`
- `all` / `config` / `claude` → `--scope`
- `open` → `--open`
- v1 한정: `side` / `stack` → `--layout`, `big` → `--height 1100 --font 14`, `small` → `--height 540 --font 10`

### 2단계: 스크립트 실행

```bash
ARGS=(--days 14 --scope config)
python3 ~/.claude/scripts/md-trace-v2.py "${ARGS[@]}"
```

### 3단계: 요약 해석

stdout 출력을 보고 Claude가 인사이트 추가:

1. **적중률 < 70%**: 룰 키워드가 부족하거나, 사용자 발화 패턴이 룰 가정과 다름 → REQUEST_RULES 정규식 보강 필요
2. **죽은 룰 다수**: 14일 동안 한 번도 안 쓰인 .md → 그 작업 자체가 없었거나 (정상), 룰 트리거 키워드 갱신 필요
3. **Heatmap 한 셀 쏠림**: 특정 (요청 카테고리 × md 카테고리)에 압도적 → 다른 카테고리 라우팅이 약함
4. **타임라인 빈 lane**: 특정 카테고리가 N일째 비어있으면 룰 죽은 후보

## v2 데이터 처리 핵심

- **요청 카테고리 분류**: `categorize_request()` 함수 — CLAUDE.md "작업 타입 자동 라우팅" + 키워드(SSO, 파이프라인, codex 등) 기반 정규식 매칭. 한 요청이 여러 카테고리 동시 매칭 가능
- **기대 .md 매핑**: `REQUEST_RULES` 테이블에 (정규식 → 카테고리 → 기대 .md 글롭) 명시. 사용자가 룰 추가하려면 이 테이블 편집
- **죽은 룰 탐지**: `discover_all_md()` 가 `~/.claude/{workflows, skills, agents, memory}` 전수 스캔 → 14일 Read 기록과 차집합

## 규칙

- transcript jsonl 수정/삭제 금지 (읽기만)
- HTML 자가완결 (Plotly CDN만 외부)
- v1/v2 스크립트는 별도 진입점 — 둘 다 보존
- REQUEST_RULES 갱신 시 새 키워드를 추가하되 기존 정규식은 보존 (히스토리 비교 위해)

## 데이터 소스

- `~/.claude/projects/**/*.jsonl` (Claude Code transcript)
- 각 user 메시지(`type=user, userType=external`) 직후 등장한 `Read` tool_use 의 `file_path` 중 `.md`만 수집
- 출력: `~/.claude/cache/md-trace/report-v2.html` (v2), `report.html` (v1)
