# Debugging

> Python 버전 — 원본: Debugging

---

## 1. Python 디버깅

### VS Code Debugger (debugpy)

```json
// .vscode/launch.json
{
  "configurations": [
    {
      "type": "debugpy",
      "request": "launch",
      "name": "FastAPI Debug",
      "module": "uvicorn",
      "args": ["app.main:app", "--reload", "--port", "8000"],
      "envFile": "${workspaceFolder}/.env.local",
      "console": "integratedTerminal"
    },
    {
      "type": "debugpy",
      "request": "attach",
      "name": "Attach to Process",
      "connect": {"host": "localhost", "port": 5678}
    },
    {
      "type": "debugpy",
      "request": "launch",
      "name": "Pytest Debug",
      "module": "pytest",
      "args": ["tests/", "-v", "-x"],
      "envFile": "${workspaceFolder}/.env.test"
    }
  ]
}
```

### pdb / ipdb

```python
# 코드에 브레이크포인트 삽입
import pdb; pdb.set_trace()        # 기본
import ipdb; ipdb.set_trace()      # 컬러, 자동완성
breakpoint()                        # Python 3.7+ (PYTHONBREAKPOINT 환경변수로 커스텀)

# pdb 명령어
# n(ext)     — 다음 줄
# s(tep)     — 함수 안으로
# c(ontinue) — 다음 브레이크포인트까지
# p expr     — 표현식 출력
# pp expr    — pretty print
# l(ist)     — 현재 코드 보기
# w(here)    — 콜스택
# u(p)/d(own) — 스택 프레임 이동
```

---

## 2. 로그 디버깅

```python
import structlog

logger = structlog.get_logger()

# 구조화 로그 — 검색/필터 가능
logger.debug(
    "쿼리 실행",
    query=str(stmt),
    params=params,
    duration_ms=elapsed * 1000,
)

# 임시 디버그 로그 (커밋 전 제거)
logger.debug(">>> DEBUG", value=suspicious_variable, type=type(suspicious_variable).__name__)
```

### 로그 레벨 동적 변경

```python
import logging

# 런타임에 로그 레벨 변경
logging.getLogger("sqlalchemy.engine").setLevel(logging.DEBUG)  # SQL 쿼리 출력
logging.getLogger("httpx").setLevel(logging.DEBUG)               # HTTP 요청 출력
```

---

## 3. 프로파일링

### py-spy (프로덕션 안전)

```bash
# Flame Graph 생성
py-spy record -o profile.svg -- python -m uvicorn app.main:app

# 실행 중 프로세스에 attach
py-spy record -o profile.svg --pid <PID>

# 실시간 top 모니터링
py-spy top --pid <PID>
```

### cProfile (내장)

```python
import cProfile
import pstats

# 함수 프로파일링
with cProfile.Profile() as pr:
    result = await some_function()

stats = pstats.Stats(pr)
stats.sort_stats("cumulative")
stats.print_stats(20)

# 커맨드라인
# python -m cProfile -s cumtime app/main.py
```

### line_profiler (라인 단위)

```python
# pip install line_profiler
from line_profiler import profile

@profile
def process_data(data):
    filtered = [x for x in data if x > 0]       # Line 1: 10ms
    sorted_data = sorted(filtered)                # Line 2: 50ms  ← 병목!
    return sorted_data[:100]                      # Line 3: 0.1ms
```

---

## 4. 메모리 디버깅

### tracemalloc (내장)

```python
import tracemalloc

tracemalloc.start()

# ... 작업 수행 ...

snapshot = tracemalloc.take_snapshot()
top_stats = snapshot.statistics("lineno")

print("[ Top 10 메모리 사용 ]")
for stat in top_stats[:10]:
    print(stat)
```

### objgraph (객체 참조)

```python
import objgraph

# 가장 많은 객체 타입
objgraph.show_most_common_types(limit=10)

# 메모리 누수 탐지 — 증가하는 객체
objgraph.show_growth(limit=10)

# 특정 객체의 참조 체인 시각화
objgraph.show_backrefs(
    objgraph.by_type("MyClass")[0],
    max_depth=5,
    filename="refs.png",
)
```

---

## 5. 비동기 디버깅

```python
# asyncio 디버그 모드 활성화
import asyncio
asyncio.get_event_loop().set_debug(True)

# 느린 콜백 감지 (기본 100ms)
# WARNING: Executing <Task ...> took 0.200 seconds

# 환경변수로도 설정 가능
# PYTHONASYNCIODEBUG=1 python app/main.py
```

### 느린 쿼리 감지

```python
# SQLAlchemy 이벤트로 느린 쿼리 로깅
from sqlalchemy import event
import time

@event.listens_for(engine.sync_engine, "before_cursor_execute")
def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    conn.info["query_start_time"] = time.perf_counter()

@event.listens_for(engine.sync_engine, "after_cursor_execute")
def after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    elapsed = time.perf_counter() - conn.info["query_start_time"]
    if elapsed > 0.5:  # 500ms 이상
        logger.warning("slow_query", duration_ms=elapsed * 1000, query=statement[:200])
```

---

## 6. 네트워크 디버깅

```python
# httpx 요청/응답 로깅
import httpx
import logging

logging.getLogger("httpx").setLevel(logging.DEBUG)

# 또는 이벤트 훅
async def log_request(request: httpx.Request):
    logger.debug("request", method=request.method, url=str(request.url))

async def log_response(response: httpx.Response):
    logger.debug("response", status=response.status_code, elapsed=response.elapsed)

client = httpx.AsyncClient(
    event_hooks={"request": [log_request], "response": [log_response]}
)
```

---

## 7. 에러 재현

```python
# pytest에서 실패 재현
pytest tests/ -x --pdb          # 실패 시 pdb 진입
pytest tests/ -x --pdb-trace    # 모든 테스트에서 pdb
pytest tests/ --lf              # 마지막 실패한 테스트만 재실행
pytest tests/ --ff              # 실패한 테스트 우선 실행
```
