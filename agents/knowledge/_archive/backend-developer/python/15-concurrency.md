# Concurrency

> Python 버전 — 원본: Concurrency

---

## 1. 동시성 문제 유형

```
Race Condition   — 여러 요청이 같은 자원을 동시에 수정
Deadlock         — 두 트랜잭션이 서로의 락을 기다림
Stale Read       — 캐시/복제 지연으로 오래된 데이터 읽음
Lost Update      — 동시 수정으로 한쪽 변경 사항이 덮어쓰여짐
```

---

## 2. 데이터베이스 락

### 비관적 락 (Pessimistic Lock)

충돌이 자주 발생하는 경우. 읽을 때부터 락.

```python
# SQLAlchemy — SELECT FOR UPDATE
from sqlalchemy import select

async def withdraw(db: AsyncSession, account_id: str, amount: int):
    async with db.begin():
        # FOR UPDATE — 다른 트랜잭션이 읽기/쓰기 차단
        stmt = (
            select(Account)
            .where(Account.id == account_id)
            .with_for_update()
        )
        result = await db.execute(stmt)
        account = result.scalar_one()

        if account.balance < amount:
            raise InsufficientBalanceException()

        account.balance -= amount

    # 트랜잭션 종료 시 자동 락 해제


# SKIP LOCKED — 락 걸린 행 건너뛰기 (큐 패턴)
stmt = (
    select(Task)
    .where(Task.status == "pending")
    .with_for_update(skip_locked=True)
    .limit(10)
)
```

### 낙관적 락 (Optimistic Lock)

충돌이 드문 경우. 수정 시 버전 확인.

```python
# SQLAlchemy version_id_col
from sqlalchemy import Integer
from sqlalchemy.orm import Mapped, mapped_column

class Product(Base):
    __tablename__ = "products"

    id: Mapped[str] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255))
    stock: Mapped[int] = mapped_column(default=0)
    version: Mapped[int] = mapped_column(Integer, default=1)

    __mapper_args__ = {
        "version_id_col": version,  # 자동 버전 관리
    }


# 사용 — version 불일치 시 StaleDataError 발생
from sqlalchemy.orm.exc import StaleDataError

async def update_stock(db: AsyncSession, product_id: str, delta: int):
    product = await db.get(Product, product_id)
    product.stock += delta
    try:
        await db.flush()
    except StaleDataError:
        await db.rollback()
        raise ConflictException("다른 요청에 의해 데이터가 변경되었습니다. 재시도해주세요.")
```

---

## 3. Redis 분산 락

여러 서버 인스턴스 간 동기화.

```python
import redis.asyncio as redis
import uuid
import asyncio


class DistributedLock:
    def __init__(self, redis_client: redis.Redis, key: str, ttl: int = 10):
        self.redis = redis_client
        self.key = f"lock:{key}"
        self.ttl = ttl
        self.token = str(uuid.uuid4())

    async def acquire(self, timeout: int = 5) -> bool:
        end = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < end:
            if await self.redis.set(self.key, self.token, nx=True, ex=self.ttl):
                return True
            await asyncio.sleep(0.1)
        return False

    async def release(self):
        # Lua 스크립트로 원자적 해제 (본인 토큰만)
        script = """
        if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
        else
            return 0
        end
        """
        await self.redis.eval(script, 1, self.key, self.token)

    async def __aenter__(self):
        if not await self.acquire():
            raise TimeoutError("분산 락 획득 실패")
        return self

    async def __aexit__(self, *args):
        await self.release()


# 사용
async def refresh_token(user_id: str):
    async with DistributedLock(redis_client, f"refresh:{user_id}", ttl=5):
        # 이 블록은 한 번에 하나의 인스턴스만 실행
        token = await fetch_new_token(user_id)
        await save_token(user_id, token)
        return token
```

---

## 4. asyncio 동시성 패턴

### asyncio.gather

```python
import asyncio

# 병렬 실행 (모든 작업 완료 대기)
async def get_dashboard(user_id: str):
    user, orders, notifications = await asyncio.gather(
        get_user(user_id),
        get_orders(user_id),
        get_notifications(user_id),
    )
    return {"user": user, "orders": orders, "notifications": notifications}

# return_exceptions=True — 예외도 결과로 반환
results = await asyncio.gather(
    task1(), task2(), task3(),
    return_exceptions=True,
)
for result in results:
    if isinstance(result, Exception):
        logger.error("작업 실패", error=str(result))
```

### asyncio.TaskGroup (Python 3.11+)

```python
# 하나라도 실패하면 나머지도 취소
async def process_batch(items: list):
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(process_item(item)) for item in items]
    # 모든 태스크 완료 (또는 ExceptionGroup 발생)
    return [t.result() for t in tasks]
```

### asyncio.Semaphore

```python
# 동시 실행 수 제한
semaphore = asyncio.Semaphore(10)  # 최대 10개 동시

async def rate_limited_request(url: str):
    async with semaphore:
        async with httpx.AsyncClient() as client:
            return await client.get(url)

# 100개 URL을 동시 최대 10개로 처리
results = await asyncio.gather(
    *[rate_limited_request(url) for url in urls]
)
```

### asyncio.Lock

```python
# 인메모리 공유 자원 보호
cache_lock = asyncio.Lock()
cache: dict = {}

async def get_or_compute(key: str):
    if key in cache:
        return cache[key]

    async with cache_lock:
        # 더블 체크 (락 획득 사이에 다른 코루틴이 채웠을 수 있음)
        if key in cache:
            return cache[key]
        value = await expensive_computation(key)
        cache[key] = value
        return value
```

---

## 5. Worker 기반 동시성

### multiprocessing (CPU 바운드)

```python
from concurrent.futures import ProcessPoolExecutor
import asyncio

process_pool = ProcessPoolExecutor(max_workers=4)

async def cpu_bound_endpoint(data: list):
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(process_pool, heavy_computation, data)
    return result
```

### threading (블로킹 I/O 호환)

```python
from concurrent.futures import ThreadPoolExecutor

thread_pool = ThreadPoolExecutor(max_workers=20)

async def legacy_sync_call():
    loop = asyncio.get_event_loop()
    # 동기 라이브러리를 async 컨텍스트에서 실행
    result = await loop.run_in_executor(thread_pool, sync_library.call)
    return result
```

---

## 6. 태스크 큐 (Celery)

백그라운드 작업, 스케줄링.

```python
# app/tasks/celery_app.py
from celery import Celery

celery_app = Celery(
    "tasks",
    broker="redis://localhost:6379/1",
    backend="redis://localhost:6379/2",
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Asia/Seoul",
    task_soft_time_limit=300,
    task_time_limit=600,
)


# 태스크 정의
@celery_app.task(bind=True, max_retries=3)
def send_email(self, to: str, subject: str, body: str):
    try:
        mailer.send(to=to, subject=subject, body=body)
    except Exception as exc:
        self.retry(exc=exc, countdown=60)  # 60초 후 재시도


# FastAPI에서 호출
@router.post("/users/")
async def create_user(body: UserCreate):
    user = await service.create_user(body)
    send_email.delay(user.email, "가입 환영", "환영합니다!")  # 비동기 전송
    return user
```

### arq (경량 대안)

```python
# asyncio 네이티브 태스크 큐
from arq import create_pool
from arq.connections import RedisSettings


async def send_email(ctx, to: str, subject: str):
    await mailer.send(to=to, subject=subject)


class WorkerSettings:
    functions = [send_email]
    redis_settings = RedisSettings(host="localhost")


# 태스크 큐잉
redis_pool = await create_pool(RedisSettings())
await redis_pool.enqueue_job("send_email", "user@test.com", "환영!")
```

---

## 7. 동시성 안티패턴

```python
# ❌ asyncio.gather에서 DB 세션 공유
async def bad_parallel(db: AsyncSession):
    await asyncio.gather(
        update_user(db, "1"),   # 같은 세션을 동시에 사용 → 레이스 컨디션
        update_user(db, "2"),
    )

# ✅ 각각 별도 세션 사용
async def good_parallel():
    async with async_session() as db1, async_session() as db2:
        await asyncio.gather(
            update_user(db1, "1"),
            update_user(db2, "2"),
        )
```
