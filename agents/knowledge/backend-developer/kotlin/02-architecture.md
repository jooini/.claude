# Architecture

> Kotlin/Spring Boot 버전 — 원본: Architecture

---

## 1. Spring Boot 레이어드 아키텍처

```
HTTP Request
    ↓
Controller        (요청/응답 처리, DTO 변환)
    ↓
Service           (비즈니스 로직, 트랜잭션)
    ↓
Repository        (데이터 접근, Spring Data JPA)
    ↓
Database
```

```
src/main/kotlin/com/example/app/
  api/
    controller/
      UserController.kt       # HTTP 레이어
      PostController.kt
    dto/
      UserDto.kt              # Request/Response DTO
      PostDto.kt
  domain/
    model/
      User.kt                 # JPA Entity
      Post.kt
    repository/
      UserRepository.kt       # Spring Data JPA
      PostRepository.kt
    service/
      UserService.kt          # 비즈니스 로직
      PostService.kt
  infrastructure/
    config/
      SecurityConfig.kt       # Spring Security
      RedisConfig.kt
      JpaConfig.kt
    client/
      PaymentClient.kt        # 외부 API 클라이언트
    filter/
      RequestIdFilter.kt      # 서블릿 필터
  common/
    exception/
      Exceptions.kt           # 커스텀 예외
      GlobalExceptionHandler.kt
    util/
      JwtUtil.kt
  Application.kt              # Spring Boot 진입점
```

---

## 2. 레이어별 책임

### Controller

```kotlin
// api/controller/UserController.kt
// 역할: 요청 파싱, 응답 반환, 유효성 검증
// 금지: 비즈니스 로직, DB 직접 접근

@RestController
@RequestMapping("/api/v1/users")
class UserController(
    private val userService: UserService,
) {
    @PostMapping
    fun createUser(
        @Valid @RequestBody request: CreateUserRequest,
    ): ResponseEntity<UserResponse> {
        val user = userService.createUser(request)
        return ResponseEntity.status(HttpStatus.CREATED).body(user)
    }
}
```

### Service

```kotlin
// domain/service/UserService.kt
// 역할: 비즈니스 로직, 트랜잭션 관리, 외부 서비스 호출
// 금지: HTTP 관련 로직, JPQL/SQL 직접 작성 (Repository에 위임)

@Service
@Transactional(readOnly = true)
class UserService(
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder,
) {
    @Transactional
    fun createUser(request: CreateUserRequest): UserResponse {
        userRepository.findByEmail(request.email)?.let {
            throw DuplicateEmailException(request.email)
        }

        val user = User(
            email = request.email,
            name = request.name,
            password = passwordEncoder.encode(request.password),
        )
        return UserResponse.from(userRepository.save(user))
    }
}
```

### Repository

```kotlin
// domain/repository/UserRepository.kt
// 역할: DB 쿼리, Spring Data JPA 인터페이스
// 금지: 비즈니스 로직

interface UserRepository : JpaRepository<User, String> {
    fun findByEmail(email: String): User?
    fun findByStatus(status: UserStatus, pageable: Pageable): Page<User>

    @Query("SELECT u FROM User u WHERE u.deletedAt IS NULL AND u.name LIKE %:name%")
    fun searchByName(@Param("name") name: String): List<User>
}
```

---

## 3. 의존성 주입 (Spring DI)

```kotlin
// 생성자 주입 (Kotlin에서 자동 — @Autowired 불필요)
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val userService: UserService,
    private val paymentClient: PaymentClient,
)

// 조건부 빈
@Configuration
class CacheConfig {
    @Bean
    @ConditionalOnProperty("cache.enabled", havingValue = "true")
    fun cacheManager(redisConnectionFactory: RedisConnectionFactory): CacheManager {
        return RedisCacheManager.builder(redisConnectionFactory)
            .cacheDefaults(RedisCacheConfiguration.defaultCacheConfig().entryTtl(Duration.ofMinutes(5)))
            .build()
    }
}
```

---

## 4. 설정 관리

```kotlin
// infrastructure/config/AppProperties.kt
@ConfigurationProperties(prefix = "app")
data class AppProperties(
    val name: String = "identity-hub",
    val debug: Boolean = false,
    val database: DatabaseProperties = DatabaseProperties(),
    val redis: RedisProperties = RedisProperties(),
    val keycloak: KeycloakProperties = KeycloakProperties(),
) {
    data class DatabaseProperties(
        val url: String = "",
        val poolSize: Int = 10,
        val maxOverflow: Int = 20,
    )
    data class RedisProperties(
        val url: String = "",
        val sessionTtl: Long = 86400,
    )
    data class KeycloakProperties(
        val serverUrl: String = "",
        val internalUrl: String = "",
        val adminUsername: String = "",
        val adminPassword: String = "",
    )
}
```

```yaml
# application.yml
app:
  name: identity-hub
  database:
    url: ${DATABASE_URL}
    pool-size: 10
  redis:
    url: ${REDIS_URL}
    session-ttl: 86400
  keycloak:
    server-url: ${KEYCLOAK_SERVER_URL}
    internal-url: ${KEYCLOAK_INTERNAL_URL}
```

---

## 5. 필터 & 인터셉터

```kotlin
// infrastructure/filter/RequestIdFilter.kt
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class RequestIdFilter : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val requestId = request.getHeader("X-Request-ID") ?: UUID.randomUUID().toString()
        MDC.put("requestId", requestId)
        response.setHeader("X-Request-ID", requestId)

        try {
            filterChain.doFilter(request, response)
        } finally {
            MDC.remove("requestId")
        }
    }
}
```

---

## 6. 프로파일별 설정

```yaml
# application.yml (공통)
spring:
  profiles:
    active: ${SPRING_PROFILES_ACTIVE:local}

# application-local.yml
spring:
  jpa:
    show-sql: true
logging:
  level:
    org.hibernate.SQL: DEBUG

# application-prod.yml
spring:
  jpa:
    show-sql: false
logging:
  level:
    root: INFO
```

---

## 7. 모듈 구성 (멀티 모듈)

```
project/
  app-api/          # 웹 레이어 (Controller, DTO)
  app-domain/       # 도메인 레이어 (Entity, Service, Repository)
  app-infrastructure/ # 인프라 레이어 (외부 API, 설정)
  app-common/       # 공통 유틸리티
```

```kotlin
// settings.gradle.kts
rootProject.name = "identity-hub"
include("app-api", "app-domain", "app-infrastructure", "app-common")
```
