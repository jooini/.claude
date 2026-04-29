# Error Handling

> Python/FastAPI 버전 — 원본: Error Handling

---

## 1. 예외 계층 설계

```python
# app/core/exceptions.py
from fastapi import HTTPException, status


class AppException(HTTPException):
    """애플리케이션 기본 예외"""
    def __init__(
        self,
        code: str,
        message: str,
        status_code: int,
        details: dict | None = None,
    ):
        self.code = code
        self.details = details
        super().__init__(status_code=status_code, detail=message)


# 도메인별 예외
class UserNotFoundException(AppException):
    def __init__(self, user_id: str | None = None):
        msg = f"사용자({user_id})를 찾을 수 없습니다" if user_id else "사용자를 찾을 수 없습니다"
        super().__init__("USER_NOT_FOUND", msg, status.HTTP_404_NOT_FOUND)


class DuplicateEmailException(AppException):
    def __init__(self, email: str):
        super().__init__("DUPLICATE_EMAIL", f"이미 사용 중인 이메일: {email}", status.HTTP_409_CONFLICT)


class InsufficientStockException(AppException):
    def __init__(self, product_id: str, requested: int, available: int):
        super().__init__(
            "INSUFFICIENT_STOCK",
            f"재고 부족: 요청 {requested}, 가용 {available}",
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            details={"product_id": product_id, "requested": requested, "available": available},
        )


class UnauthorizedException(AppException):
    def __init__(self, message: str = "인증이 필요합니다"):
        super().__init__("UNAUTHORIZED", message, status.HTTP_401_UNAUTHORIZED)


class ForbiddenException(AppException):
    def __init__(self, message: str = "접근 권한이 없습니다"):
        super().__init__("FORBIDDEN", message, status.HTTP_403_FORBIDDEN)
```

---

## 2. 글로벌 예외 핸들러

```python
# app/core/exceptions.py
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
import structlog

logger = structlog.get_logger()


def register_exception_handlers(app: FastAPI):
    @app.exception_handler(AppException)
    async def app_exception_handler(request: Request, exc: AppException):
        logger.warning(
            "app_exception",
            code=exc.code,
            message=exc.detail,
            path=request.url.path,
        )
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": {
                    "code": exc.code,
                    "message": exc.detail,
                    "details": exc.details,
                }
            },
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError):
        logger.warning("validation_error", errors=exc.errors(), path=request.url.path)
        return JSONResponse(
            status_code=422,
            content={
                "error": {
                    "code": "VALIDATION_ERROR",
                    "message": "입력값 검증 실패",
                    "details": [
                        {
                            "field": ".".join(str(loc) for loc in err["loc"]),
                            "message": err["msg"],
                        }
                        for err in exc.errors()
                    ],
                }
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception):
        logger.error(
            "unhandled_exception",
            error=str(exc),
            path=request.url.path,
            exc_info=True,
        )
        return JSONResponse(
            status_code=500,
            content={
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": "서버 내부 오류가 발생했습니다",
                    # 운영에서는 상세 에러 숨김
                }
            },
        )
```

---

## 3. 서비스 레이어 에러 처리

```python
# app/services/order_service.py
class OrderService:
    async def create_order(self, user_id: str, items: list[OrderItem]) -> Order:
        # 1. 사용자 확인
        user = await self.user_repo.find_by_id(user_id)
        if not user:
            raise UserNotFoundException(user_id)

        # 2. 재고 확인
        for item in items:
            product = await self.product_repo.find_by_id(item.product_id)
            if not product:
                raise ProductNotFoundException(item.product_id)
            if product.stock < item.quantity:
                raise InsufficientStockException(
                    product.id, item.quantity, product.stock
                )

        # 3. 주문 생성 (트랜잭션)
        try:
            order = await self.order_repo.create(user_id=user_id, items=items)
            await self.db.commit()
            return order
        except Exception:
            await self.db.rollback()
            raise
```

---

## 4. 외부 서비스 호출 에러

```python
# app/services/external_service.py
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential


class PaymentService:
    def __init__(self):
        self.client = httpx.AsyncClient(
            base_url="https://api.payment.com",
            timeout=httpx.Timeout(10.0, connect=5.0),
        )

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        reraise=True,
    )
    async def charge(self, amount: int, token: str) -> dict:
        try:
            response = await self.client.post(
                "/v1/charges",
                json={"amount": amount, "token": token},
            )
            response.raise_for_status()
            return response.json()
        except httpx.TimeoutException:
            raise AppException(
                "PAYMENT_TIMEOUT", "결제 서비스 응답 시간 초과", 503
            )
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 402:
                raise AppException("PAYMENT_FAILED", "결제 실패", 402)
            raise AppException(
                "PAYMENT_ERROR", "결제 서비스 오류", 502
            )
```

---

## 5. 에러 응답 표준 (RFC 9457 Problem Details)

```python
# RFC 9457 호환 에러 응답
@app.exception_handler(AppException)
async def problem_details_handler(request: Request, exc: AppException):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "type": f"https://api.example.com/errors/{exc.code.lower()}",
            "title": exc.code,
            "status": exc.status_code,
            "detail": exc.detail,
            "instance": request.url.path,
        },
        media_type="application/problem+json",
    )
```

---

## 6. 로깅 컨텍스트

```python
# 에러 발생 시 충분한 컨텍스트 포함
logger.error(
    "order_creation_failed",
    user_id=user_id,
    order_items=len(items),
    error=str(exc),
    request_id=request.state.request_id,
    # ❌ 민감 정보 절대 포함하지 않음
    # password=user.password  # 금지!
    # card_number=payment.card  # 금지!
)
```
