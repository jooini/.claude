# Error Handling

> Kotlin/Spring Boot 버전 — 원본: Error Handling

---

## 1. 예외 계층 설계

```kotlin
// common/exception/Exceptions.kt
abstract class AppException(
    val code: String,
    override val message: String,
    val httpStatus: HttpStatus,
    val details: Any? = null,
) : RuntimeException(message)

class UserNotFoundException(userId: String? = null) : AppException(
    code = "USER_NOT_FOUND",
    message = if (userId != null) "사용자($userId)를 찾을 수 없습니다" else "사용자를 찾을 수 없습니다",
    httpStatus = HttpStatus.NOT_FOUND,
)

class DuplicateEmailException(email: String) : AppException(
    code = "DUPLICATE_EMAIL",
    message = "이미 사용 중인 이메일: $email",
    httpStatus = HttpStatus.CONFLICT,
)

class InsufficientStockException(
    productId: String, requested: Int, available: Int,
) : AppException(
    code = "INSUFFICIENT_STOCK",
    message = "재고 부족: 요청 $requested, 가용 $available",
    httpStatus = HttpStatus.UNPROCESSABLE_ENTITY,
    details = mapOf("productId" to productId, "requested" to requested, "available" to available),
)

class UnauthorizedException(message: String = "인증이 필요합니다") : AppException(
    code = "UNAUTHORIZED", message = message, httpStatus = HttpStatus.UNAUTHORIZED,
)

class ForbiddenException(message: String = "접근 권한이 없습니다") : AppException(
    code = "FORBIDDEN", message = message, httpStatus = HttpStatus.FORBIDDEN,
)
```

---

## 2. 글로벌 예외 핸들러

```kotlin
// common/exception/GlobalExceptionHandler.kt
@RestControllerAdvice
class GlobalExceptionHandler {
    private val logger = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(AppException::class)
    fun handleAppException(ex: AppException, request: HttpServletRequest): ResponseEntity<ErrorResponse> {
        logger.warn("AppException: code={}, message={}, path={}", ex.code, ex.message, request.requestURI)
        return ResponseEntity.status(ex.httpStatus).body(
            ErrorResponse(
                error = ErrorDetail(
                    code = ex.code,
                    message = ex.message,
                    details = ex.details,
                ),
            ),
        )
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(ex: MethodArgumentNotValidException): ResponseEntity<ErrorResponse> {
        val details = ex.bindingResult.fieldErrors.map {
            mapOf("field" to it.field, "message" to (it.defaultMessage ?: "유효하지 않은 값"))
        }
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body(
            ErrorResponse(
                error = ErrorDetail(
                    code = "VALIDATION_ERROR",
                    message = "입력값 검증 실패",
                    details = details,
                ),
            ),
        )
    }

    @ExceptionHandler(Exception::class)
    fun handleUnexpected(ex: Exception, request: HttpServletRequest): ResponseEntity<ErrorResponse> {
        logger.error("Unhandled exception: path={}", request.requestURI, ex)
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(
            ErrorResponse(
                error = ErrorDetail(
                    code = "INTERNAL_ERROR",
                    message = "서버 내부 오류가 발생했습니다",
                ),
            ),
        )
    }
}

data class ErrorResponse(val error: ErrorDetail)
data class ErrorDetail(
    val code: String,
    val message: String,
    val details: Any? = null,
)
```

---

## 3. 서비스 레이어 에러 처리

```kotlin
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val userRepository: UserRepository,
    private val productRepository: ProductRepository,
) {
    @Transactional
    fun createOrder(userId: String, items: List<OrderItemRequest>): OrderResponse {
        // 1. 사용자 확인
        val user = userRepository.findById(userId)
            .orElseThrow { UserNotFoundException(userId) }

        // 2. 재고 확인
        items.forEach { item ->
            val product = productRepository.findById(item.productId)
                .orElseThrow { ProductNotFoundException(item.productId) }
            if (product.stock < item.quantity) {
                throw InsufficientStockException(product.id, item.quantity, product.stock)
            }
        }

        // 3. 주문 생성
        val order = Order(userId = userId, items = items.map { ... })
        return OrderResponse.from(orderRepository.save(order))
    }
}
```

---

## 4. 외부 서비스 호출 에러

```kotlin
// infrastructure/client/PaymentClient.kt
@Component
class PaymentClient(
    private val restClient: RestClient,
) {
    @Retryable(
        value = [PaymentTimeoutException::class],
        maxAttempts = 3,
        backoff = Backoff(delay = 1000, multiplier = 2.0),
    )
    fun charge(amount: Long, token: String): PaymentResult {
        return try {
            restClient.post()
                .uri("/v1/charges")
                .body(mapOf("amount" to amount, "token" to token))
                .retrieve()
                .body(PaymentResult::class.java)
                ?: throw AppException("PAYMENT_ERROR", "결제 응답 없음", HttpStatus.BAD_GATEWAY)
        } catch (e: ResourceAccessException) {
            throw PaymentTimeoutException("결제 서비스 응답 시간 초과")
        } catch (e: HttpClientErrorException) {
            when (e.statusCode) {
                HttpStatus.PAYMENT_REQUIRED -> throw PaymentFailedException("결제 실패")
                else -> throw AppException("PAYMENT_ERROR", "결제 서비스 오류", HttpStatus.BAD_GATEWAY)
            }
        }
    }
}
```

---

## 5. 에러 응답 표준 (RFC 9457)

```kotlin
@ExceptionHandler(AppException::class)
fun handleProblemDetails(ex: AppException, request: HttpServletRequest): ResponseEntity<ProblemDetail> {
    val problem = ProblemDetail.forStatusAndDetail(ex.httpStatus, ex.message).apply {
        type = URI.create("https://api.example.com/errors/${ex.code.lowercase()}")
        title = ex.code
        setProperty("instance", request.requestURI)
    }
    return ResponseEntity.status(ex.httpStatus)
        .contentType(MediaType.APPLICATION_PROBLEM_JSON)
        .body(problem)
}
```

---

## 6. 로깅 컨텍스트 (MDC)

```kotlin
// 에러 발생 시 MDC 컨텍스트 자동 포함
logger.error("주문 생성 실패: userId={}, items={}", userId, items.size, ex)
// MDC에 requestId가 설정되어 있으면 로그에 자동 포함

// ❌ 민감 정보 절대 포함하지 않음
// logger.error("실패: password={}", user.password)  // 금지!
```
