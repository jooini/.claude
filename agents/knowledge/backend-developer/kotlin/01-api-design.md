# API Design

> Kotlin/Spring Boot 버전 — 원본: API Design

---

## 1. REST API 설계 원칙

### 리소스 중심 URL

```
# ✅ 리소스(명사) 기반
GET    /users              # 목록 조회
GET    /users/{id}         # 단건 조회
POST   /users              # 생성
PATCH  /users/{id}         # 부분 수정
PUT    /users/{id}         # 전체 교체
DELETE /users/{id}         # 삭제

# 중첩 리소스
GET    /users/{id}/posts   # 특정 유저의 게시물
POST   /users/{id}/posts
```

### HTTP 메서드 의미

| 메서드 | 의미 | 멱등성 | 안전성 |
|--------|------|--------|--------|
| GET | 조회 | ✅ | ✅ |
| POST | 생성 | ❌ | ❌ |
| PUT | 전체 수정 | ✅ | ❌ |
| PATCH | 부분 수정 | ❌ | ❌ |
| DELETE | 삭제 | ✅ | ❌ |

---

## 2. HTTP 상태 코드

```
2xx 성공
  200 OK              — 일반 성공
  201 Created         — 리소스 생성 성공 (POST)
  204 No Content      — 성공, 응답 본문 없음 (DELETE)

4xx 클라이언트 에러
  400 Bad Request     — 잘못된 요청 (유효성 실패)
  401 Unauthorized    — 인증 필요
  403 Forbidden       — 권한 없음
  404 Not Found       — 리소스 없음
  409 Conflict        — 충돌 (중복 이메일 등)
  422 Unprocessable   — 유효성 에러 상세
  429 Too Many Requests — Rate limit 초과

5xx 서버 에러
  500 Internal Server Error
  502 Bad Gateway
  503 Service Unavailable
```

---

## 3. Spring Boot Controller 설계

```kotlin
// api/controller/UserController.kt
@RestController
@RequestMapping("/api/v1/users")
class UserController(
    private val userService: UserService,
) {
    @GetMapping
    fun listUsers(
        @RequestParam(defaultValue = "1") page: Int,
        @RequestParam(defaultValue = "20") size: Int,
        @RequestParam(required = false) status: String?,
    ): ResponseEntity<PageResponse<UserResponse>> {
        val result = userService.listUsers(page, size, status)
        return ResponseEntity.ok(result)
    }

    @GetMapping("/{userId}")
    fun getUser(@PathVariable userId: String): ResponseEntity<UserResponse> {
        val user = userService.getUser(userId)
        return ResponseEntity.ok(user)
    }

    @PostMapping
    fun createUser(
        @Valid @RequestBody request: CreateUserRequest,
    ): ResponseEntity<UserResponse> {
        val user = userService.createUser(request)
        return ResponseEntity.status(HttpStatus.CREATED).body(user)
    }

    @PatchMapping("/{userId}")
    fun updateUser(
        @PathVariable userId: String,
        @Valid @RequestBody request: UpdateUserRequest,
    ): ResponseEntity<UserResponse> {
        val user = userService.updateUser(userId, request)
        return ResponseEntity.ok(user)
    }

    @DeleteMapping("/{userId}")
    fun deleteUser(@PathVariable userId: String): ResponseEntity<Void> {
        userService.deleteUser(userId)
        return ResponseEntity.noContent().build()
    }
}
```

---

## 4. DTO (Request / Response)

```kotlin
// dto/UserDto.kt
data class CreateUserRequest(
    @field:NotBlank(message = "이메일은 필수입니다")
    @field:Email(message = "올바른 이메일 형식이 아닙니다")
    val email: String,

    @field:NotBlank
    @field:Size(min = 1, max = 100)
    val name: String,

    @field:NotBlank
    @field:Size(min = 8, max = 128)
    val password: String,
)

data class UpdateUserRequest(
    @field:Size(min = 1, max = 100)
    val name: String? = null,
    val status: String? = null,
)

data class UserResponse(
    val id: String,
    val email: String,
    val name: String,
    val status: String,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    companion object {
        fun from(user: User) = UserResponse(
            id = user.id,
            email = user.email,
            name = user.name,
            status = user.status.name,
            createdAt = user.createdAt,
            updatedAt = user.updatedAt,
        )
    }
}

data class PageResponse<T>(
    val items: List<T>,
    val total: Long,
    val page: Int,
    val size: Int,
)
```

---

## 5. 페이지네이션 패턴

### Offset 기반 (Spring Data)

```kotlin
// repository
interface UserRepository : JpaRepository<User, String> {
    fun findByStatus(status: UserStatus, pageable: Pageable): Page<User>
}

// service
fun listUsers(page: Int, size: Int, status: String?): PageResponse<UserResponse> {
    val pageable = PageRequest.of(page - 1, size, Sort.by("createdAt").descending())
    val result = if (status != null) {
        userRepository.findByStatus(UserStatus.valueOf(status), pageable)
    } else {
        userRepository.findAll(pageable)
    }
    return PageResponse(
        items = result.content.map { UserResponse.from(it) },
        total = result.totalElements,
        page = page,
        size = size,
    )
}
```

### Cursor 기반 (대량 데이터 권장)

```kotlin
@GetMapping
fun listUsers(
    @RequestParam(required = false) cursor: Instant?,
    @RequestParam(defaultValue = "20") size: Int,
): CursorResponse<UserResponse> {
    val users = userRepository.findByCursor(cursor, size + 1)
    val hasNext = users.size > size
    val items = users.take(size)
    return CursorResponse(
        items = items.map { UserResponse.from(it) },
        nextCursor = if (hasNext) items.last().createdAt.toString() else null,
    )
}
```

---

## 6. API 버저닝

```kotlin
// URL 경로 기반 (권장)
@RestController
@RequestMapping("/api/v1/users")
class UserControllerV1

@RestController
@RequestMapping("/api/v2/users")
class UserControllerV2
```

---

## 7. 응답 형식 표준화

```kotlin
data class ApiResponse<T>(
    val success: Boolean = true,
    val data: T? = null,
    val error: ErrorDetail? = null,
)

data class ErrorDetail(
    val code: String,
    val message: String,
    val details: Any? = null,
)
```

---

## 8. Coroutine 기반 (WebFlux / Spring Boot 3.2+)

```kotlin
// Coroutine Controller (Spring WebFlux)
@RestController
@RequestMapping("/api/v1/users")
class UserController(
    private val userService: UserService,
) {
    @GetMapping("/{userId}")
    suspend fun getUser(@PathVariable userId: String): ResponseEntity<UserResponse> {
        val user = userService.getUser(userId)
        return ResponseEntity.ok(user)
    }

    @GetMapping
    fun listUsers(): Flow<UserResponse> {
        return userService.listUsers()
    }
}
```
