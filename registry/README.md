# Claude Config Registry

이 디렉토리는 `~/.claude` 설정을 플랫폼처럼 관리하기 위한 전환 레지스트리다.

현재 정본은 아직 `settings.json`, `.mcp.json`, `CLAUDE.md`, `workflows/`, `skills/`, `hooks/`에 분산되어 있다. 이 레지스트리는 그 분산 상태를 한눈에 검증하기 위한 중간 단계이며, 장기적으로는 여기서 설정과 문서를 생성하는 구조로 전환한다.

## 현재 상태

2026-06-06 18:12 KST 기준 `scripts/audit-claude-config.py`가 통과한다.

| 항목 | 값 |
|---|---:|
| 등록 훅 | 45개 |
| 통합 후보 | 18개 |
| wrapper plan | 14개 |
| wrapper definition | 11개 |
| active wrapper | 7개 |
| planned wrapper | 4개 |
| residual candidate decision | 3개 |
| planned wrapper activation gate | 4개 |
| planned wrapper activation validation | 7개, 실패 0개 |
| planned wrapper isolated execute | 6개, 실패 0개 |
| PreToolUse guard decision | 7개 |
| LLM adapter threshold policy | 1개 |
| presentation pipeline | 1개 |
| 승인되지 않은 직접 LLM 호출 | 0개 |

현재 active wrapper는 7개이며, `pretooluse-gh-pr-pipeline`은 가장 작은 planned PreToolUse 후보로 선택되어 `settings.json`에 반영됐다. 현재 planned wrapper는 `pretooluse-git-commit-pipeline`, `pretooluse-edit-write-event-matcher`, `pretooluse-agent-event-matcher`, `stop-composite-notification-output-router` 4개다. 남은 PreToolUse 그룹들은 각각 `Bash(git commit*)`, `Edit|Write`, `Agent` 사전 훅을 묶는 계획이고, Stop composite router는 notification/audio/status/vault-write/output/finalize/TaskHub 흐름을 하나의 status-aware router로 묶는 계획이다. 이 그룹들은 LLM-backed, blocking, notification/audio/network side effect를 포함하므로 settings에는 아직 반영하지 않는다. 각 planned wrapper는 `hook-wrapper-activation-gates.json`에서 active 승격 전 필수 검증을 가진다. PreToolUse direct 유지 경계는 `hook-wrapper-decision-log.json:pretooluse_guard_policy`에 7개 decision으로 기록되어 있으며, 감사가 현재 PreToolUse 훅 전체 coverage를 검증한다.

## 파일

| 파일 | 목적 |
|---|---|
| `hook-policy.json` | 이벤트별 필수 훅, 실패 정책, 운영 원칙 |
| `hook-timeout-policy.json` | 훅별/이벤트별 timeout 기준과 런타임 timeout 필수 정책 |
| `settings-policy.json` | secret 없는 `settings.json`/`.mcp.json` 필수 키·env·MCP·permission 정책 |
| `hooks-manifest.json` | `settings.json:hooks` 전체 런타임 배열의 전환기 full manifest |
| `hooks-inventory.json` | `settings.json`에서 생성한 전체 훅 45개 인벤토리 |
| `hook-consolidation-candidates.json` | hook inventory 기반 통합 후보와 위험도 분석 |
| `hook-consolidation-plan.md` | hook 통합 후보를 낮은 위험, 순서 검토, wrapper-ready, 수동 리뷰 단계로 나눈 실행계획 |
| `hook-wrapper-definitions.json` | settings 전환 후에도 유지되어야 하는 planned/active wrapper 실행 정의 |
| `hook-wrapper-plan.json` | wrapper-ready 후보를 order-preserving runner로 옮기기 위한 실행 계획 |
| `hook-wrapper-decision-log.json` | 남은 후보 기반 wrapper plan의 defer/reject/promote 판단과 사유 |
| `hook-wrapper-activation-gates.json` | planned wrapper를 active/settings로 승격하기 전 필요한 검증 gate |
| `hook-wrapper-activation-report.json` | activation gate fixture dry-run 재생 결과 |
| `hook-wrapper-isolated-execute-report.json` | temp HOME/temp git repo/stub PATH 기반 isolated execute 결과 |
| `hook-replay-fixtures.json` | wrapper dry-run/replay용 synthetic hook payload |
| `hook-order-review.json` | 남은 후보별 blocker, strategy, next action 분류 |
| `hook-order-review.md` | order-review 운영/발표용 요약 문서 |
| `hook-output-contracts.json` | Stop/PreToolUse 등 사용자 가시 출력과 차단 의미가 있는 훅의 stdout/stderr/status/audio/exit 계약 |
| `llm-calls-inventory.json` | 런타임 hooks/scripts 기준 LLM 호출 가능 파일 인벤토리 |
| `llm-routing.json` | provider-neutral task route, fallback, handoff, provider 역할과 호출 경로 |
| `llm-adapter-policy.json` | 직접 LLM CLI 호출 금지 기준과 승인된 예외 |
| `llm-log-schema.json` | shell/Python LLM 어댑터 JSONL 공통 로그 필드 |
| `llm-adapter-thresholds.json` | LLM adapter 실패율, timeout, provider별 지연시간 경고/위험 임계치 |
| `presentation-pipeline.json` | generated Mermaid 파일을 발표 deck/문서 생성 입력으로 쓰는 파이프라인 계약 |
| `../scripts/llm-router.sh` | task별 provider fallback, recursion guard, handoff cache를 담당하는 공통 라우터 |
| `../scripts/llm-router.py` | `llm-router.sh`의 실행 본체 |
| `../scripts/llm-call.sh` | shell 훅용 공통 LLM 호출 어댑터(provider/caller/timeout telemetry) |
| `../scripts/llm-usage.py` | Claude/Codex/Gemini/Ollama 사용량과 LLM 어댑터 성공률/지연시간 리포트 |
| `../scripts/generate-hook-manifest.py` | `settings.json:hooks` full manifest 생성 |
| `../scripts/generate-hook-consolidation-candidates.py` | hook 통합 후보 생성 |
| `../scripts/generate-hook-consolidation-plan.py` | hook 통합 실행계획 문서 생성 |
| `../scripts/generate-hook-wrapper-plan.py` | wrapper-ready 후보의 order-preserving migration plan 생성 |
| `../scripts/generate-hook-order-review.py` | 남은 후보의 blocker/strategy 리뷰 문서 생성 |
| `../scripts/hook-wrapper-runner.py` | stdin payload를 각 기존 hook에 순서대로 재전달하는 wrapper runner |
| `../scripts/validate-hook-wrapper-activation.py` | planned wrapper activation gate fixture dry-run 검증 리포트 생성 |
| `../scripts/validate-hook-wrapper-isolated-execute.py` | planned wrapper isolated execute 시나리오 검증 리포트 생성 |
| `../scripts/project-settings-from-registry.py` | `hooks-manifest.json`과 `settings-policy.json`에서 hooks/env/MCP/permissions 일부를 projection |
| `../scripts/generate-architecture-diagrams.py` | registry/settings 기준 발표용 Mermaid 다이어그램 생성 |
| `../cache/generated-docs/claude-architecture-diagrams.generated.md` | 자동 생성된 구조도/순서도/LLM 라우팅 표 |

## 검증

```bash
scripts/audit-claude-config.py
```

검증 대상:

- 필수 hook 이벤트와 핵심 hook 등록 여부
- `settings-policy.json` 기준 top-level/env/MCP/permissions 정합성
- `settings.json:hooks`와 `hooks-manifest.json`의 full manifest 정합성
- `hooks-manifest.json`과 `settings-policy.json`에서 projection한 settings가 현재 `settings.json`과 의미적으로 동일한지
- `settings.json`과 `hooks-inventory.json`의 훅 수/순서/명령 정합성
- `hook-consolidation-candidates.json`이 현재 hook inventory에서 재생성되는지
- `hook-consolidation-plan.md`가 현재 후보 리포트에서 재생성되는지
- `hook-wrapper-plan.json`이 현재 후보/인벤토리에서 재생성되는지
- `hook-wrapper-definitions.json`의 planned/active 정의가 wrapper plan에 유지되는지
- `hook-wrapper-decision-log.json`이 남은 후보 기반 wrapper plan을 모두 설명하는지
- `hook-wrapper-decision-log.json:pretooluse_guard_policy`가 현재 PreToolUse guard 전체의 direct/wrapper 경계를 덮는지
- `hook-wrapper-activation-gates.json`이 planned wrapper 전체와 dry-run fixture를 덮는지
- `hook-wrapper-activation-report.json`이 현재 activation gate fixture dry-run 결과에서 재생성되는지
- `hook-wrapper-isolated-execute-report.json`이 현재 isolated execute 시나리오 결과에서 재생성되고 실패 0개인지
- wrapper plan의 per-hook timeout, execution order, safe initial migration, overlap count가 일관적인지
- `hook-replay-fixtures.json`이 wrapper 대상 event/matcher fixture를 모두 제공하는지
- `hook-order-review.json`/`.md`가 현재 후보와 wrapper plan에서 재생성되는지
- 남은 후보별 blocker, strategy, next_action이 비어 있지 않은지
- `hook-output-contracts.json`이 현재 Stop 훅 전체와 PreToolUse 훅 전체의 출력/차단 계약을 덮는지
- 등록된 hook 스크립트의 존재 여부와 실행 권한
- 모든 `settings.json` hook에 런타임 `timeout`이 명시되어 있는지
- `hook-timeout-policy.json` 기준 effective timeout을 계산할 수 있는지
- `hooks-inventory.json`과 `llm-calls-inventory.json`이 생성기 출력과 일치하는지
- `claude-architecture-diagrams.generated.md`가 생성기 출력과 일치하는지
- Gemini/Codex/Ollama/Gemma/Qwen-ini 런타임 호출 경로가 하나 이상 존재하는지
- 공통 LLM 라우터 `scripts/llm-router.sh`와 `scripts/llm-router.py`가 존재하고 실행 가능하며 라우팅 문서에 등록되어 있는지
- 공통 shell LLM 어댑터 `scripts/llm-call.sh`가 존재하고 실행 가능하며 라우팅 문서에 등록되어 있는지
- 등록된 hook 스크립트가 Gemini/Codex/ini를 직접 호출하지 않고 `scripts/llm-call.sh`를 통하는지
- 런타임 hooks/scripts의 직접 LLM CLI 호출이 `llm-adapter-policy.json` 승인 예외 안에만 존재하는지
- shell/Python LLM 어댑터가 `llm-log-schema.json`의 공통 로그 필드를 기록하는지
- `scripts/llm-usage.py`가 `cache/llm-adapter-calls.jsonl`과 공통 로그 필드를 읽어 provider/caller/status를 집계하는지
- `llm-adapter-thresholds.json`의 실패율, timeout, 평균 지연시간 임계치가 usage 리포트에서 health로 평가되는지
- `llm-routing.json`이 `default/scan/implement/review/private/rescue/summarize` task route와 `cache/llm-handoff/current.json` handoff 경로를 선언하는지
- `presentation-pipeline.json`이 generated Mermaid 파일을 PPTX/문서 입력으로 선언하고 stale check를 유지하는지
- AskUserQuestion 한글 직렬화 버그 방어 훅 등록 여부
- Codex가 MCP가 아닌 CLI/Plugin/Skill 경로로 문서화되어 있는지
- MoAI hardcoded 외부 사용자 경로 제거 여부
- 핵심 MCP 서버 등록 여부
- LLM 라우팅 레지스트리와 `settings.json` 환경값 정합성

## 훅 인벤토리 갱신

`settings.json`의 hooks가 바뀌면 아래 명령으로 인벤토리를 재생성한다.

```bash
scripts/generate-hook-inventory.py --write
scripts/generate-hook-manifest.py --write
scripts/generate-hook-consolidation-candidates.py --write
scripts/generate-hook-consolidation-plan.py --write
scripts/generate-hook-wrapper-plan.py --write
scripts/validate-hook-wrapper-activation.py --write
scripts/validate-hook-wrapper-isolated-execute.py --write
scripts/generate-hook-order-review.py --write
scripts/project-settings-from-registry.py --check
scripts/generate-llm-call-inventory.py --write
scripts/generate-architecture-diagrams.py --write
scripts/audit-claude-config.py
```

## 운영 원칙

- 새 hook은 먼저 `hook-policy.json`에 목적과 실패 정책을 추가한다.
- `settings-policy.json`에는 토큰/비밀번호를 넣지 않고 필수 키, 서버명, env key, permission guard만 둔다.
- `settings-policy.json:projection_scope`에는 hooks, env exact/path, MCP server command, permission guard처럼 secret 없이 projection 가능한 범위만 둔다.
- 새 hook은 `settings.json`에 `timeout`을 반드시 명시하고, 기본 정책과 다르면 `hook-timeout-policy.json`에 override를 추가한다.
- `settings.json` hook 배열을 바꾼 뒤에는 반드시 `hooks-manifest.json`과 `hooks-inventory.json`을 재생성한다.
- `hook-consolidation-candidates.json`은 자동 병합 지시가 아니라 검토용 후보 목록이다. P0/blocking 후보는 수동 리뷰 없이 합치지 않는다.
- 실제 통합은 `hook-consolidation-plan.md`의 Phase 1부터 진행한다. 낮은 위험 후보가 0개면 순서 검토 대상부터 order-preserving wrapper 설계를 먼저 하고, 각 단계 후 감사와 생성물 stale 검사를 통과해야 한다.
- wrapper 적용 전에는 `hook-wrapper-plan.json`에서 `safe_initial_migration=true`인 후보만 `dry_run_command`로 확인한다.
- 실제 settings 전환 후보는 먼저 `hook-wrapper-definitions.json`에 planned 정의로 고정한다. 후보 기반 plan만 믿고 settings를 바꾸면 원본 hook이 사라진 뒤 runner 실행 정의도 사라질 수 있다.
- planned/active로 승격하지 않는 후보 기반 plan은 `hook-wrapper-decision-log.json`에 defer/reject/promote 판단과 다음 조치를 남긴다.
- LLM adapter 임계치는 `llm-adapter-thresholds.json`에서 조정하고, 변경 후 `scripts/llm-usage.py --json --days 1`과 audit를 함께 확인한다.
- LLM provider fallback 정책은 `llm-routing.json:tasks`에서 조정하고, 변경 후 `scripts/llm-router.sh doctor`와 audit를 함께 확인한다.
- planned wrapper를 active로 승격하기 전에는 `hook-wrapper-activation-gates.json`의 금지 execute 범위와 isolated validation 요구사항을 먼저 만족해야 한다.
- planned wrapper의 dry-run fixture 재생 결과는 `scripts/validate-hook-wrapper-activation.py --write`로 갱신하고 감사가 실패 0개를 검증한다.
- planned wrapper의 isolated execute 결과는 `scripts/validate-hook-wrapper-isolated-execute.py --write`로 갱신하고 감사가 실패 0개를 검증한다.
- settings에 들어가는 wrapper command는 반드시 `--execute --allow-side-effects`를 포함해야 한다. 감사 스크립트가 이 조건을 강제한다.
- wrapper는 stdin payload, 기존 hook order, per-hook timeout, 기존 hook stdout/stderr 출력을 보존해야 하며, 실행 요약은 `cache/hook-wrapper-runs.jsonl`에 JSONL로 기록한다.
- PreToolUse처럼 차단 의미가 있는 wrapper는 `preserve_first_nonzero_exit`와 `stop_after_blocking_exit` 실행 계약을 가져야 하며, 감사 스크립트가 이 조건을 강제한다.
- statusMessage/LLM/mixed async 후보는 별도 리뷰 전까지 settings에 반영하지 않는다.
- 남은 후보는 `hook-order-review.md`의 strategy를 기준으로 처리한다. `order-preserving-router-required`, `status-aware-wrapper-required`, `split-sync-guard-before-async-router`는 서로 다른 설계가 필요하다.
- Stop/PreToolUse 훅 wrapper 전환 전에는 `hook-output-contracts.json`에서 stdout/stderr/statusMessage/audio/notification/exit 계약을 먼저 갱신하고 감사가 통과해야 한다.
- `hooks-manifest.json` 또는 `settings-policy.json`의 projection 대상 범위를 바꿨다면 `scripts/project-settings-from-registry.py --write`로 `settings.json`에 projection한 뒤 감사한다.
- hooks/scripts의 LLM 호출 경로를 바꾼 뒤에는 반드시 `llm-calls-inventory.json`을 재생성한다.
- 새 LLM 호출 경로는 `llm-routing.json`에 provider, task route, entrypoint, privacy tier를 추가한다.
- 새 shell hook에서 Gemini/Codex/ini를 직접 호출해야 하면 먼저 `scripts/llm-call.sh` 사용을 검토한다.
- `settings.json`에 등록되는 hook은 Gemini/Codex/ini 직접 호출 금지. 예외가 필요하면 감사 스크립트와 레지스트리에 이유를 먼저 남긴다.
- 비등록 scripts에서 직접 provider CLI가 필요한 경우에도 `llm-adapter-policy.json`에 예외 사유를 남긴 뒤 감사가 통과해야 한다.
- LLM 어댑터 로그 필드를 추가/변경하면 `llm-log-schema.json`과 감사 스크립트를 같이 갱신한다.
- LLM 어댑터 로그 필드를 추가/변경하면 `scripts/llm-usage.py`의 adapter telemetry 집계도 같이 갱신한다.
- 발표용 구조도 숫자는 직접 수정하지 않고 `scripts/generate-architecture-diagrams.py --write`로 갱신한다.
- `CLAUDE.md`나 workflow 문서의 실행 경로가 바뀌면 감사 스크립트가 실패하도록 만든다.
- disabled/archive hook은 복구 계획이 없으면 삭제 후보로 분류한다.
