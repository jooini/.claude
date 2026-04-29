# Performance

> Python/FastAPI 버전 — 원본: Performance

---

## 1. 성능 병목 진단

```
측정 → 분석 → 최적화 → 재측정

도구:
- py-spy: Python 프로파일링 (flame graph)
- cProfile: 내장 프로파일러
- line_profiler: 라인 단위 프로파일링
- OpenTelemetry: 분산 트레이싱
- EXPLAIN ANALYZE: DB 쿼리 분석
- locust / k6: 부하 테스트
```

---

## 2. 데이터베이스 최적화

### 인덱스

```python
# 자주 조회하는 컬럼에 인덱스
class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (
        Index("ix_orders_user_status", "user_id", "status"),
        Index("ix_orders_created", "created_at"),
    )

    id: Mapped[str] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(20))
    created_at: Mapped[datetime] = mapped_column()
```

### N+1 쿼리 방지

```python
# ❌ N+1 문제
users = (await db.execute(select(User))).scalars().all()
for user in users:
    posts = user.posts  # 매번 추가 쿼리 발생!

# ✅ Eager Loading
from sqlalchemy.orm import selectinload, joinedload

# selectinload: IN 쿼리 (1:N에 적합)
stmt = select(User).options(selectinload(User.posts))

# joinedload: JOIN (1:1, N:1에 적합)
stmt = select(Post).options(joinedload(Post.author))

# 중첩 로딩
stmt = select(User).options(
    selectinload(User.posts).selectinload(Post.comments)
)
```

### 필요한 컬럼만 조회

```python
# ❌ SELECT * (전체 컬럼)
stmt = select(User)

# ✅ 필요한 컬럼만
stmt = select(User.id, User.email, User.name)
result = await db.execute(stmt)
rows = result.all()  # list of Row
```

### 페이지네이션

```python
# Offset 기반 (소규모)
stmt = select(User).offset(offset).limit(size)

# Keyset 기반 (대규모, 권장)
stmt = (
    select(User)
    .where(User.created_at < cursor_value)
    .order_by(User.created_at.desc())
    .limit(size)
)
```

---

## 3. Connection Pool 최적화

```python
# app/db/session.py
engine = create_async_engine(
    DATABASE_URL,
    pool_size=10,          # 기본 연결 수
    max_overflow=20,       # 초과 허용 연결 수
    pool_pre_ping=True,    # 연결 유효성 검사
    pool_recycle=3600,     # 1시간마다 연결 재생성
    pool_timeout=30,       # 연결 대기 타임아웃
    echo=False,            # SQL 로그 (운영에서 False)
)
```

---

## 4. 캐싱

```python
# Redis 캐싱
import redis.asyncio as redis
import json

redis_client = redis.from_url("redis://localhost:6379")


async def get_user_cached(user_id: str) -> dict | None:
    # 캐시 확인
    cached = await redis_client.get(f"user:{user_id}")
    if cached:
        return json.loads(cached)

    # DB 조회
    user = await repo.find_by_id(user_id)
    if user:
        await redis_client.setex(
            f"user:{user_id}",
            300,  # 5분 TTL
            json.dumps(user.to_dict()),
        )
    return user


# 캐시 무효화
async def invalidate_user_cache(user_id: str):
    await redis_client.delete(f"user:{user_id}")
```

---

## 5. 비동기 최적화

```python
import asyncio

# ❌ 순차 실행
user = await get_user(user_id)
orders = await get_orders(user_id)
reviews = await get_reviews(user_id)
# 총 시간: 100ms + 200ms + 150ms = 450ms

# ✅ 병렬 실행
user, orders, reviews = await asyncio.gather(
    get_user(user_id),
    get_orders(user_id),
    get_reviews(user_id),
)
# 총 시간: max(100, 200, 150) = 200ms

# ✅ TaskGroup (Python 3.11+, 에러 전파 우수)
async with asyncio.TaskGroup() as tg:
    user_task = tg.create_task(get_user(user_id))
    orders_task = tg.create_task(get_orders(user_id))
    reviews_task = tg.create_task(get_reviews(user_id))

user = user_task.result()
orders = orders_task.result()
```

---

## 6. 응답 압축

```python
# GZip 미들웨어
from fastapi.middleware.gzip import GZipMiddleware

app.add_middleware(GZipMiddleware, minimum_size=1000)  # 1KB 이상만 압축
```

---

## 7. 프로파일링

```bash
# py-spy — 프로덕션 안전 프로파일러
py-spy record -o profile.svg -- python -m uvicorn app.main:app

# py-spy top — 실시간 모니터링
py-spy top --pid <PID>
```

```python
# cProfile — 내장 프로파일러
import cProfile
import pstats

with cProfile.Profile() as pr:
    await some_function()

stats = pstats.Stats(pr)
stats.sort_stats("cumulative")
stats.print_stats(20)  # 상위 20개
```

---

## 8. 부하 테스트 (Locust)

```python
# locustfile.py
from locust import HttpUser, task, between


class ApiUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def list_users(self):
        self.client.get("/api/v1/users/?page=1&size=20")

    @task(1)
    def create_user(self):
        self.client.post("/api/v1/users/", json={
            "email": f"user{self.environment.runner.user_count}@test.com",
            "name": "부하테스트",
            "password": "Test1234!",
        })
```

```bash
locust -f locustfile.py --host=http://localhost:8000
```
