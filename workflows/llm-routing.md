# LLM 라우팅 규칙

Claude, Codex, Gemini/agy, Gemma/Ollama를 한쪽 전용 설정이 아니라 공통 라우팅 계층으로 묶는다. 실행 정책의 정본은 `registry/llm-routing.json`이고, 실제 호출은 `scripts/llm-router.sh`가 담당한다.

---

## 공통 라우터

**진입점**: `~/.claude/scripts/llm-router.sh`

**역할**:
- task별 provider fallback 결정
- 호출한 provider로 다시 라우팅되는 self-recursion 방지
- `cache/llm-handoff/current.json`에 이어받기 컨텍스트 기록
- `cache/llm-provider-health.json`에 provider 상태 기록
- 실제 provider 실행은 항상 `scripts/llm-call.sh`에 위임

**기본 사용**:

```bash
~/.claude/scripts/llm-router.sh doctor
~/.claude/scripts/llm-router.sh doctor --strict
~/.claude/scripts/llm-router.sh scan --caller manual --prompt "영향 범위 분석"
~/.claude/scripts/llm-router.sh implement --caller manual --prompt "패치 초안 작성"
~/.claude/scripts/llm-router.sh review --caller manual --prompt "현재 diff 리뷰"
~/.claude/scripts/llm-router.sh private --caller manual --prompt "민감한 로컬 검토"
```

## Task Routes

| task | 전략 | 순서 |
|---|---|---|
| `scan` | first success | Gemini/agy → Codex → Gemma |
| `implement` | first success | Codex → Gemini |
| `review` | parallel best-effort | Codex + Gemini/agy + Gemma |
| `private` | first success | Gemma only |
| `rescue` | first success | Codex → Gemini/agy → Gemma |
| `summarize` | first success | Gemma → Codex → Gemini/agy |
| `default` | first success | Codex → Gemini/agy → Gemma |

Claude 토큰이 소진되면 `rescue` 또는 `implement` 경로가 Codex를 우선 사용한다. Gemini/agy는 큰 컨텍스트 스캔과 통합 검증에 우선 쓰고, Gemma/Ollama는 민감하거나 로컬-only인 작업에 우선 쓴다.

---

## Health And Local Hosts

`doctor`는 `cache/llm-provider-health.json`을 갱신한다. Codex/Gemini가 사용 가능하면 라우터는 실행 가능 상태로 보고, 로컬 Gemma/Ollama만 실패한 경우 `degraded`로 표시한다. 모든 provider가 반드시 살아 있어야 하는 점검에는 `doctor --strict`를 쓴다.

Gemma/Ollama host 탐색 순서:

1. `OLLAMA_HOST_LAN` 또는 `OLLAMA_HOST_URL`
2. `~/.config/ini/config.toml`의 `host`
3. `registry/llm-routing.json`의 `providers.gemma.host_candidates`

`doctor`가 성공한 로컬 host를 찾으면 이후 `ini` adapter 호출에 `OLLAMA_HOST_LAN`으로 넘긴다.

---

## Provider Roles

### Gemini / Antigravity CLI

**역할**: 광범위 스캔, 영향 분석, 대규모 컨텍스트 확인

**사용 상황**:
- 코드 구조/아키텍처/의존성 파악
- 3파일 이상 수정, 리팩터, 마이그레이션 영향 분석
- 최종 통합 검증
- UI/스크린샷 분석, 문서 요약

**경로**: `scripts/llm-router.sh scan` 또는 `scripts/llm-call.sh gemini`

### Codex

**역할**: 구현, 패치, 코드 리뷰, Claude quota 소진 시 주 continuation 경로

**사용 상황**:
- 구현 대안 작성
- 패치 초안/검토
- 디버깅 rescue
- Claude 토큰 소진 후 이어받기

**경로**: `scripts/llm-router.sh implement`, `scripts/llm-router.sh rescue`, 또는 `scripts/llm-call.sh codex`

### Gemma / Ollama / ini

**역할**: 로컬, 프라이빗, 빠른 판단 보조

**사용 상황**:
- 민감 데이터 포함 질의
- 외부 API로 보내기 부적합한 검토
- 짧은 요약, 한글 초안, 세션 요약

**경로**: `scripts/llm-router.sh private`, `scripts/llm-router.sh summarize`, 또는 `scripts/llm-call.sh ini`

---

## Handoff

라우터는 호출 시 `cache/llm-handoff/current.json`을 갱신한다.

포함 정보:
- 현재 `cwd`
- task/caller/provider
- prompt preview
- git root/branch/status
- changed files 일부

다른 LLM에서 이어받을 때는 이 파일을 먼저 읽고, 실제 코드와 현재 git 상태를 다시 확인한다.

## Recursion Guard

라우터는 다음 환경변수를 사용한다.

| env | 의미 |
|---|---|
| `LLM_PARENT_PROVIDER` | 현재 호출을 만든 상위 provider |
| `LLM_ACTIVE_PROVIDER` | 현재 실행 중인 provider |
| `LLM_CALL_DEPTH` | 중첩 호출 깊이 |

기본 정책은 parent provider를 fallback 후보에서 제거하고, `max_call_depth=2` 이상이면 중단한다.

## 원칙

- active orchestrator가 최종 통합한다. Claude가 항상 가능하다고 가정하지 않는다.
- hooks/scripts의 provider 호출은 `llm-router.sh` 또는 `llm-call.sh`를 통한다.
- `private` route는 외부 provider를 쓰지 않는다.
- LLM 출력은 근거 자료일 뿐 자동 채택하지 않는다.
