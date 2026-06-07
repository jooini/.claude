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
~/.claude/scripts/llm-router.sh doctor --live --provider codex --provider gemini
~/.claude/scripts/llm-router.sh route-health
~/.claude/scripts/llm-router.sh route-health --json
moai-system-check
moai-system-check --live
moai-e2e-check
moai-regression-check --force
moai-telemetry-report --days 7
moai-telemetry-report --days 7 --require-e2e
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

`doctor`는 `cache/llm-provider-health.json`을 갱신한다. Codex/Gemini가 사용 가능하면 라우터는 실행 가능 상태로 본다. Gemma/Ollama는 회사 Windows 호스트에 붙는 office-only provider이므로, 집이나 외부 네트워크에서 닿지 않는 것은 `expected_offline`으로 기록하고 일반 `doctor`에서는 장애로 보지 않는다. 모든 provider가 반드시 살아 있어야 하는 점검에는 `doctor --strict`를 쓴다.

`doctor --strict`는 `expected_offline`도 실패로 본다. 회사 Windows Ollama까지 반드시 살아 있어야 하는 사무실 점검용이고, 집이나 외부 네트워크에서 실패하는 것은 정상이다.

`moai-system-check`도 같은 기준을 쓴다. 기본 실행에서는 Gemma provider와 `private` route의 `expected_offline`을 PASS로 처리한다. 이 상태는 “집/외부망이라 office-only provider에 닿지 않음”이라는 정책 결과이지 장애가 아니다. `moai-system-check --strict`만 사무실망 검증 모드이며, 이때는 Gemma/Ollama가 실제로 reachable이어야 한다.

`moai-system-check --live`는 구조 점검을 넘어 실제 Codex/Gemini/agy provider smoke, MoAI-ADK bridge smoke, handoff/log 업데이트, telemetry E2E evidence까지 확인한다. 성공하면 `cache/moai-bridge-live.jsonl`에 bridge runner별 결과가 남고, `moai-telemetry-report --require-e2e`에서 `complete=True`로 잡혀야 한다.

`moai-e2e-check`는 10점권 통합 게이트다. 단위 테스트, 기본 system check, live provider/bridge smoke, `private` 외부 provider 차단, 실제 Workspace 프로젝트 cwd에서 router dry-run과 read-only Codex provider 호출, telemetry current E2E evidence를 한 번에 검증한다.

`moai-regression-check`는 sync 이후 자동 실행되는 가벼운 회귀 게이트다. 기본은 `moai-e2e-check --skip-live --skip-project-live`를 rate-limit해서 돌리고 결과를 `cache/moai-regression-check.json`에 남긴다. 실패하면 다음 SessionStart에서 `moai-regression-session-warn.sh`가 경고한다. 수동 재검증은 `moai-regression-check --force`를 쓴다.

`doctor --live`는 provider CLI 존재 여부만 보지 않고 짧은 실제 호출을 보낸다. 비용과 시간이 드는 smoke test라서 수동 점검이나 릴리즈 전 검증에만 쓴다. 실패 결과는 `cache/llm-adapter-calls.jsonl`에 `health_class=smoke`, `failure_reason=smoke_failure`로 남아 adapter health 경고율에서는 제외된다.

`route-health`는 provider 단위가 아니라 task route 단위로 현재 실행 가능성을 보여준다. 각 route는 `status`, `score`, `available_providers`, `skipped_providers`, `action`을 가진다. 예를 들어 집에서는 `scan`/`implement`/`review`가 Codex/Gemini로 `ok`이고, `private`는 외부 provider를 의도적으로 금지하기 때문에 `expected_offline`으로 보일 수 있다.

`route-health --json`의 출력 계약은 `registry/llm-route-health-schema.json`에 둔다. `health_cache.age_seconds`와 `health_cache.is_stale`을 같이 보고, doctor cache가 5분보다 오래됐으면 `doctor`를 다시 실행한 뒤 route 점수를 판단한다.

Gemma/Ollama는 `registry/llm-routing.json`에서 `office_only_locked`로 고정한다. 외부 provider fallback은 허용하지 않는다. 특히 `private` route는 Gemma only이고, 외부망에서 Gemma가 `expected_offline`이면 실행 불가 상태로 두는 것이 맞다.

라우터는 이 정책을 실행 시점에도 강제한다. `private --provider codex` 같은 수동 override도 `local_only route forbids external providers`로 차단되어야 한다.

Gemma/Ollama host 탐색 순서:

1. `OLLAMA_HOST_LAN` 또는 `OLLAMA_HOST_URL`
2. `~/.config/ini/config.toml`의 `host`
3. `registry/llm-routing.json`의 `providers.gemma.host_candidates`

`doctor`가 성공한 로컬 host를 찾으면 이후 `ini` adapter 호출에 `OLLAMA_HOST_LAN`으로 넘긴다.

---

## Scores And Telemetry

`doctor`의 `score`는 provider 준비 점수다. Codex/Gemini 중 하나라도 `unavailable`이면 0점이고, 일반 모드에서는 office-only Gemma의 `expected_offline`을 감점하지 않는다. `doctor --strict`에서는 `expected_offline`도 감점하고 exit code도 실패로 돌린다.

`route-health`의 `overall_score`는 route별 `score` 평균이다. `private`처럼 local-only route가 office-only Gemma 때문에 `expected_offline`이면 전체 장애가 아니라 “현재 네트워크에서 의도적으로 실행 불가”로 본다.

`scripts/llm-call.sh`는 모든 provider 호출을 `cache/llm-adapter-calls.jsonl`에 남긴다. 실패 레코드는 `health_class`와 `failure_reason`을 가진다. `moai-telemetry-report`는 최신 E2E 기준의 `current.status`와 7일 누적 기준의 `history.status`를 분리한다. 과거 runtime failure가 남아 있어도 최신 E2E 이후 health-relevant error가 없으면 `MoAI telemetry report: OK (history=DEGRADED)`처럼 표시한다.

Adapter timeout은 `timeout` → `gtimeout` → Python `subprocess.run(timeout=...)` 순서로 강제한다. macOS에서 GNU timeout이 PATH에 없더라도 provider CLI가 무기한 대기하지 않게 해야 한다.

| field | 의미 |
|---|---|
| `health_class=ok` | 정상 호출 |
| `health_class=expected_offline` | office-only local provider가 현재 네트워크에서 닿지 않음 |
| `health_class=smoke` | `doctor --live` 같은 의도적 점검 호출 |
| `health_class=sandbox_blocked` | 실행 환경 제한으로 막힘 |
| `health_class=runtime_failure` | 실제 provider 실행 실패 |

대표 `failure_reason`은 `timeout`, `timeout_large_prompt`, `missing_executable`, `usage_error`, `auth_error`, `quota_or_rate_limit`, `prompt_too_large`, `provider_offline`, `expected_offline`, `smoke_failure`, `runtime_error`다.

기존 로그 보정:

```bash
~/.claude/scripts/normalize-llm-adapter-telemetry.py --json
~/.claude/scripts/normalize-llm-adapter-telemetry.py --write --json
```

`scripts/llm-usage.py`는 `expected_offline`, `smoke`, `sandbox_blocked`를 adapter health 경고율에서 제외하고, 실패 사유별 집계를 따로 표시한다.

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
