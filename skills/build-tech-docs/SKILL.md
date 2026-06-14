---
name: build-tech-docs
description: >
  코드베이스(SSOT) 기준 외부 통합자용 publish 연동 문서 묶음을 docs/tech-docs/ 에
  신규 생성. 추정 0, 모든 사실은 코드 라인 근거. Diátaxis 4구역. 기존 분산 문서는
  SSOT 흡수 stub. 트리거 "/build-tech-docs", "tech-docs 만들어", "publish 문서
  만들어줘". tech-doc(이슈 단발)·docs-update(SSO 갱신)·moai-docs-generation
  (정적사이트)와 별개.
argument-hint: "[--path docs/tech-docs] [--phase 1|2|all] [--audience integrator|operator|both]"
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, TodoWrite, Skill, mcp__plugin_claude-mem_mcp-search__search, mcp__local-rag__query_documents
---

# build-tech-docs

외부 통합자(integrator)와 운영자(operator)를 대상으로 한 publish 품질의 연동
tech-docs 묶음을 프로젝트 코드베이스(SSOT)를 기준으로 신규 생성한다.

## 핵심 원칙 [HARD]

- **추정 0**: 모든 사실 주장은 Read/Grep 으로 사전 검증된 코드 라인 근거를 가져야 한다. "아마", "보통", "대체로" 같은 추정 어휘 금지
- **SSOT 보장**: 동일 사실은 단 하나의 문서에만 존재. 기존 분산 연동 문서는 흡수/리다이렉트 stub 처리
- **Diátaxis 구조**: Tutorial(02-quickstart) / How-to(integrations/*) / Reference(reference/*) / Explanation(01-overview) 4구역 명확 분리
- **publish 가능**: 내부 핸드오프 노트, 작업 TODO, 가설성 표현은 절대 포함 금지. 외부에 그대로 공개 가능한 품질만
- **양방향 대조**: 외부 서비스 코드가 실존하면 그 코드도 직접 grep 하여 호출/호출자 양쪽을 근거로 사용

## 기존 스킬과 구분

| 스킬 | 목적 | 출력 위치 |
|------|------|-----------|
| `tech-doc` | 이슈 단발성 분석/완성 문서 | Obsidian Vault |
| `docs-update` | 통합 SSO 문서 자동 갱신(기존 갱신) | DOCS_INTEGRATED.md |
| `moai-docs-generation` | Sphinx/MkDocs 정적 사이트 생성 | docs site |
| **`build-tech-docs` (본 스킬)** | **외부 통합자용 publish 문서 묶음 신규 생성** | `docs/tech-docs/` |

## 입력 처리

`$ARGUMENTS` 파싱:

- `--path <dir>` : 생성 위치 (기본 `docs/tech-docs/`)
- `--phase N`    : `1`(연동 코어) / `2`(reference+quickstart) / `all` (기본 `all`)
- `--audience X` : `integrator` / `operator` / `both` (기본 `both`)

옵션이 없으면 Phase 3 에서 본문 마크다운으로 대화형 결정한다(AskUserQuestion 한글
버그 회피를 위해 본문 A/B/C 선택지 사용).

## 실행 절차

### Phase 0: 사전 검색 [필수]

이전에 동일/유사 작업이 있었는지 메모리와 RAG 양쪽을 먼저 확인한다.

1. `mcp__plugin_claude-mem_mcp-search__search` — 과거 동일 작업 기록 확인
   - 쿼리 예시: "build-tech-docs 외부 연동 publish 문서"
2. `mcp__local-rag__query_documents` — 현재 `docs/` 상태와 기존 통합 문서 확인
   - 쿼리 예시: "external integration guide tech-docs structure"
3. 결과가 있으면 "이전에 X 처리됨" 명시, 없으면 "신규" 명시한 뒤 진행

### Phase 1: 기존 문서 현황 매트릭스

Bash + Glob 으로 `docs/` 트리와 흡수 후보를 식별한다.

```bash
find docs -maxdepth 2 -type d 2>/dev/null
ls docs/integrations/ 2>/dev/null
ls docs/feature/integration/ 2>/dev/null
ls docs/modules/ 2>/dev/null
```

흡수 대상을 3분류한다:

- **(가) 완전 흡수 가능** — tech-docs 에 동일 사실이 더 정확하게 들어감 → 리다이렉트 stub 으로 교체
- **(나) 부분 흡수** — tech-docs 가 진입점이지만 본문 일부는 유지 → 상단 배너 + 본문 유지
- **(다) 보존** — 내부 노트/모듈 상세/이슈 라이프사이클 문서 → 손대지 않음

### Phase 2: 코드 사실 전수 수집 (FACT 블록)

추정 0 의 핵심. 다음 7개 FACT 를 **병렬 Bash/Grep/Read** 로 한 번에 추출한다.
각 사실에는 반드시 `파일:라인` 근거를 메모하고, 문서에 그대로 명시한다.

- **FACT-1 엔드포인트**: 라우터 마운트(`app/api/v1/router.py` 등) + 각 `endpoints/*.py` 의 `@router` 데코레이터
- **FACT-2 인증/JWT**: `app/core/security.py` 의 JWT 검증 함수 전문, JWKS 캐시 동작, audience 정책
- **FACT-3 환경변수**: `app/core/config.py` 전체 — Settings 클래스 필드와 기본값
- **FACT-4 스키마**: 요청/응답 Pydantic 스키마 클래스 (특히 OAuth/Auth 응답 형태)
- **FACT-5 예외**: `app/core/exceptions.py` 등 모든 예외 클래스 + 매핑되는 HTTP 상태
- **FACT-6 관측성**: 로깅/감사/메트릭 코드 지점. 실제로 있는지/0줄인지 확정 (예: Prometheus `/metrics` 엔드포인트 존재 여부)
- **FACT-7 외부 서비스 코드**: 실존하는 워크스페이스의 클라이언트 코드 직접 grep
  - 예: `~/Workspace/maxai-b2c-backend/` 에서 Identity Hub 호출 경로 grep
  - 예: `~/Workspace/identity-hub-python-sdk/` SDK 사용 패턴 grep

[HARD] 코드에 **없는** 사실도 "사실"로 명시한다. 예: "Prometheus `/metrics` 엔드포인트는 코드베이스에 없음(2026-MM-DD 기준)". 추측이 아니라 부재 사실의 확정이다.

### Phase 3: 사용자 정렬 (본문 마크다운 선택지)

저위험 결정 질문은 **AskUserQuestion 쓰지 말 것** (한글 버그 회피, CLAUDE.md HARD
룰). 본문에 A/B/C 선택지로 제시한다.

질문 예시(범위/흡수/옵션):

```
범위:
  A) 1차만 (overview + integrations 코어) — 권장
  B) all (reference + quickstart 포함)
  C) reference 만

흡수 정책:
  A) 분류대로 자동 적용 — 권장
  B) 흡수 보류 (신규 생성만)
  C) 흡수 대상 사전 검토

추가:
  A) operations/observability 포함 — 권장
  B) 제외
```

고위험(파괴적/배포) 확인만 AskUserQuestion 허용하되 모든 필드는 ASCII 영어로.

### Phase 4: 문서 생성 (Diátaxis 표준 트리)

`docs/tech-docs/` 하위에 다음 트리를 생성한다.

```
docs/tech-docs/
├── README.md                    # 연동 모델 매트릭스 + 진입점
├── 01-overview.md               # Explanation (BFF 모델, 인증 플로우, 보안 모델)
├── 02-quickstart.md             # Tutorial (15분 안에 동작)
├── integrations/                # How-to (서비스/스택별 레시피)
│   ├── {primary-client}.md      # 예: maxai-b2c-backend.md
│   ├── sdk-services.md          # 공식 SDK 사용 서비스
│   ├── m2m-service-token.md     # 서비스간 M2M 토큰
│   └── third-party.md           # 외부 서드파티 (Hub 비경유 케이스도 정확히 명시)
├── reference/                   # Reference (API/Token/Errors)
│   ├── api-endpoints.md         # FACT-1 기반 전수
│   ├── token-jwt.md             # FACT-2 기반
│   └── error-codes.md           # FACT-5 기반
└── operations/
    └── observability.md         # FACT-6 — 있는 것/없는 것 둘 다 사실로
```

문서 작성 원칙 [HARD]:

- 모든 표/사실 옆에 코드 라인 근거 명시 (예: `근거: app/api/v1/router.py:42-58`)
- "아마", "대체로", "보통", "추정", "~할 것이다" 등 추정 어휘 금지
- 정보가 없으면 **"코드에 없음"을 사실로 명시** (FACT-6 의 핵심 정신)
- 외부 서비스 코드 확인 시 그 라인도 근거에 포함 (양방향 대조)
- 내부 TODO/핸드오프/작업 메모 절대 포함 금지
- 한국어 본문, 코드 식별자/엔드포인트는 영어 원문 유지

### Phase 5: SSOT 흡수 처리

Phase 1 분류대로 실행한다.

- **(가) 완전 흡수**: 기존 문서 본문을 짧은 리다이렉트 stub 으로 교체
  ```markdown
  # {기존 제목}

  > 이 문서의 내용은 `docs/tech-docs/` 로 통합되었습니다.
  > 진입점: [docs/tech-docs/README.md](../tech-docs/README.md)
  >
  > | 기존 내용 | 새 위치 |
  > |-----------|---------|
  > | API 엔드포인트 표 | reference/api-endpoints.md |
  > | JWT 검증 절차 | reference/token-jwt.md |
  ```
- **(나) 부분 흡수**: 기존 문서 상단에 배너 추가, 본문 유지
  ```markdown
  > 외부 통합자/운영자라면 먼저 [docs/tech-docs/](../tech-docs/README.md) 의 진입점을 보세요. 본 문서는 내부 모듈 상세입니다.
  ```
- **(다) 보존**: 손대지 않음
- **`docs/README.md` 인덱스**: tech-docs 행 추가 (디렉토리 맵 + 빠른 진입점)

### Phase 6: 검증 (커밋 전 필수)

내부 `.md` 링크 정합 검증을 Python 으로 수행한다. **BROKEN 0** 이어야 다음 단계.

```bash
python3 - <<'PY'
import os, re, glob, sys
broken = 0
roots = glob.glob("docs/tech-docs/**/*.md", recursive=True) + ["docs/README.md"]
for f in roots:
    if not os.path.isfile(f):
        continue
    d = os.path.dirname(f)
    with open(f, encoding="utf-8") as fh:
        body = fh.read()
    for m in re.finditer(r'\]\(([^)]+?\.md)(?:#[^)]*)?\)', body):
        link = m.group(1)
        if link.startswith("http"):
            continue
        tgt = os.path.normpath(os.path.join(d, link))
        if not os.path.isfile(tgt):
            print(f"BROKEN {f} -> {link}")
            broken += 1
print(f"--- broken links: {broken}")
sys.exit(0 if broken == 0 else 1)
PY
```

추가 자동 검증:

- 추정 어휘 grep (`아마|대체로|~일 것|추정|보통`) → 0건 이어야 함
- 내부 TODO/핸드오프 grep (`TODO|FIXME|핸드오프|작업메모`) → 0건 이어야 함

### Phase 7: 커밋 (사용자 명시 요청 시만)

**자동 커밋 금지**. 사용자가 명시적으로 커밋 요청한 경우에만 2개로 분리한다.

1. `docs(tech-docs): 외부 연동 tech-docs 신규 생성 + 흡수 처리`
   - tech-docs 신규 트리 추가
   - 흡수 대상 stub 교체
2. `docs(readme): tech-docs 진입점 인덱스 추가`
   - `docs/README.md` 만 변경

규칙:

- Co-Authored-By **금지** (CLAUDE.md HARD 룰)
- 한글 메시지
- 본문에 변경 사실 + 핵심 코드 근거 요약

## 산출물 품질 기준

- ✅ 모든 사실에 코드 라인 근거 (Read/Grep 사전 검증)
- ✅ Diátaxis 4구역 (Tutorial / How-to / Reference / Explanation) 명확 분리
- ✅ 단일 진실 공급원 (SSOT) — 같은 사실은 한 문서에만
- ✅ 내부 핸드오프/TODO 0건, publish 가능 품질
- ✅ 내부 링크 BROKEN 0건 (Phase 6 자동 검증)
- ✅ 외부 서비스 코드와 양방향 대조 완료

## 참고 사례 (2026-06-07 identity-hub)

본 스킬은 다음 실측 작업을 기반으로 표준화되었다.

- **프로젝트**: identity-hub (FastAPI BFF + Keycloak)
- **결과**: 11개 문서 1383줄, 내부 링크 63개 전부 유효
- **코드 드리프트 정정 2건**:
  1. `AuthCodeExchangeResponse` 실제 스키마 vs 기존 문서 필드표 불일치 → 코드 라인으로 정정
  2. 외부 서비스 `maxai-b2c-backend` 직접 grep 으로 token-password 마이그레이션 완료 확인
- **부재 사실 확정**: 코드에 Grafana/Prometheus `/metrics` 0줄 → "없음"을 사실로 명시
- **흡수**: 분산되어 있던 `docs/feature/integration/` 스텁 7개 → tech-docs 로 진입점 통일
