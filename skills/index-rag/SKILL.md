---
name: index-rag
description: local-rag 벡터 DB에 Obsidian Vault 및 프로젝트 소스코드를 인덱싱합니다. "/index", "/index vault", "/index identity-hub", "/index delta" 등으로 사용합니다.
argument-hint: "[vault|프로젝트명|status|delta [프로젝트명]]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(find *), Bash(date *), Bash(ls *), Bash(/Users/leonard/.claude/scripts/rag-ingest.sh *), Read, Glob
---

# index-rag

local-rag MCP 서버에 파일을 인덱싱한다.

## 사용법

```
/index              → 전체 (vault + 모든 프로젝트)
/index vault        → Obsidian vault만
/index {프로젝트명}  → 특정 프로젝트만
/index status       → 현재 인덱싱 상태 확인
/index delta        → 변경된 파일만 (전체 프로젝트 + vault)
/index delta vault  → vault에서 변경된 파일만
/index delta {프로젝트명} → 특정 프로젝트에서 변경된 파일만
```

## 인덱싱 대상

### Obsidian Vault (`vault`)

- 경로: `~/Workspace/weaversbrain/weaversbrain/`
- 대상: `**/*.md`
- 제외: `.obsidian/`, `Templates/`

### 프로젝트 목록

| 이름 | 경로 | 대상 확장자 |
|------|------|------------|
| `identity-hub` | `~/Workspace/identity-hub` | `.py`, `.md` |
| `maxai-b2c-backend` | `~/Workspace/maxai-b2c-backend` | `.php`, `.vue`, `.js`, `.md` |
| `identity-keycloak` | `~/Workspace/identity-keycloak` | `.ftl`, `.java`, `.properties`, `.md` |
| `identity-hub-frontend` | `~/Workspace/identity-hub-frontend` | `.tsx`, `.ts`, `.md` |
| `identity-hub-python-sdk` | `~/Workspace/identity-hub-python-sdk` | `.py`, `.md` |
| `keycloak-kakao-social-provider` | `~/Workspace/keycloak-kakao-social-provider` | `.kt`, `.java`, `.md` |
| `sso-fallback-monitor` | `~/Workspace/sso-fallback-monitor` | `.py`, `.html`, `.js`, `.md` |
| `identity-platform-docker` | `~/Workspace/identity-platform-docker` | `.yml`, `.yaml`, `.conf`, `.md` |
| `maxai-docker` | `~/Workspace/maxai-docker` | `.yml`, `.yaml`, `.conf`, `.md` |
| `speakingmax-backend` | `~/Workspace/speakingmax-backend` | `.php`, `.js`, `.vue`, `.md` |

### 공통 제외 패턴

아래 경로는 **항상** 제외한다:

- `.git/`, `.venv/`, `venv/`, `node_modules/`, `vendor/`
- `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`
- `dist/`, `build/`, `.next/`, `out/`
- `site-packages/`, `.idea/`, `.vscode/`
- `.obsidian/`
- `*.min.js`, `*.min.css`, `*.map`
- `package-lock.json`, `yarn.lock`, `poetry.lock`, `composer.lock`

## 인덱싱 방법: 2-Phase 전략

토큰 소모를 최소화하기 위해 CLI 벌크 인제스트와 MCP 인제스트를 분리한다.

### Phase 1: CLI 벌크 인제스트 (토큰 0)

`.md` 파일은 CLI로 직접 인제스트한다. MCP 도구 호출 오버헤드가 없으므로 토큰이 소모되지 않는다.

**헬퍼 스크립트**: `/Users/leonard/.claude/scripts/rag-ingest.sh`
- DB_PATH, CACHE_DIR, MODEL_NAME이 MCP 서버와 동일하게 설정됨
- 사용법: `rag-ingest.sh <파일 또는 디렉토리 경로>`

**Vault 전체:**
```bash
/Users/leonard/.claude/scripts/rag-ingest.sh ~/Workspace/weaversbrain/weaversbrain/
```
- CLI가 디렉토리를 재귀 탐색하여 `.md` 파일을 자동 수집/인제스트
- `.obsidian/`은 .md가 아닌 파일이므로 자동 제외됨
- `Templates/` 디렉토리의 .md 파일 3개는 무해하므로 허용

**프로젝트 .md 파일:**
프로젝트 디렉토리에는 `.venv/`, `node_modules/`, `vendor/` 등에 불필요한 .md 파일이 있을 수 있다.
따라서 프로젝트의 .md 파일은 **개별 파일 경로**로 CLI 인제스트한다:

```bash
# Glob으로 .md 파일 수집 (제외 패턴 적용) → /tmp에 파일 목록 저장
# xargs로 개별 파일 인제스트 (CLI는 단일 파일도 지원)
```

또는 프로젝트 .md 파일 수가 적으면 (보통 <10개) Phase 2에서 MCP `ingest_file`로 처리해도 무방.

### Phase 2: MCP 인제스트 (소스코드)

`.py`, `.php`, `.vue`, `.js`, `.ts`, `.tsx`, `.kt`, `.java`, `.ftl`, `.properties`, `.yml`, `.yaml`, `.conf` 등 소스코드 파일은 CLI가 지원하지 않으므로 MCP로 인제스트한다.

**에이전트 기반 병렬 처리:**
- 프로젝트별로 에이전트를 병렬 디스패치
- 각 에이전트는 소스코드 파일만 처리 (.md 제외 — 이미 Phase 1에서 처리됨)
- 에이전트 프롬프트에 `.md 파일은 건너뛰어라` 명시

```
1. Read(file_path=절대경로)로 내용 읽기
2. mcp__local-rag__ingest_data(
     content=파일내용,
     metadata={
       source: "file://절대경로",
       format: "text"
     }
   )
```

**에이전트 디스패치 규칙:**
- 한 에이전트당 **최대 100개 파일** (컨텍스트 누적 억제)
- 파일 100개 이상인 프로젝트는 분할하여 복수 에이전트
- `mode: "bypassPermissions"` 필수
- 에이전트 프롬프트에 파일 목록을 직접 포함 (Read로 파일 목록 읽기 금지)

## 상태 파일

증분 인덱싱을 위해 마지막 인덱싱 시점을 기록하는 상태 파일을 관리한다.

- **경로**: `~/.claude/skills/index-rag/.index-state.json`
- **형식**:
```json
{
  "projects": {
    "identity-hub": {
      "last_commit": "abc1234",
      "last_indexed_at": "2026-02-21T14:30:00+09:00"
    },
    "vault": {
      "last_commit": null,
      "last_indexed_at": "2026-02-21T14:30:00+09:00",
      "note": "vault is not a git repo, uses mtime fallback"
    }
  }
}
```

- `last_commit`: 해당 프로젝트의 마지막 인덱싱 시 git HEAD commit hash
- `last_indexed_at`: ISO 형식 타임스탬프 (mtime 폴백용)

## 실행 절차

### 1단계: 인자 파싱

- 인자 없음 → `all` (전체 인덱싱)
- `vault` → Obsidian vault만 (전체)
- `status` → 상태 확인 후 종료
- `delta` → 변경분만 인덱싱 (증분 모드)
- `delta vault` → vault 변경분만
- `delta {프로젝트명}` → 특정 프로젝트 변경분만
- 그 외 → 프로젝트 목록에서 매칭 (전체)

### 2단계: 현재 상태 확인

`mcp__local-rag__status`로 현재 인덱싱 상태(문서 수, 청크 수)를 확인하여 사용자에게 보여준다.

### 3단계: Phase 1 — CLI 벌크 인제스트 (.md 파일)

#### Vault 인덱싱

```bash
/Users/leonard/.claude/scripts/rag-ingest.sh ~/Workspace/weaversbrain/weaversbrain/
```

한 번의 Bash 호출로 vault 내 모든 .md 파일 (~992개)을 인제스트한다.
타임아웃: 600000ms (10분). 진행은 stderr로 출력된다.

#### 프로젝트 .md 인덱싱

각 프로젝트에서 .md 파일을 Glob으로 수집한 뒤 CLI로 인제스트:

```bash
# 방법 1: 프로젝트 루트에 .md가 소수면 개별 호출
/Users/leonard/.claude/scripts/rag-ingest.sh /path/to/project/README.md
/Users/leonard/.claude/scripts/rag-ingest.sh /path/to/project/docs/guide.md

# 방법 2: 프로젝트에 불필요한 하위 디렉토리(.venv 등)가 없으면 디렉토리 인제스트
/Users/leonard/.claude/scripts/rag-ingest.sh /path/to/project/docs/
```

**병렬 실행**: vault와 프로젝트 .md 인제스트를 병렬 Bash 호출로 동시 실행 가능.

### 4단계: Phase 2 — 소스코드 에이전트 인제스트

Phase 1에서 .md 처리가 완료되면, 소스코드 파일만 에이전트로 처리한다.

#### 파일 목록 수집

각 프로젝트별로 Glob으로 소스코드 파일을 수집한다 (.md 제외):

```
identity-hub: *.py (md 제외)
maxai-b2c-backend: *.php, *.vue, *.js (md 제외)
...
```

#### 에이전트 디스패치

프로젝트별 에이전트를 병렬 디스패치한다. 에이전트 프롬프트에:
1. 처리할 파일 목록 (절대 경로)
2. 인덱싱 방법 (Read → ingest_data)
3. `.md 파일은 이미 처리됨 — 건너뛰어라`
4. 빈 파일 건너뛰기 규칙
5. 진행 상황 보고 형식

**중요:**
- 한 번에 **최대 5개** MCP 호출 병렬
- 에러 발생 시 건너뛰고 마지막에 실패 목록 출력
- 빈 파일 (0바이트, `__init__.py` 등) 건너뛰기

### 5단계: 파일 목록 수집 (증분 모드)

#### 증분 모드 (`delta`)

변경된 파일만 수집한다. git diff를 사용하며, git이 없으면 mtime으로 폴백한다.

**절차:**

1. **상태 파일 읽기**: `~/.claude/skills/index-rag/.index-state.json`을 Read로 읽는다. 파일이 없으면 첫 실행이므로 전체 인덱싱으로 폴백하고 사용자에게 알린다: `"상태 파일이 없어 전체 인덱싱으로 전환합니다."`

2. **git 변경 파일 감지** (프로젝트 경로에서 Bash 실행):
```bash
# 변경된 파일 (마지막 인덱싱 커밋 대비)
git -C {프로젝트경로} diff --name-only {last_commit} HEAD -- {확장자패턴들}

# 스테이징되지 않은 변경
git -C {프로젝트경로} diff --name-only -- {확장자패턴들}

# 새로 추가된 untracked 파일
git -C {프로젝트경로} ls-files --others --exclude-standard -- {확장자패턴들}
```

   - 세 결과를 합치고 중복 제거 → 절대 경로로 변환
   - 공통 제외 패턴에 해당하는 파일은 필터링

3. **git 없는 경우 (mtime 폴백)** — vault 등:
   ```bash
   find {경로} -name "*.md" -newer {상태파일경로} -type f
   ```

4. **삭제된 파일 감지**:
   ```bash
   git -C {프로젝트경로} diff --name-only --diff-filter=D {last_commit} HEAD
   ```
   - 삭제된 파일은 `mcp__local-rag__delete_file`로 RAG에서도 제거한다.

5. **결과 요약**:
   ```
   identity-hub: 변경 3개 (.py 2, .md 1), 신규 1개, 삭제 0개
   vault: 변경 5개, 신규 2개, 삭제 1개
   총 11개 파일 인덱싱 예정
   ```

6. **증분 인덱싱도 2-Phase 적용**:
   - 변경된 .md 파일 → CLI `rag-ingest.sh`로 개별 인제스트
   - 변경된 소스코드 → MCP `ingest_data`로 인제스트 (소수이므로 에이전트 없이 직접 가능)

### 6단계: 결과 보고

**전체 모드:**
```
인덱싱 완료!

Phase 1 (CLI): vault 992개 + 프로젝트 .md 45개 = 1,037개 (토큰 0)
Phase 2 (MCP): 소스코드 490개 (에이전트 8개)

| 스코프 | 파일 수 | CLI | MCP | 실패 |
|--------|---------|-----|-----|------|
| vault  | 992     | 992 | 0   | 0    |
| identity-hub | 78 | 5  | 73  | 0    |
| 합계   | 1,527   | 1,037 | 490 | 0  |

토큰 절감: ~60% (이전 대비)
```

**증분 모드:**
```
증분 인덱싱 완료! (delta)

| 스코프 | 변경 | 신규 | 삭제 | 방법 |
|--------|------|------|------|------|
| vault  | 5    | 2    | 1    | CLI  |
| identity-hub | 3 | 1  | 0    | MCP  |
| 합계   | 8    | 3    | 1    | —    |
```

### 7단계: 상태 파일 갱신

인덱싱 완료 후 상태 파일을 갱신한다.

각 프로젝트별로:
1. Bash로 현재 HEAD commit hash를 가져온다:
   ```bash
   git -C {프로젝트경로} rev-parse HEAD
   ```
2. 현재 시각을 ISO 형식으로 기록
3. 상태 파일을 Write 도구로 저장

**중요:** 상태 파일 갱신은 인덱싱이 성공적으로 완료된 스코프에 대해서만 수행한다.

## status 명령

`/index status` 실행 시:

1. `mcp__local-rag__status` 호출
2. `mcp__local-rag__list_files` 호출
3. 프로젝트별 인덱싱 파일 수를 집계하여 테이블 출력:

```
| 프로젝트 | 인덱싱됨 | 디스크 파일 | 차이 |
|----------|----------|------------|------|
| vault    | 992      | 992        | 0    |
| identity-hub | 78  | 78         | 0    |
| ...      |          |            |      |
```

## 주의사항

- CLI 인제스트는 `.md`, `.txt`, `.pdf`, `.docx`만 지원. 소스코드는 MCP 필수.
- CLI와 MCP는 같은 DB를 공유. `rag-ingest.sh`의 환경 변수가 `run-local-rag.sh`와 동일해야 함.
- CLI는 이미 인덱싱된 파일을 자동 업데이트 (중복 안전).
- lock 파일, minified 파일, 빌드 산출물은 인덱싱하지 않는다.
- `__init__.py` 같은 빈 파일도 건너뛴다.
- **증분 모드**: 상태 파일이 없으면 전체 인덱싱으로 폴백.
- **증분 모드**: 변경 파일이 0개면 "변경사항 없음. 인덱싱 건너뜀." 출력 후 종료.
- 대형 프로젝트는 시간이 걸린다. CLI 진행률은 stderr로 자동 출력.
- 전체 인덱싱 시에도 상태 파일 갱신 (이후 delta 사용 가능).
