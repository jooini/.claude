# Python Internals

> Python 버전 — 원본: Node.js Internals

---

## 1. GIL (Global Interpreter Lock)

CPython은 GIL로 인해 한 번에 하나의 스레드만 Python 바이트코드를 실행.

```
스레드 A: [실행] → [GIL 해제 (I/O)] → [대기] → [실행]
스레드 B: [대기] → [실행] → [GIL 해제] → [대기]

GIL의 영향:
- CPU 바운드: 멀티스레딩 이점 없음 → multiprocessing 사용
- I/O 바운드: GIL 해제되므로 멀티스레딩/asyncio 효과적
```

```python
# CPU 바운드 → multiprocessing
from concurrent.futures import ProcessPoolExecutor
import asyncio

async def cpu_intensive_task(data):
    loop = asyncio.get_event_loop()
    with ProcessPoolExecutor() as pool:
        result = await loop.run_in_executor(pool, heavy_computation, data)
    return result

# I/O 바운드 → asyncio
async def io_intensive_task():
    async with httpx.AsyncClient() as client:
        response = await client.get("https://api.example.com")
    return response.json()
```

---

## 2. asyncio 이벤트 루프

```
┌────────────────────────────────────┐
│         asyncio Event Loop         │
│                                    │
│  1. Ready 콜백 실행                │
│  2. I/O 이벤트 폴링 (select/epoll) │
│  3. 타이머 콜백 실행               │
│  4. 반복                           │
└────────────────────────────────────┘

uvloop: libuv 기반 고성능 이벤트 루프 (2-4x 빠름)
```

```python
# uvloop 사용 (uvicorn 기본)
# pip install uvloop
import uvloop
asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())

# 이벤트 루프 블로킹 방지
# ❌ 이벤트 루프 블로킹
@router.get("/heavy")
async def heavy_endpoint():
    result = time.sleep(5)       # 전체 서버 블로킹!
    result = hashlib.pbkdf2_hmac(...)  # CPU 바운드 블로킹!

# ✅ 블로킹 작업은 executor로
@router.get("/heavy")
async def heavy_endpoint():
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(None, time.sleep, 5)  # ThreadPool
    result = await loop.run_in_executor(process_pool, heavy_computation)  # ProcessPool
```

---

## 3. 메모리 관리

### Reference Counting + GC

```
CPython 메모리 관리:
1. Reference Counting: 참조 카운트 0이 되면 즉시 해제
2. Generational GC: 순환 참조 감지 (세대별: gen0, gen1, gen2)
3. Memory Pool: 작은 객체(<512B)는 pymalloc arena에서 할당
```

```python
import sys
import gc

# 참조 카운트 확인
obj = {"key": "value"}
print(sys.getrefcount(obj))  # 2 (변수 + getrefcount 인자)

# GC 수동 제어
gc.collect()                    # 강제 GC
gc.get_count()                  # (gen0, gen1, gen2) 카운트
gc.set_threshold(700, 10, 10)   # 임계값 설정

# 메모리 사용량
import resource
print(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)  # Peak RSS (KB)
```

### 메모리 누수 방지

```python
# ❌ 순환 참조
class Node:
    def __init__(self):
        self.parent = None
        self.children = []

    def add_child(self, child):
        child.parent = self        # 순환 참조!
        self.children.append(child)

# ✅ weakref 사용
import weakref

class Node:
    def __init__(self):
        self._parent = None
        self.children = []

    @property
    def parent(self):
        return self._parent() if self._parent else None

    def add_child(self, child):
        child._parent = weakref.ref(self)  # 약한 참조
        self.children.append(child)
```

---

## 4. 동기 vs 비동기

```python
# 동기 함수 (def) vs 비동기 함수 (async def)

# FastAPI에서의 차이:
# - async def: 이벤트 루프에서 직접 실행 (I/O 바운드에 적합)
# - def: 스레드풀에서 실행 (블로킹 코드 호환)

@router.get("/async")
async def async_endpoint():
    # ✅ 비동기 DB, HTTP 호출
    result = await db.execute(stmt)
    return result

@router.get("/sync")
def sync_endpoint():
    # FastAPI가 자동으로 threadpool에서 실행
    # 레거시 동기 코드 호환에 유용
    result = requests.get("https://api.example.com")
    return result.json()
```

---

## 5. Generators & Async Generators

```python
# Generator — 메모리 효율적 대량 데이터 처리
def read_large_file(path: str):
    with open(path) as f:
        for line in f:
            yield line.strip()

# Async Generator — 비동기 스트리밍
async def stream_db_rows(db: AsyncSession, batch_size: int = 1000):
    offset = 0
    while True:
        stmt = select(User).offset(offset).limit(batch_size)
        result = await db.execute(stmt)
        rows = result.scalars().all()
        if not rows:
            break
        for row in rows:
            yield row
        offset += batch_size

# FastAPI StreamingResponse
from fastapi.responses import StreamingResponse

@router.get("/export")
async def export_users(db: AsyncSession = Depends(get_db)):
    async def generate():
        async for user in stream_db_rows(db):
            yield f"{user.id},{user.email}\n"

    return StreamingResponse(generate(), media_type="text/csv")
```

---

## 6. __slots__ 최적화

```python
# ❌ 일반 클래스 — __dict__ 사용 (메모리 많이 차지)
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y
# sys.getsizeof(Point(1, 2).__dict__)  # ~104 bytes

# ✅ __slots__ — 고정 속성, 메모리 절약
class Point:
    __slots__ = ("x", "y")
    def __init__(self, x, y):
        self.x = x
        self.y = y
# ~56 bytes (약 50% 절약, 대량 객체에서 효과적)
```

---

## 7. Worker 모델

```
uvicorn (ASGI 서버)
  └── 단일 프로세스, 이벤트 루프 기반

gunicorn + uvicorn workers (프로덕션 권장)
  ├── Master Process
  ├── Worker 1 (uvicorn)  ← 각각 독립 이벤트 루프
  ├── Worker 2 (uvicorn)
  └── Worker N (uvicorn)

Workers 수 = CPU 코어 × 2 + 1 (가이드라인)
```

```bash
# 프로덕션 실행
gunicorn app.main:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --timeout 120 \
  --graceful-timeout 30 \
  --access-logfile -
```
