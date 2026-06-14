---
name: audit-service-coverage-flake-2026-06-07
description: identity-hub test_audit_service.py::test_log_event_omits_none_values 는 `--cov` 옵션과 결합 시 race condition 으로 flake. pre-existing
metadata:
  type: project
---

`tests/unit/test_audit_service.py::test_log_event_omits_none_values` (88줄) 는 단독/파일 단위 실행 시 PASS, **전체 + `--cov=app`** 조합 실행 시 종종 FAIL.

**증상:** `json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)` — audit log 파일이 비어 있음.

**원인:** AuditService 가 `QueueHandler` + 백그라운드 `QueueListener` 구조라 `log_event()` 호출 후 즉시 file flush 보장 없음. 같은 파일의 `test_log_event_writes_json` (37줄) 은 명시적으로 `audit_svc.close()` 를 호출해 flush 를 강제하지만, `test_log_event_omits_none_values` 는 close 호출 없이 바로 file read 함.

`--cov` 옵션이 coverage instrumentation 으로 thread scheduling 을 변경 → queue listener flush 가 read 보다 늦어지는 race 발생.

**검증:**
- baseline (`git stash` 상태) 에서도 `--cov` 와 함께 실행 시 FAIL 재현 → pre-existing
- `--cov` 없이 실행하면 510/0 PASS
- `-p no:randomly` 로 순서 고정해도 511/0 PASS (특정 실행 순서에 race 의존)

**Why:** 사용자가 회귀 카운트 검증 요구할 때 이 한 건이 잡혀 "내 변경 때문" 으로 오인할 수 있다. 실제로는 cov instrumentation 의 thread timing 영향.

**How to apply:** identity-hub 에서 회귀 분석할 때:
1. 신규 테스트 후 FAIL 발생 시 baseline (`git stash`) 동일 옵션으로 즉시 재현 확인
2. baseline 에서도 같은 FAIL 이면 pre-existing flake — 신규 코드와 무관
3. 근본 수정 권고: `test_log_event_omits_none_values` 87줄 다음에 `audit_svc.close()` 추가 (다른 테스트들과 동일 패턴)
4. 본 작업 범위 외 — 별도 fix 커밋으로 분리

같은 코드베이스에서 cov 조건부 flake 발견 시 [[identity-hub-coverage-drift-2026-06-07]] 의 baseline 재측정 프로토콜 적용.
