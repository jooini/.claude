# 프로덕션 디버깅

> 운영 디버깅의 첫 원칙은 사용자를 더 아프게 하지 않는 것이다.

---

## 1. 운영 디버깅 목표

프로덕션에서는 원인 분석과 영향 최소화를 동시에 해야 한다.
로컬 디버깅처럼 자유롭게 로그를 늘리거나 데이터를 바꿀 수 없다.

우선순위:

1. 사용자 영향 파악
2. 확산 방지 또는 완화
3. 안전한 증거 수집
4. 근본 원인 검증
5. 수정, 롤백, 모니터링

---

## 2. 금지 행동

- [ ] 운영 DB에서 검증 없이 UPDATE 실행
- [ ] 전체 DEBUG 로그 장시간 활성화
- [ ] 재현을 위해 운영에 부하 발생
- [ ] 임의 재시작 반복
- [ ] 민감정보를 로컬로 다운로드
- [ ] 원인 미확인 상태에서 여러 설정 동시 변경

---

## 3. 영향도 확인

```bash
curl -sS "$PROMETHEUS/api/v1/query" \
    --data-urlencode 'query=sum(rate(http_requests_total{status=~"5.."}[5m])) by (route)' \
    | jq .
```

확인할 것:

- [ ] 영향 route 또는 기능
- [ ] 5xx 비율
- [ ] 사용자 수
- [ ] 특정 tenant 또는 region
- [ ] 시작 시각
- [ ] 최근 배포/설정 변경

---

## 4. 안전한 로그 레벨 변경

```typescript
app.post('/admin/debug-log-level', adminGuard, (req, res) => {
    const level = req.body.level;
    const ttlMs = Math.min(Number(req.body.ttlMs ?? 300_000), 300_000);

    logger.level = level;
    setTimeout(() => {
        logger.level = 'info';
    }, ttlMs);

    res.json({ level, ttlMs });
});
```

운영 DEBUG는 TTL과 대상 제한이 필수다.
특정 trace id, user id, tenant로 좁힐 수 있으면 더 안전하다.

---

## 5. Feature flag 완화

```bash
curl -sS -X PATCH "$FLAG_ADMIN_URL/flags/new-checkout" \
    -H "authorization: Bearer $ADMIN_TOKEN" \
    -H "content-type: application/json" \
    -d '{
        "enabled": false,
        "reason": "checkout 500 mitigation",
        "expiresAt": "2026-05-09T12:00:00+09:00"
    }'
```

flag 변경 후 반드시 지표를 확인한다.
완화가 효과 없으면 즉시 되돌리고 다른 가설로 이동한다.

---

## 6. 롤백 판단

롤백이 우선인 경우:

- [ ] 최근 배포 직후 장애가 시작되었다.
- [ ] 영향도가 크고 완화가 없다.
- [ ] 데이터 마이그레이션이 irreversible하지 않다.
- [ ] 롤백 위험이 현재 장애보다 낮다.

롤백 전 확인:

- [ ] DB schema가 이전 버전과 호환되는가?
- [ ] message/event contract가 호환되는가?
- [ ] feature flag와 설정도 함께 되돌려야 하는가?
- [ ] 롤백 후 확인할 지표가 정해졌는가?

---

## 7. 운영 DB 읽기 전용 수집

```sql
SELECT status, COUNT(*)
FROM orders
WHERE created_at >= now() - interval '30 minutes'
GROUP BY status
ORDER BY COUNT(*) DESC;
```

```bash
psql "$DATABASE_URL" \
    --set=ON_ERROR_STOP=1 \
    --command="BEGIN READ ONLY; SELECT now(); COMMIT;"
```

가능하면 read-only transaction 또는 replica를 사용한다.
운영 primary에서 무거운 query를 실행하면 장애를 키울 수 있다.

---

## 8. 개인정보 보호

```bash
rg "traceId=abc-123" /var/log/app.log \
    | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/***EMAIL***/g' \
    | sed -E 's/(Bearer )[A-Za-z0-9._-]+/\1***/g' \
    > /tmp/incident-abc-123.redacted.log
```

운영 로그와 payload에는 민감정보가 있다.
공유용 자료는 반드시 마스킹한다.

---

## 9. Canary 검증

```bash
kubectl rollout status deployment/api
kubectl get pods -l app=api -o wide
```

수정 배포 후에는 전체 트래픽을 바로 보내지 않는다.
가능하면 canary, percentage rollout, tenant 제한을 사용한다.

확인 지표:

- [ ] canary pod error rate
- [ ] latency p95/p99
- [ ] CPU/memory
- [ ] DB query count
- [ ] business success metric

---

## 10. Incident 기록

```markdown
## Incident Debug Log
- started_at: 2026-05-09T10:32:00+09:00
- detected_by: alert `checkout_5xx_high`
- impact: checkout 5xx 12%, tenant A/B only
- mitigation: disabled `new-checkout`
- evidence: trace ids abc, def, ghi
- root cause: coupon total zero validation regression
- fix: validation state machine patch
- confirmed_by: 5xx below 0.1% for 30 minutes
```

기록은 사후 리뷰와 재발 방지의 재료다.

---

## 11. 운영 디버깅 체크리스트

- [ ] 사용자 영향도를 먼저 확인했다.
- [ ] 완화와 원인 분석을 분리했다.
- [ ] 로그/쿼리/캡처의 안전 범위를 정했다.
- [ ] 변경은 하나씩 적용했다.
- [ ] 변경 후 지표를 확인했다.
- [ ] 롤백 경로가 준비되었다.

---

## 12. 완료 기준

- [ ] 장애 영향이 종료 또는 안정화되었다.
- [ ] 원인이 증거로 설명된다.
- [ ] 수정 또는 완화가 지표로 확인되었다.
- [ ] 임시 설정과 로그 레벨이 복구되었다.
- [ ] 사후 기록과 후속 액션이 남았다.
