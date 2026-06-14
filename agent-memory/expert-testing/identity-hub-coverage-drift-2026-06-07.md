---
name: identity-hub-coverage-drift-2026-06-07
description: 사용자가 제공한 coverage 측정치와 실측 baseline 이 크게 어긋날 수 있다 — 작업 시작 전 동일 명령으로 직접 재측정해 비교할 것
metadata:
  type: feedback
---

identity-hub P1 coverage gap 작업에서 사용자가 인용한 baseline 측정치와 실측 baseline 이 크게 달랐다.

**사용자 인용 (분석 문서 기반):**
- oauth.py: 47.1% (54 라인 미커버)
- clients.py: 89.2% (14 라인 미커버)
- config.py: 98.3% (1 라인 미커버)
- exceptions.py: 95.3% (4 라인 미커버)
- 전체: 78.1%

**실측 baseline (`pytest --cov=app --cov-report=term -q`):**
- oauth.py: 100% (0 라인 미커버) ← 이미 100%
- clients.py: 100% (0 라인 미커버) ← 이미 100%
- config.py: 100% (0 라인 미커버) ← 이미 100%
- exceptions.py: 95% (4 라인 미커버) ← 일치
- 전체: 80% (740 missed)

**원인 추정:**
- 사용자 측정과 실측의 명령/옵션이 달랐을 가능성 (`--no-cov` vs `--cov`, 다른 마커, 파일 필터 등)
- coverage 측정 시점의 코드 상태가 달랐을 가능성 (다른 브랜치/커밋)
- coverage tool 의 분기 vs 라인 측정 모드 차이

**Why:** 사용자 인용 데이터를 그대로 믿고 작업하면 ROI 가 0인 테스트를 작성하게 된다. exceptions.py 의 4 라인은 진짜 갭이라 보강이 의미 있었지만, oauth/clients/config 100% 위에 추가한 테스트는 라인 회복 0. 다만 회귀 가드 가치는 남음.

**How to apply:** coverage 갭을 보고받을 때:
1. 작업 시작 전 사용자가 사용한 것과 동일한 pytest 명령으로 직접 측정
2. 사용자 데이터와 실측이 5%p 이상 다르면 즉시 alert
3. 차이의 원인을 사용자에게 확인 (명령? 환경? 시점?)
4. 동의된 baseline 위에서 작업 진행

[[audit-service-coverage-flake-2026-06-07]] 도 같은 측정 검증 과정에서 발견됨.
