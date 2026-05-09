# Observability

> Python 버전 — 원본: Observability

---

## 1. Observability 3 기둥

```
Logs    — 무슨 일이 일어났는가 (이벤트)
Metrics — 얼마나 자주/빠르게 (수치)
Traces  — 어떻게 흘렀는가 (요청 경로)
```

---

## 2. 구조화 로깅 (structlog)

```python
# app/core/logging.py
import structlog


def setup_logging(log_level: str = "INFO", json_format: bool = True):
    processors = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
    ]

    if json_format:
        processors.append(structlog.processors.JSONRenderer())
    else:
        processors.append(structlog.dev.ConsoleRenderer())

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.stdlib.BoundLogger,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


logger = structlog.get_logger()
```

### 컨텍스트 바인딩

```python
# 요청별 컨텍스트
import structlog
from starlette.middleware.base import BaseHTTPMiddleware


class LoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(
            request_id=request.state.request_id,
            method=request.method,
            path=request.url.path,
            client_ip=request.client.host,
        )

        logger.info("request_started")
        response = await call_next(request)
        logger.info("request_completed", status=response.status_code)
        return response
```

### 로그 레벨 가이드

```python
# DEBUG — 개발 시 상세 정보
logger.debug("쿼리 실행", query=str(stmt), params=params)

# INFO — 주요 비즈니스 이벤트
logger.info("사용자 생성", user_id=user.id, email=user.email)

# WARNING — 잠재적 문제
logger.warning("Rate limit 근접", user_id=user_id, remaining=3)

# ERROR — 처리된 에러
logger.error("결제 실패", user_id=user_id, amount=amount, error=str(e))

# CRITICAL — 시스템 장애
logger.critical("DB 연결 실패", url=db_url, error=str(e))
```

---

## 3. 메트릭 (Prometheus)

```python
# app/core/metrics.py
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from fastapi import Response

# 카운터
http_requests_total = Counter(
    "http_requests_total",
    "총 HTTP 요청 수",
    ["method", "endpoint", "status"],
)

# 히스토그램
http_request_duration = Histogram(
    "http_request_duration_seconds",
    "HTTP 요청 처리 시간",
    ["method", "endpoint"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)

# 게이지
active_connections = Gauge(
    "active_connections",
    "현재 활성 연결 수",
)

db_pool_size = Gauge(
    "db_pool_size",
    "DB 커넥션 풀 크기",
    ["state"],  # active, idle
)
```

### 미들웨어로 자동 수집

```python
import time
from starlette.middleware.base import BaseHTTPMiddleware


class MetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        method = request.method
        endpoint = request.url.path

        active_connections.inc()
        start = time.perf_counter()

        response = await call_next(request)

        duration = time.perf_counter() - start
        active_connections.dec()

        http_requests_total.labels(method, endpoint, response.status_code).inc()
        http_request_duration.labels(method, endpoint).observe(duration)

        return response
```

### /metrics 엔드포인트

```python
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST


@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

---

## 4. 분산 트레이싱 (OpenTelemetry)

```python
# app/core/tracing.py
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor


def setup_tracing(app, engine):
    provider = TracerProvider()
    exporter = OTLPSpanExporter(endpoint="http://otel-collector:4317")
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    # 자동 계측
    FastAPIInstrumentor.instrument_app(app)
    SQLAlchemyInstrumentor().instrument(engine=engine.sync_engine)
    HTTPXClientInstrumentor().instrument()


# 수동 스팬 추가
tracer = trace.get_tracer(__name__)

async def create_order(self, data):
    with tracer.start_as_current_span("create_order") as span:
        span.set_attribute("user_id", data.user_id)
        span.set_attribute("item_count", len(data.items))

        with tracer.start_as_current_span("validate_stock"):
            await self.validate_stock(data.items)

        with tracer.start_as_current_span("process_payment"):
            await self.process_payment(data)
```

---

## 5. 헬스체크

```python
@app.get("/health")
async def health_check(db: AsyncSession = Depends(get_db)):
    checks = {}

    # DB 체크
    try:
        await db.execute(text("SELECT 1"))
        checks["database"] = "healthy"
    except Exception as e:
        checks["database"] = f"unhealthy: {e}"

    # Redis 체크
    try:
        await redis_client.ping()
        checks["redis"] = "healthy"
    except Exception as e:
        checks["redis"] = f"unhealthy: {e}"

    all_healthy = all(v == "healthy" for v in checks.values())
    return JSONResponse(
        status_code=200 if all_healthy else 503,
        content={"status": "healthy" if all_healthy else "degraded", "checks": checks},
    )
```

---

## 6. 감사 로그

```python
# app/services/audit_service.py
import structlog
from pathlib import Path

audit_logger = structlog.get_logger("audit")


async def log_audit_event(
    action: str,
    user_id: str | None = None,
    resource_type: str | None = None,
    resource_id: str | None = None,
    details: dict | None = None,
):
    audit_logger.info(
        "audit_event",
        action=action,
        user_id=user_id,
        resource_type=resource_type,
        resource_id=resource_id,
        details=details,
    )
```
