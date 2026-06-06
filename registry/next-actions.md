---
title: Claude Config Next Actions
date: 2026-06-06 18:12 KST
status: completed
scope: claude-config
tags:
  - claude-code
  - moai
  - hooks
  - llm-routing
---

# Claude Config Next Actions

## 현재 완료 기준

2026-06-06 18:37 KST 기준 구조 문서화, 운영 레지스트리화, P0/P1/P2 개선 항목은 완료 상태다.

- `scripts/audit-claude-config.py` 통과
- generated registry 파일 freshness 검사 통과
- `scripts/project-settings-from-registry.py --check` 통과
- `git diff --check` 통과
- planned wrapper activation dry-run 7개, 실패 0개
- planned wrapper isolated execute 6개, 실패 0개
- PreToolUse guard decision 7개, current hook coverage 감사 통과
- LLM adapter threshold policy 1개, usage health 리포트 검증 통과
- 승인되지 않은 직접 LLM 호출 0개
- 발표용 문서와 Mermaid 다이어그램 Vault 복사본 동기화 완료
- `stop-composite-notification-output-router` planned definition 추가
- `pretooluse-gh-pr-pipeline` active 승격 및 settings 반영 완료
- `presentation-pipeline.json`으로 generated Mermaid 발표 입력 연결 완료
- `settings-policy.json:projection_scope`와 projection script env/MCP/permissions 일부 확대 완료

## 다음 작업 우선순위

| 우선순위 | 작업 | 목표 | 완료 기준 |
|---|---|---|---|
| 완료 | Stop notification/output router 정리 | Stop 계열 훅의 사용자 가시 출력, notification, vault write 흐름을 하나의 status-aware router로 정리 | `registry/hook-output-contracts.json` 갱신, wrapper dry-run/execute 검증, audit 통과 |
| 완료 | 단일 PreToolUse guard 유지 정책 결정 | direct로 유지할 PreToolUse 훅과 wrapper로 묶을 훅의 경계 확정 | `registry/hook-wrapper-decision-log.json`에 active-wrapper/planned-wrapper/keep-direct 판단 기록, audit 통과 |
| 완료 | planned wrapper active 승격 후보 1개 선택 | 검증된 planned wrapper 중 가장 위험이 낮은 그룹을 settings에 반영 | `pretooluse-gh-pr-pipeline` active 승격, `hooks-manifest.json`, `settings.json`, `hook-wrapper-definitions.json` 정합성 통과 |
| 완료 | LLM adapter 실패율 임계치 추가 | `cache/llm-adapter-calls.jsonl` 기반 provider/caller별 실패율과 지연시간 경고 기준 정의 | `registry/llm-adapter-thresholds.json`, `registry/llm-log-schema.json`, `scripts/llm-usage.py`, audit 항목 갱신 |
| 완료 | generated Mermaid를 발표 파이프라인에 연결 | 수동 복사 없이 발표 자료에서 최신 구조도를 재사용 | `registry/presentation-pipeline.json`이 generated diagram 파일을 PPT/문서 생성 입력으로 선언하고 audit가 stale 검사를 유지 |
| 완료 | settings projection 범위 확대 | hooks 외 settings 영역도 registry에서 생성 가능하게 단계적으로 전환 | `settings-policy.json:projection_scope`와 `scripts/project-settings-from-registry.py`가 env/MCP/permissions 일부까지 projection/check |

## 권장 실행 순서

1. `Stop notification/output router`는 planned router로 정리했다.
   - `stop-composite-notification-output-router`가 notification/audio/status/vault-write/output/finalize/TaskHub 흐름을 순서 보존 execution으로 가진다.
   - settings migration은 아직 하지 않는다. activation gate와 isolated execute evidence를 근거로 별도 승격 판단한다.

2. `PreToolUse guard 유지 정책`은 `hook-wrapper-decision-log.json:pretooluse_guard_policy`로 확정했다.
   - active wrapper: `pretooluse-bash-safety-gates`
   - active 승격: `pretooluse-gh-pr-pipeline`
   - planned wrapper: `pretooluse-git-commit-pipeline`, `pretooluse-edit-write-event-matcher`, `pretooluse-agent-event-matcher`
   - keep-direct: `mcp-deferred-guard.sh`, `askuserquestion-korean-block.sh`

3. planned wrapper 하나를 active로 승격했다.
   - `pretooluse-gh-pr-pipeline`을 선택했다. child 2개이며 `Bash(gh pr*)`에만 적용되어 남은 후보 중 settings migration blast radius가 가장 낮다.
   - 한 번에 여러 wrapper를 settings에 넣지 않는 원칙은 유지한다.

4. LLM adapter telemetry를 운영 지표로 올렸다.
   - `registry/llm-adapter-thresholds.json`이 실패율, timeout, 평균 지연시간 warning/critical 기준을 가진다.
   - `scripts/llm-usage.py --json --days 1`은 `llm_adapter.health`를 출력하고, audit가 threshold 정책과 usage 리포트 코드를 검증한다.

5. generated Mermaid를 발표 파이프라인에 연결했다.
   - `registry/presentation-pipeline.json`이 `cache/generated-docs/claude-architecture-diagrams.generated.md`를 markdown 문서와 PPTX deck source input으로 선언한다.
   - `scripts/audit-claude-config.py`가 generated diagram stale 여부와 presentation pipeline 입력 연결을 함께 검증한다.

6. settings projection 범위를 확대했다.
   - 기존 hooks-only projection에 `settings-policy.json`의 env exact/path, settings MCP server command, permission default/required guard overlay를 추가했다.
   - secret 값, MCP token, 전체 permission ordering, plugin marketplace payload는 projection 제외 범위로 남겼다.

## 참조 파일

| 파일 | 용도 |
|---|---|
| `registry/README.md` | 현재 registry 운영 규칙과 검증 항목 |
| `registry/hook-wrapper-definitions.json` | active/planned wrapper 실행 정의 |
| `registry/hook-wrapper-activation-gates.json` | planned wrapper 승격 전 gate |
| `registry/hook-wrapper-activation-report.json` | dry-run validation 결과 |
| `registry/hook-wrapper-isolated-execute-report.json` | isolated execute validation 결과 |
| `registry/hook-wrapper-decision-log.json` | 남은 후보 기반 wrapper 판단 기록 |
| `registry/hook-output-contracts.json` | Stop/PreToolUse 출력과 차단 계약 |
| `registry/llm-calls-inventory.json` | LLM 호출 가능 파일 인벤토리 |
| `registry/llm-adapter-thresholds.json` | LLM adapter health 임계치 |
| `registry/presentation-pipeline.json` | 발표 deck/문서 생성 입력 계약 |
| `scripts/audit-claude-config.py` | 전체 정합성 감사 |
| `scripts/hook-wrapper-runner.py` | wrapper dry-run/execute runner |
| `scripts/validate-hook-wrapper-activation.py` | activation dry-run 검증 |
| `scripts/validate-hook-wrapper-isolated-execute.py` | isolated execute 검증 |

## 발표 후 바로 할 체크리스트

- 발표 피드백 중 “실제 실행 순서” 관련 질문을 `registry/hook-order-review.md`에 반영한다.
- MoAI-ADK 연동 설명에서 과장된 “완전 자동” 표현을 피하고, planned/active 상태를 구분한다.
- 다음 변경 전에는 항상 `scripts/audit-claude-config.py`와 generated freshness 검사를 먼저 통과시킨다.

## 후속 백로그

| 우선순위 | 작업 | 기준 |
|---|---|---|
| P1 | 남은 planned wrapper 4개 중 1개 재선정 | `pretooluse-git-commit-pipeline`, `pretooluse-edit-write-event-matcher`, `pretooluse-agent-event-matcher`, `stop-composite-notification-output-router` 중 하나만 선택하고 isolated evidence를 먼저 보강 |
| P2 | presentation pipeline에서 실제 PPTX export 자동화 | `registry/presentation-pipeline.json`을 입력으로 쓰고, generated Mermaid를 수동 복사하지 않음 |
| P2 | LLM adapter health 알림 연결 | `llm_adapter.health.overall`을 주간 리포트 또는 Stop/SessionEnd 요약에 연결 |
| P3 | secret 없는 settings 영역 추가 projection | plugin marketplace payload와 secret 값은 제외하고 projection scope를 단계적으로 확대 |
