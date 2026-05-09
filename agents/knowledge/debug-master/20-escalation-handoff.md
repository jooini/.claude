# 에스컬레이션과 인계

> 세 번 실패했으면 더 세게 추측하지 말고, 더 좋은 컨텍스트로 넘긴다.

---

## 1. 에스컬레이션 기준

디버깅을 계속할수록 정보가 늘어야 한다.
세 번의 가설 검증이 실패했는데 범위가 줄지 않았다면 접근을 바꾼다.

에스컬레이션 신호:

- [ ] 같은 가설을 반복하고 있다.
- [ ] 재현 실패가 계속된다.
- [ ] 운영 영향이 커지고 있다.
- [ ] 권한 또는 도메인 지식이 부족하다.
- [ ] 인프라/보안/데이터 변경 승인이 필요하다.
- [ ] 3회 수정 후 같은 증상이 남아 있다.

---

## 2. 3회 실패 규칙

```markdown
| 시도 | 가설 | 검증 | 결과 | 다음 판단 |
|------|------|------|------|-----------|
| 1 | cache stale | cache bypass | 실패 유지 | 캐시 제외 |
| 2 | provider timeout | provider mock | 실패 유지 | 외부 API 제외 |
| 3 | DB lock | pg_locks 확인 | lock 없음 | DB lock 제외 |
```

세 번 실패하면 다음 중 하나를 한다.

- [ ] 재현 조건을 다시 정의한다.
- [ ] 더 넓은 계층에서 수집한다.
- [ ] 도메인 담당자에게 인계한다.
- [ ] 운영 영향이 있으면 incident lead에게 에스컬레이션한다.

---

## 3. 좋은 인계의 조건

인계는 "잘 모르겠습니다"가 아니다.
다음 사람이 같은 길을 다시 걷지 않도록 지도와 제외 근거를 넘기는 것이다.

포함할 것:

- [ ] 증상 요약
- [ ] 영향 범위
- [ ] 재현 방법
- [ ] 수집한 증거 위치
- [ ] 검증한 가설과 결과
- [ ] 제외한 후보
- [ ] 남은 후보
- [ ] 위험한 변경 또는 금지 행동
- [ ] 필요한 권한 또는 담당자

---

## 4. 인계 템플릿

```markdown
# Debug Handoff

## Summary
- symptom:
- started_at:
- impact:
- current_status:

## Reproduction
```bash
./scripts/reproduce-checkout.sh
```

## Evidence
- trace_ids:
- logs:
- dashboards:
- db snapshots:

## Tried
| hypothesis | experiment | result |
|------------|------------|--------|
| | | |

## Excluded
- cache:
- external provider:
- DB lock:

## Remaining Suspects
- 

## Risks
- 

## Next Recommended Step
- 
```

---

## 5. 재현 패키지 만들기

```bash
mkdir -p /tmp/debug-handoff/logs /tmp/debug-handoff/requests

cp /tmp/timeline-abc-123.log /tmp/debug-handoff/logs/
cp /tmp/request.json /tmp/debug-handoff/requests/
cp /tmp/environment-snapshot.txt /tmp/debug-handoff/

tar -czf /tmp/debug-handoff.tar.gz -C /tmp debug-handoff
```

민감정보를 포함할 수 있으므로 공유 전에 반드시 마스킹한다.

```bash
tar -tzf /tmp/debug-handoff.tar.gz
```

---

## 6. 코드 컨텍스트 인계

```bash
rg "createOrder|reserveStock|authorizePayment" src tests -n \
    > /tmp/debug-handoff/code-references.txt

git status --short > /tmp/debug-handoff/git-status.txt
git diff -- src/order src/inventory > /tmp/debug-handoff/current-diff.patch
```

현재 워크트리에 임시 로그나 실험 코드가 있으면 명확히 표시한다.
다음 사람이 그것을 production fix로 오해하면 안 된다.

---

## 7. 운영 인계

운영 장애 인계에는 현재 완화 상태가 중요하다.

```markdown
## Production State
- feature flags changed:
    - `new-checkout=false`, expires 2026-05-09T12:00+09
- log level:
    - api debug for tenant A, expires in 10 minutes
- rollback:
    - not executed
- customer impact:
    - checkout failures reduced from 12% to 1.5%
- watch:
    - dashboard checkout-error-rate
```

임시 조치의 만료 시각을 반드시 남긴다.

---

## 8. 질문을 좋은 형태로 바꾸기

나쁜 질문:

- 결제 쪽 좀 봐주세요.
- 운영이 이상합니다.
- DB 문제 같아요.

좋은 질문:

- `traceId=abc`에서 `payment.authorize.start` 후 5초 timeout입니다. provider mock에서는 통과하고 실제 provider만 실패합니다. provider credentials와 network ACL 확인이 필요합니다.
- 스테이징과 운영 모두 schema version 103인데 운영에서만 `orders_user_created_at` index가 없습니다. index 생성 이력 확인이 필요합니다.

---

## 9. 에스컬레이션 대상 선택

| 상황 | 대상 |
|------|------|
| API 계약 불일치 | backend owner |
| UI 상태 재현 필요 | frontend owner |
| DB lock/index/migration | database owner |
| 네트워크/TLS/DNS | ops owner |
| 보안/인증/권한 | security 또는 identity owner |
| 요구사항 모호 | product owner |
| 테스트 flaky | QA/test owner |

정확한 대상에게 넘기면 왕복 시간이 줄어든다.

---

## 10. 인계 전 자기 점검

- [ ] 같은 명령을 다음 사람이 실행할 수 있는가?
- [ ] 실패한 시도를 숨기지 않았는가?
- [ ] 제외 근거가 증거 기반인가?
- [ ] 민감정보를 제거했는가?
- [ ] 임시 변경과 영구 수정이 구분되는가?
- [ ] 가장 추천하는 다음 행동이 하나인가?

---

## 11. 완료 기준

- [ ] 인계 문서만으로 현재 상태를 이해할 수 있다.
- [ ] 재현 방법과 증거 위치가 있다.
- [ ] 실패한 가설과 제외 후보가 정리되었다.
- [ ] 남은 리스크와 필요한 권한이 명확하다.
- [ ] 운영 임시 조치의 만료와 복구 방법이 기록되었다.
