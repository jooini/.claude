# Performance

> Kotlin/Spring Boot 버전 — 원본: Performance

---

## 1. 성능 병목 진단

```
측정 → 분석 → 최적화 → 재측정

도구:
- Spring Boot Actuator: 메트릭, 헬스체크
- VisualVM / JFR (Java Flight Recorder): JVM 프로파일링
- async-profiler: 네이티브 프로파일러 (CPU, 메모리, 락)
- EXPLAIN ANALYZE: DB 쿼리 분석
- Gatling / k6: 부하 테스트
- Micrometer: Prometheus 메트릭 수집
```

---

## 2. 데이터베이스 최적화

### N+1 쿼리 방지

```kotlin
// ❌ N+1 문제 (LAZY 기본)
@OneToMany(mappedBy = "author", fetch = FetchType.LAZY)
val posts: List<Post> = emptyList()
// users.forEach { it.posts }  → 매번 추가 쿼리!

// ✅ EntityGraph
@EntityGraph(attributePaths = ["posts"])
fun findAllWithPosts(): List<User>

// ✅ FETCH JOIN
@Query("SELECT u FROM User u LEFT JOIN FETCH u.posts WHERE u.status = :status")
fun findActiveWithPosts(@Param("status") status: UserStatus): List<User>

// ✅ Batch Size (application.yml)
spring:
  jpa:
    properties:
      hibernate:
        default_batch_fetch_size: 100  # IN 쿼리로 배치 로딩
```

### 필요한 컬럼만 조회

```kotlin
// ❌ Entity 전체 로딩
val users = userRepository.findAll()  // SELECT *

// ✅ Projection
interface UserSummary {
    val id: String
    val email: String
    val name: String
}

fun findAllSummaries(pageable: Pageable): Page<UserSummary>

// ✅ DTO Projection (JPQL)
@Query("SELECT new com.example.app.dto.UserSummary(u.id, u.email, u.name) FROM User u")
fun findAllDtoProjections(): List<UserSummary>
```

---

## 3. Connection Pool (HikariCP)

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      idle-timeout: 300000
      max-lifetime: 1800000
      connection-timeout: 30000
      leak-detection-threshold: 60000  # 60초 — 커넥션 누수 감지
```

---

## 4. 캐싱

### Spring Cache + Redis

```kotlin
@Configuration
@EnableCaching
class CacheConfig {
    @Bean
    fun cacheManager(redisConnectionFactory: RedisConnectionFactory): CacheManager {
        val config = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(5))
            .serializeValuesWith(
                RedisSerializationContext.SerializationPair.fromSerializer(
                    GenericJackson2JsonRedisSerializer()
                )
            )
        return RedisCacheManager.builder(redisConnectionFactory)
            .cacheDefaults(config)
            .withCacheConfiguration("users", config.entryTtl(Duration.ofMinutes(10)))
            .build()
    }
}

// 사용
@Service
class UserService(private val userRepository: UserRepository) {

    @Cacheable(value = ["users"], key = "#userId")
    fun getUser(userId: String): UserResponse { ... }

    @CacheEvict(value = ["users"], key = "#userId")
    fun updateUser(userId: String, request: UpdateUserRequest): UserResponse { ... }

    @CacheEvict(value = ["users"], allEntries = true)
    fun deleteUser(userId: String) { ... }
}
```

---

## 5. 비동기 처리

```kotlin
// CompletableFuture
@Async
fun sendEmail(to: String, subject: String): CompletableFuture<Void> {
    mailer.send(to, subject)
    return CompletableFuture.completedFuture(null)
}

// Kotlin Coroutine
suspend fun getDashboard(userId: String): DashboardResponse = coroutineScope {
    val userDeferred = async { userService.getUser(userId) }
    val ordersDeferred = async { orderService.getOrders(userId) }
    val notificationsDeferred = async { notificationService.getNotifications(userId) }

    DashboardResponse(
        user = userDeferred.await(),
        orders = ordersDeferred.await(),
        notifications = notificationsDeferred.await(),
    )
}
```

---

## 6. 응답 압축

```yaml
server:
  compression:
    enabled: true
    min-response-size: 1024  # 1KB 이상만 압축
    mime-types: application/json,text/html,text/plain
```

---

## 7. JVM 튜닝

```bash
# 프로덕션 JVM 옵션
java -jar app.jar \
  -Xms512m -Xmx512m \          # 힙 크기 고정 (GC 부담 감소)
  -XX:+UseG1GC \                # G1 GC (기본)
  -XX:MaxGCPauseMillis=200 \    # GC 목표 시간
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/var/log/ \
  -Djava.security.egd=file:/dev/./urandom  # 빠른 난수 생성
```

---

## 8. 부하 테스트 (Gatling)

```kotlin
// GatlingSimulation.kt (Scala DSL)
class UserApiSimulation : Simulation() {
    val httpProtocol = http.baseUrl("http://localhost:8080")

    val scn = scenario("User API")
        .exec(
            http("List Users").get("/api/v1/users?page=1&size=20")
        )
        .pause(1)
        .exec(
            http("Create User").post("/api/v1/users")
                .header("Content-Type", "application/json")
                .body(StringBody("""{"email":"test${Random.nextInt()}@test.com","name":"부하테스트","password":"Test1234!"}"""))
        )

    init {
        setUp(
            scn.inject(
                rampUsersPerSec(1.0).to(50.0).during(Duration.ofMinutes(2)),
                constantUsersPerSec(50.0).during(Duration.ofMinutes(5)),
            )
        ).protocols(httpProtocol)
    }
}
```
