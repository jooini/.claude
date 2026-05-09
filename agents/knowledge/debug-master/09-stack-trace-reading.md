# 스택트레이스 해석

> 스택트레이스는 에러의 주소록이다. 맨 위 한 줄만 읽으면 자주 틀린다.

---

## 1. 읽는 순서

스택트레이스는 언어마다 모양이 다르지만 읽는 원칙은 같다.

1. 에러 타입과 메시지를 확인한다.
2. 애플리케이션 코드 프레임을 찾는다.
3. 최초 원인과 재던짐 지점을 구분한다.
4. 비동기 경계와 framework wrapper를 걷어낸다.
5. 입력값과 상태를 로그로 연결한다.

---

## 2. 공통 체크리스트

- [ ] 에러 타입은 무엇인가?
- [ ] 메시지에 실제 값이 포함되어 있는가?
- [ ] 우리 코드의 첫 프레임은 어디인가?
- [ ] 마지막으로 호출한 외부 라이브러리는 무엇인가?
- [ ] cause 또는 chained exception이 있는가?
- [ ] 비동기 task/thread/process 경계가 있는가?
- [ ] source map 또는 line number가 정확한가?

---

## 3. Python traceback

Python은 아래에서 위로 호출 경로가 쌓이고, 마지막 줄에 에러 타입과 메시지가 나온다.

```text
Traceback (most recent call last):
  File "app/api/orders.py", line 42, in create_order
    result = service.create_order(payload)
  File "app/services/order_service.py", line 88, in create_order
    total = calculate_total(payload["items"])
  File "app/services/pricing.py", line 17, in calculate_total
    return sum(item["price"] * item["quantity"] for item in items)
KeyError: 'price'
```

해석:

- 실패 타입: `KeyError`
- 누락 키: `price`
- 우리 코드 최초 원인: `pricing.py:17`
- 상위 API: `orders.py:42`

---

## 4. Python 예외 체인

```python
try:
    user = repository.get(user_id)
except DatabaseError as exc:
    raise UserLoadError(f"failed to load user_id={user_id}") from exc
```

`raise ... from exc`를 사용하면 원인 예외가 보존된다.
디버깅 중에는 가장 바깥 예외만 보지 말고 `The above exception was the direct cause` 아래를 확인한다.

---

## 5. Node.js / TypeScript stack

```text
TypeError: Cannot read properties of undefined (reading 'id')
    at createOrder (/app/src/order/order.service.ts:54:31)
    at processTicksAndRejections (node:internal/process/task_queues:95:5)
    at async OrderController.create (/app/src/order/order.controller.ts:22:20)
```

해석:

- `undefined.id` 접근이다.
- 실제 코드 위치는 `order.service.ts:54:31`이다.
- `processTicksAndRejections`는 비동기 경계라 원인 프레임이 아니다.
- controller는 호출자이고 원인은 service일 가능성이 높다.

source map이 없으면 빌드된 JS line number만 보인다.
운영에서는 source map 보관 정책이 필요하다.

---

## 6. TypeScript 원인 보강

```typescript
function requireUser(user: User | undefined): User {
    if (!user) {
        throw new Error('user is required before creating order');
    }
    return user;
}

const user = requireUser(await userRepository.findById(userId));
```

`Cannot read properties of undefined`보다 도메인 문맥이 있는 에러가 훨씬 빠르게 원인을 알려준다.

---

## 7. JVM stack trace

```text
java.lang.NullPointerException: Cannot invoke "User.getId()" because "user" is null
    at com.example.order.OrderService.create(OrderService.java:57)
    at com.example.order.OrderController.create(OrderController.java:31)
Caused by: org.postgresql.util.PSQLException: ERROR: duplicate key value violates unique constraint
    at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2676)
```

JVM은 `Caused by` 체인이 중요하다.
Spring AOP, proxy, reflection 프레임이 많기 때문에 `com.example` 같은 애플리케이션 패키지를 먼저 찾는다.

---

## 8. JVM 확인 명령

```bash
jcmd "$PID" Thread.print > /tmp/thread-dump.txt
rg "BLOCKED|WAITING|OrderService|Caused by" /tmp/thread-dump.txt -n -C 3
```

deadlock이나 thread starvation은 일반 stack trace보다 thread dump가 더 중요하다.
동일 시점에 2~3회 덤프를 떠서 같은 위치에 멈춰 있는지 본다.

---

## 9. Go panic stack

```text
panic: runtime error: invalid memory address or nil pointer dereference
goroutine 42 [running]:
github.com/acme/app/order.(*Service).Create(0xc0000a, {0x...}, 0x0)
    /app/order/service.go:73 +0x1a5
github.com/acme/app/order.(*Handler).Create(0xc0000b, ...)
    /app/order/handler.go:29 +0x88
```

Go에서는 goroutine 번호와 상태를 본다.
panic 프레임의 인자에서 `0x0`이 보이면 nil 인자가 전달된 단서다.

---

## 10. Go goroutine dump

```bash
curl -sS http://localhost:6060/debug/pprof/goroutine?debug=2 \
    > /tmp/goroutines.txt

rg "semacquire|chan receive|database/sql|order" /tmp/goroutines.txt -n -C 2
```

goroutine leak, deadlock, channel wait는 panic 없이도 장애를 만든다.
pprof endpoint는 운영 노출 시 접근 제어가 필요하다.

---

## 11. Framework 프레임 걷어내기

| 언어 | 흔한 노이즈 프레임 | 의미 |
|------|-------------------|------|
| Node | `processTicksAndRejections` | async scheduler |
| Python | `site-packages/fastapi` | framework dispatch |
| JVM | `CGLIB`, `ReflectiveMethodInvocation` | proxy/AOP |
| Go | `net/http.HandlerFunc` | HTTP wrapper |

노이즈 프레임을 제거하되, framework 버그 가능성을 완전히 배제하지는 않는다.
대부분은 우리 코드가 framework에 잘못된 입력을 넘긴다.

---

## 12. 스택트레이스 저장

```bash
TRACE_ID="abc-123"
rg "$TRACE_ID" logs/app.log -n -C 10 \
    > "/tmp/stack-$TRACE_ID.log"
```

```python
import traceback

try:
    run_job()
except Exception as exc:
    with open("/tmp/job-stack.txt", "w", encoding="utf-8") as file:
        file.write("".join(traceback.format_exception(exc)))
    raise
```

---

## 13. 해석 완료 기준

- [ ] 에러 타입과 메시지를 설명할 수 있다.
- [ ] 우리 코드의 원인 프레임을 찾았다.
- [ ] wrapper/framework 프레임을 구분했다.
- [ ] cause chain 또는 async boundary를 확인했다.
- [ ] 해당 line의 입력값을 수집할 계획이 있다.
