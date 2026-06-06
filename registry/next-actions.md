---
title: Claude Config Next Actions
date: 2026-06-06 18:01 KST
status: active
scope: claude-config
tags:
  - claude-code
  - moai
  - hooks
  - llm-routing
---

# Claude Config Next Actions

## 현재 완료 기준

2026-06-06 18:01 KST 기준 구조 문서화와 1차 운영 레지스트리화는 완료 상태다.

- `scripts/audit-claude-config.py` 통과
- generated registry 파일 freshness 검사 통과
- `scripts/project-settings-from-registry.py --check` 통과
- `git diff --check` 통과
- planned wrapper activation dry-run 8개, 실패 0개
- planned wrapper isolated execute 5개, 실패 0개
- 승인되지 않은 직접 LLM 호출 0개
- 발표용 문서와 Mermaid 다이어그램 Vault 복사본 동기화 완료

## 다음 작업 우선순위

| 우선순위 | 작업 | 목표 | 완료 기준 |
|---|---|---|---|
| P0 | Stop notification/output router 정리 | Stop 계열 훅의 사용자 가시 출력, notification, vault write 흐름을 하나의 status-aware router로 정리 | `registry/hook-output-contracts.json` 갱신, wrapper dry-run/execute 검증, audit 통과 |
| P0 | 단일 PreToolUse guard 유지 정책 결정 | direct로 유지할 PreToolUse 훅과 wrapper로 묶을 훅의 경계 확정 | `registry/hook-wrapper-decision-log.json`에 promote/defer/reject 판단 기록, audit 통과 |
| P1 | planned wrapper active 승격 후보 1개 선택 | 검증된 planned wrapper 중 가장 위험이 낮은 그룹을 settings에 반영 | 승격 전/후 `hooks-manifest.json`, `settings.json`, `hook-wrapper-definitions.json` 정합성 통과 |
| P1 | LLM adapter 실패율 임계치 추가 | `cache/llm-adapter-calls.jsonl` 기반 provider/caller별 실패율과 지연시간 경고 기준 정의 | `registry/llm-log-schema.json`, `scripts/llm-usage.py`, audit 항목 갱신 |
| P2 | generated Mermaid를 발표 파이프라인에 연결 | 수동 복사 없이 발표 자료에서 최신 구조도를 재사용 | generated diagram 파일을 PPT/문서 생성 입력으로 사용하고 stale 검사를 유지 |
| P2 | settings projection 범위 확대 | hooks 외 settings 영역도 registry에서 생성 가능하게 단계적으로 전환 | `settings-policy.json`과 projection script가 env/MCP/permissions 일부까지 검증 |

## 권장 실행 순서

1. `Stop notification/output router`부터 처리한다.
   - 현재 hook 복잡도에서 남은 큰 덩어리다.
   - vault write wrapper는 이미 active라, notification/status/output 계열을 분리해 설계하면 충돌 범위가 줄어든다.

2. `PreToolUse guard 유지 정책`을 문서로 먼저 확정한다.
   - blocking 의미가 있는 guard는 무리하게 합치면 사용자 승인/차단 의미가 바뀔 수 있다.
   - direct 유지가 맞는 훅은 유지 사유를 decision log에 남기는 편이 낫다.

3. planned wrapper 하나만 active로 승격한다.
   - 한 번에 여러 wrapper를 settings에 넣지 않는다.
   - 승격 단위는 dry-run과 isolated execute가 이미 통과한 그룹 중 위험이 가장 낮은 것으로 선택한다.

4. LLM adapter telemetry를 운영 지표로 올린다.
   - 현재는 호출 경로와 로그 스키마 정합성까지 맞춘 상태다.
   - 다음 단계는 실패율, timeout, provider별 지연시간을 기준으로 alert threshold를 정하는 것이다.

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
| `scripts/audit-claude-config.py` | 전체 정합성 감사 |
| `scripts/hook-wrapper-runner.py` | wrapper dry-run/execute runner |
| `scripts/validate-hook-wrapper-activation.py` | activation dry-run 검증 |
| `scripts/validate-hook-wrapper-isolated-execute.py` | isolated execute 검증 |

## 발표 후 바로 할 체크리스트

- 발표 피드백 중 “실제 실행 순서” 관련 질문을 `registry/hook-order-review.md`에 반영한다.
- MoAI-ADK 연동 설명에서 과장된 “완전 자동” 표현을 피하고, planned/active 상태를 구분한다.
- 다음 변경 전에는 항상 `scripts/audit-claude-config.py`와 generated freshness 검사를 먼저 통과시킨다.
