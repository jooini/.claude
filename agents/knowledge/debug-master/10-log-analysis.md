# 로그 분석

> 로그는 사건의 타임라인이다. 단일 에러 라인이 아니라 전후 맥락을 읽어야 한다.

---

## 1. 로그 분석의 목표

로그 분석은 실패 요청의 시간순 흐름을 복원하고, 정상 요청과 다른 지점을 찾는 작업이다.
좋은 로그 분석은 "어디서 실패했는가"뿐 아니라 "어디까지는 정상인가"도 알려준다.

확인할 것:

- [ ] 실패 요청의 시작과 끝
- [ ] 마지막 정상 이벤트
- [ ] 첫 번째 비정상 이벤트
- [ ] 같은 trace id의 모든 로그
- [ ] 같은 시간대의 시스템 경고
- [ ] 정상 요청과의 차이

---

## 2. 구조화 로그

구조화 로그는 검색과 집계가 가능해야 한다.

```typescript
logger.info({
    event: 'checkout.step',
    traceId,
    userId,
    orderId,
    step: 'reserve_inventory',
    durationMs: Date.now() - startedAt,
    result: 'success',
});
```

나쁜 로그:

```text
done
failed here
something wrong
```

좋은 로그:

```json
{"event":"checkout.step","traceId":"abc","step":"reserve_inventory","durationMs":42,"result":"success"}
```

---

## 3. 상관관계 ID

trace id가 없으면 분산 시스템 로그는 조각난다.

```typescript
import { randomUUID } from 'crypto';

function traceMiddleware(req, res, next) {
    req.traceId = req.header('x-trace-id') ?? randomUUID();
    res.setHeader('x-trace-id', req.traceId);
    next();
}
```

```bash
TRACE_ID="abc-123"
rg "\"traceId\":\"$TRACE_ID\"|traceId=$TRACE_ID" logs/ -n | sort
```

요청이 여러 서비스로 이동하면 HTTP header, queue message, DB audit log까지 같은 id를 전달한다.

---

## 4. 시간순 재구성

```bash
rg "traceId=abc-123|\"traceId\":\"abc-123\"" logs/ \
    | sort \
    > /tmp/timeline-abc-123.log
```

시간순 분석에서는 clock skew를 조심한다.
서비스 간 시간이 맞지 않으면 순서가 뒤집힐 수 있다.
가능하면 monotonic duration 필드를 함께 남긴다.

---

## 5. 로그 레벨 활용

| 레벨 | 용도 | 예시 |
|------|------|------|
| DEBUG | 일시적 상세 진단 | 계산 중간값 |
| INFO | 정상 비즈니스 이벤트 | 주문 생성 완료 |
| WARN | 복구 가능 이상 | 외부 API retry |
| ERROR | 요청 실패 | 결제 승인 실패 |
| FATAL | 프로세스 종료 | boot failure |

운영에서 DEBUG를 상시 켜면 비용과 개인정보 리스크가 크다.
특정 사용자, trace id, 짧은 TTL로 제한한다.

---

## 6. 로그 집계

```bash
jq -r 'select(.event == "payment.failed") | .error.code' logs/app.jsonl \
    | sort \
    | uniq -c \
    | sort -nr
```

```bash
jq -r 'select(.durationMs > 1000) | [.event, .route, .durationMs] | @tsv' logs/app.jsonl \
    | sort -k3 -nr \
    | head -20
```

집계는 반복 패턴을 찾는 데 유용하다.
단일 사례와 전체 경향을 섞지 않는다.

---

## 7. 정상 요청과 실패 요청 비교

```bash
jq -S . /tmp/success-trace.jsonl > /tmp/success.sorted
jq -S . /tmp/failure-trace.jsonl > /tmp/failure.sorted
diff -u /tmp/success.sorted /tmp/failure.sorted
```

비교 포인트:

- [ ] 빠진 이벤트가 있는가?
- [ ] duration이 급증한 단계가 있는가?
- [ ] error code가 다른가?
- [ ] feature flag 값이 다른가?
- [ ] 외부 API status가 다른가?

---

## 8. Python 로그 컨텍스트

```python
import logging
from contextvars import ContextVar

trace_id_var = ContextVar("trace_id", default="-")

class TraceFilter(logging.Filter):
    def filter(self, record):
        record.trace_id = trace_id_var.get()
        return True

handler = logging.StreamHandler()
handler.addFilter(TraceFilter())
handler.setFormatter(logging.Formatter(
    "%(asctime)s %(levelname)s trace_id=%(trace_id)s %(message)s"
))
```

비동기 Python에서는 thread local보다 `contextvars`가 안전하다.

---

## 9. 로그에서 보이는 안티패턴

- [ ] 에러 메시지에 값이 없다.
- [ ] 같은 이벤트 이름이 여러 의미로 쓰인다.
- [ ] stack trace가 잘려 있다.
- [ ] trace id가 중간 서비스에서 사라진다.
- [ ] 성공 로그는 많고 실패 로그는 없다.
- [ ] retry 로그가 최종 실패와 연결되지 않는다.

---

## 10. 민감정보 마스킹

```typescript
function redact(value: string): string {
    return value
        .replace(/Bearer [A-Za-z0-9._-]+/g, 'Bearer ***')
        .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, '***@***');
}

logger.info({
    event: 'request.received',
    traceId,
    body: redact(JSON.stringify(request.body)),
});
```

로그는 장기간 저장될 수 있다.
토큰, 비밀번호, 카드번호는 디버깅 편의보다 보안 비용이 크다.

---

## 11. 분석 결과 템플릿

```markdown
## Log Analysis
- trace_id: abc-123
- first_event: `checkout.start`
- last_success: `inventory.reserve.done`
- first_failure: `payment.authorize.timeout`
- missing_event: `payment.authorize.done`
- suspicious_duration: payment authorize 5000ms
- excluded: validation, inventory, DB save
```

---

## 12. 완료 기준

- [ ] 실패 요청의 전체 타임라인이 있다.
- [ ] 첫 실패 이벤트를 찾았다.
- [ ] 정상 요청과 차이를 확인했다.
- [ ] 로그 누락 자체를 기록했다.
- [ ] 다음 가설로 이어지는 관찰이 있다.
