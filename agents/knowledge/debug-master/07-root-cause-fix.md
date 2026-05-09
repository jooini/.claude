# 근본 원인 수정

> Phase 6: FIX. 수정은 증상을 숨기는 것이 아니라 원인을 제거하는 최소 변경이어야 한다.

---

## 1. 수정 단계의 목표

근본 원인 수정은 검증된 가설을 코드, 설정, 데이터, 운영 절차 중 올바른 위치에서 바로잡는 단계다.
이 단계의 핵심은 변경 범위를 작게 유지하면서 재발 가능성을 낮추는 것이다.

수정 전 확인:

- [ ] 원인 가설이 검증되었는가?
- [ ] 실패를 재현하는 테스트 또는 스크립트가 있는가?
- [ ] 수정 위치가 원인과 직접 연결되는가?
- [ ] 사이드 이펙트가 예상되는 호출자가 정리되었는가?
- [ ] 롤백 방법이 있는가?

---

## 2. 최소 변경 원칙

| 좋은 수정 | 나쁜 수정 |
|-----------|-----------|
| lock 순서만 통일 | 주문 모듈 전체 리팩터 |
| null 입력 검증 추가 | try/catch로 모든 에러 삼킴 |
| timeout 원인 쿼리 최적화 | timeout 값을 10배 증가 |
| cache invalidation 위치 수정 | cache 전체 비활성화 |
| feature flag 기본값 수정 | 운영 설정 전체 재작성 |

최소 변경은 "작게 보이기"가 아니라 "원인에 가장 가까운 변경"이다.

---

## 3. 증상 완화와 원인 수정 구분

| 조치 | 유형 | 비고 |
|------|------|------|
| 재시작 | 완화 | 메모리 누수 원인 미해결 |
| timeout 증가 | 완화 | 지연 원인 미해결 가능 |
| retry 추가 | 완화/수정 | idempotency 없으면 위험 |
| lock 순서 통일 | 수정 | deadlock 원인 제거 |
| DB index 추가 | 수정 | slow query 원인 제거 |
| 입력 검증 추가 | 수정 | 잘못된 상태 차단 |

긴급 상황에서는 완화를 먼저 할 수 있다.
단, 완화 조치와 근본 수정은 티켓이나 기록에서 분리한다.

---

## 4. 예시: race condition 수정

문제 코드:

```typescript
async function reserveStock(productId: string, quantity: number) {
    const product = await repository.findById(productId);
    if (product.stock < quantity) {
        throw new Error('out of stock');
    }
    product.stock -= quantity;
    await repository.save(product);
}
```

수정 코드:

```typescript
async function reserveStock(productId: string, quantity: number) {
    const result = await dataSource.query(
        `
        UPDATE products
        SET stock = stock - $2
        WHERE id = $1
          AND stock >= $2
        RETURNING id, stock
        `,
        [productId, quantity],
    );

    if (result.length === 0) {
        throw new Error('out of stock');
    }
}
```

읽고 쓰는 사이의 경쟁을 없애기 위해 조건부 atomic update를 사용한다.
코드 양보다 동시성 의미가 중요하다.

---

## 5. 예시: Python 예외 체인 보존

문제 코드:

```python
def load_user(user_id: str):
    try:
        return repository.get(user_id)
    except Exception:
        raise RuntimeError("failed to load user")
```

수정 코드:

```python
def load_user(user_id: str):
    try:
        return repository.get(user_id)
    except Exception as exc:
        raise RuntimeError(f"failed to load user user_id={user_id}") from exc
```

원인 예외를 보존해야 다음 장애에서 같은 디버깅을 반복하지 않는다.

---

## 6. 데이터 수정이 필요한 경우

데이터가 오염되어 있으면 코드 수정과 데이터 보정이 분리되어야 한다.

```sql
BEGIN;

UPDATE orders
SET status = 'FAILED',
    failure_reason = 'inventory reservation missing',
    updated_at = now()
WHERE status = 'PAID'
  AND NOT EXISTS (
      SELECT 1
      FROM inventory_reservations
      WHERE inventory_reservations.order_id = orders.id
  );

COMMIT;
```

운영 데이터 수정 체크리스트:

- [ ] dry-run SELECT 결과를 확인했다.
- [ ] 영향 row 수가 예상 범위다.
- [ ] 백업 또는 복구 쿼리가 있다.
- [ ] 트랜잭션으로 실행한다.
- [ ] 실행 로그를 남긴다.

---

## 7. 설정 수정이 필요한 경우

```bash
current="$(kubectl get configmap api-config -o jsonpath='{.data.FEATURE_STRICT_TOKEN}')"
echo "current FEATURE_STRICT_TOKEN=$current"

kubectl patch configmap api-config \
    --type merge \
    -p '{"data":{"FEATURE_STRICT_TOKEN":"false"}}'
```

설정 수정은 코드보다 리뷰가 약해지기 쉽다.
변경 전후 값, 적용 범위, 재시작 필요 여부를 기록한다.

---

## 8. 사이드 이펙트 분석

수정 코드의 호출자를 확인한다.

```bash
rg "reserveStock|calculatePrice|load_user" src tests -n
```

분석할 질문:

- [ ] 반환 타입이 바뀌는가?
- [ ] 예외 종류가 바뀌는가?
- [ ] 트랜잭션 범위가 바뀌는가?
- [ ] latency가 증가하는가?
- [ ] 기존 캐시 key나 이벤트 계약이 바뀌는가?

---

## 9. 수정 diff 검토 기준

```markdown
## Fix Review
- root cause: 조건 없는 stock read/update race
- fix: conditional atomic update
- files changed: inventory.repository.ts
- behavior changed: oversell 방지, out-of-stock error 증가 가능
- tests: concurrent reserve test added
- rollback: revert commit, stock correction script not needed
```

수정 설명은 리뷰어가 "왜 이 변경이 원인에 닿는지" 이해할 수 있어야 한다.

---

## 10. 금지 수정

- [ ] 에러를 catch하고 무시한다.
- [ ] 로그만 추가하고 완료한다.
- [ ] timeout만 늘리고 원인 분석을 끝낸다.
- [ ] 불필요한 리팩터를 섞는다.
- [ ] 테스트를 기대값에 맞춰 약화한다.
- [ ] 실패 재현 케이스를 삭제한다.

---

## 11. 수정 완료 기준

- [ ] 수정이 검증된 원인에 직접 연결된다.
- [ ] 변경 범위가 최소다.
- [ ] 사이드 이펙트가 검토되었다.
- [ ] 재현 스크립트가 통과한다.
- [ ] 회귀 테스트가 추가되었다.
- [ ] 운영 반영과 롤백 경로가 명확하다.
