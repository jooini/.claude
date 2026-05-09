# 간헐적 버그

> 간헐적 버그는 운이 나쁜 버그가 아니라 조건이 아직 보이지 않는 버그다.

---

## 1. 간헐적 버그의 특징

간헐적 버그는 재현 확률이 낮아 추측 수정으로 흐르기 쉽다.
핵심은 실패 확률을 높이고, 실패와 성공의 차이를 통계적으로 비교하는 것이다.

대표 원인:

- [ ] 경쟁 조건
- [ ] 시간 의존 로직
- [ ] 외부 API 지연
- [ ] flaky test fixture
- [ ] 리소스 고갈
- [ ] 캐시 만료 타이밍
- [ ] 랜덤 데이터 충돌
- [ ] 환경 차이

---

## 2. 실패 확률 측정

```bash
set -euo pipefail

total="${TOTAL:-200}"
failure=0
success=0

for i in $(seq 1 "$total"); do
    if ./scripts/reproduce-flaky.sh >"/tmp/flaky-$i.log" 2>&1; then
        success=$((success + 1))
    else
        failure=$((failure + 1))
    fi
done

echo "total=$total success=$success failure=$failure"
```

수정 전 실패율이 7%라면 수정 후 10회 성공으로는 부족하다.
충분한 반복 횟수를 정해야 한다.

---

## 3. 조건 증폭

실패 확률을 높이는 방법:

| 조건 | 방법 |
|------|------|
| 동시성 | 병렬 요청 수 증가 |
| 타이밍 | 인위적 delay 삽입 |
| 리소스 | CPU/memory 제한 |
| 네트워크 | latency/loss 주입 |
| 데이터 | 경계값 fixture 집중 |
| 순서 | test order randomize |

---

## 4. 동시성 증폭

```bash
seq 1 100 | xargs -I{} -P 50 bash -c '
    curl -sS -X POST "$BASE_URL/api/jobs" \
        -H "content-type: application/json" \
        -d "{\"jobKey\":\"same-key\",\"requestId\":\"req-{}\"}"
' > /tmp/jobs.jsonl

jq -r '.status' /tmp/jobs.jsonl | sort | uniq -c
```

같은 key에 요청을 몰아 race window를 키운다.
서로 다른 key로 보내면 경쟁 조건이 재현되지 않을 수 있다.

---

## 5. 테스트 order randomize

```bash
pytest tests -q --random-order --random-order-seed=20260509
```

```typescript
// Jest에서 seed를 로그로 남긴다.
console.info({
    event: 'test.seed',
    seed: process.env.TEST_SEED,
});
```

테스트가 순서에 따라 실패하면 shared fixture, 전역 상태, DB cleanup 누락을 의심한다.

---

## 6. 시간 고정

```python
from freezegun import freeze_time

def test_token_expiry_boundary():
    with freeze_time("2026-05-09 23:59:59"):
        token = issue_token(ttl_seconds=1)

    with freeze_time("2026-05-10 00:00:01"):
        assert is_expired(token)
```

현재 시간, timezone, 날짜 경계는 간헐성을 만든다.
테스트에서는 clock을 주입하거나 freeze한다.

---

## 7. 랜덤성 통제

```python
import random

def test_recommendation_is_stable():
    random.seed(20260509)
    result = recommend(["a", "b", "c"], limit=2)
    assert result == ["a", "c"]
```

```typescript
import seedrandom from 'seedrandom';

const rng = seedrandom('2026-05-09');
const value = rng();
```

랜덤 seed를 로그에 남기면 실패를 다시 재현할 수 있다.

---

## 8. 성공/실패 샘플 비교

```bash
jq -S . /tmp/success-sample.json > /tmp/success.sorted.json
jq -S . /tmp/failure-sample.json > /tmp/failure.sorted.json
diff -u /tmp/success.sorted.json /tmp/failure.sorted.json
```

비교할 축:

- [ ] 실행 시간
- [ ] worker id
- [ ] thread id
- [ ] seed
- [ ] input size
- [ ] feature flag
- [ ] DB row version
- [ ] cache hit/miss

---

## 9. 간헐적 운영 장애

운영에서만 간헐적으로 발생하면 샘플링 로그를 설계한다.

```typescript
const shouldSample = userId === debugUserId || Math.random() < 0.001;

if (shouldSample) {
    logger.info({
        event: 'debug.sample',
        traceId,
        userId,
        cacheHit,
        databaseReplica,
        workerId: process.env.HOSTNAME,
    });
}
```

샘플링은 로그 비용을 제어하지만 원인 신호를 잃을 수 있다.
실패 요청은 항상 상세 로그를 남기는 편이 좋다.

---

## 10. Flaky test 대응

Flaky test를 그냥 재시도하면 신뢰도가 떨어진다.

처리 순서:

1. 실패 seed와 로그를 보존한다.
2. 반복 실행으로 실패율을 측정한다.
3. test isolation, time, network, async wait를 확인한다.
4. 원인을 고친 뒤 반복 실행으로 안정성을 확인한다.
5. 정말 외부 의존성 문제면 격리하거나 quarantine한다.

---

## 11. 완료 기준

- [ ] 실패율을 숫자로 기록했다.
- [ ] 실패 확률을 높이는 조건을 찾았다.
- [ ] 성공/실패 샘플 차이를 비교했다.
- [ ] seed, 시간, 동시성 조건이 보존되었다.
- [ ] 수정 후 충분한 반복 횟수에서 실패하지 않는다.
- [ ] 재발 시 원인을 볼 수 있는 로그가 있다.
