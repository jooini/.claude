# Concurrency

> Kotlin/Spring Boot 버전 — 원본: Concurrency

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

```kotlin
// JPA — SELECT FOR UPDATE
interface AccountRepository : JpaRepository<Account, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT a FROM Account a WHERE a.id = :id")
    fun findByIdForUpdate(@Param("id") id: String): Account?
}

@Transactional
fun withdraw(accountId: String, amount: Long) {
    val account = accountRepository.findByIdForUpdate(accountId)
        ?: throw AccountNotFoundException(accountId)

    if (account.balance < amount) {
        throw InsufficientBalanceException()
    }

    account.balance -= amount
    // 트랜잭션 종료 시 자동 락 해제
}
```

### 낙관적 락 (Optimistic Lock)

```kotlin
@Entity
class Product(
    @Id val id: String,
    var stock: Int,

    @Version  // JPA 낙관적 락 — 자동 버전 관리
    var version: Long = 0,
)

@Transactional
fun updateStock(productId: String, delta: Int) {
    val product = productRepository.findById(productId)
        .orElseThrow { ProductNotFoundException(productId) }

    product.stock += delta

    try {
        productRepository.flush()
    } catch (e: OptimisticLockingFailureException) {
        throw ConflictException("다른 요청에 의해 데이터가 변경되었습니다. 재시도해주세요.")
    }
}

// Spring Retry로 자동 재시도
@Retryable(value = [OptimisticLockingFailureException::class], maxAttempts = 3)
@Transactional
fun updateStockWithRetry(productId: String, delta: Int) { ... }
```

---

## 3. Redis 분산 락

```kotlin
// Redisson 사용 (권장)
@Component
class DistributedLockService(
    private val redissonClient: RedissonClient,
) {
    fun <T> executeWithLock(
        key: String,
        waitTime: Long = 5,
        leaseTime: Long = 10,
        unit: TimeUnit = TimeUnit.SECONDS,
        action: () -> T,
    ): T {
        val lock = redissonClient.getLock("lock:$key")
        val acquired = lock.tryLock(waitTime, leaseTime, unit)
        if (!acquired) {
            throw TimeoutException("분산 락 획득 실패: $key")
        }
        return try {
            action()
        } finally {
            if (lock.isHeldByCurrentThread) {
                lock.unlock()
            }
        }
    }
}

// 사용
fun refreshToken(userId: String): TokenResponse {
    return distributedLockService.executeWithLock("refresh:$userId") {
        val newToken = fetchNewToken(userId)
        saveToken(userId, newToken)
        newToken
    }
}
```

### Spring RedisTemplate 기반 (경량)

```kotlin
@Component
class SimpleDistributedLock(
    private val redisTemplate: StringRedisTemplate,
) {
    fun tryLock(key: String, ttlSeconds: Long = 10): Boolean {
        val token = UUID.randomUUID().toString()
        return redisTemplate.opsForValue()
            .setIfAbsent("lock:$key", token, Duration.ofSeconds(ttlSeconds)) == true
    }

    fun unlock(key: String) {
        redisTemplate.delete("lock:$key")
    }
}
```

---

## 4. Kotlin Coroutine 동시성

### async / await

```kotlin
// 병렬 실행
suspend fun getDashboard(userId: String): DashboardResponse = coroutineScope {
    val user = async { userService.getUser(userId) }
    val orders = async { orderService.getOrders(userId) }
    val notifications = async { notificationService.get(userId) }

    DashboardResponse(
        user = user.await(),
        orders = orders.await(),
        notifications = notifications.await(),
    )
}
```

### Mutex (인메모리 락)

```kotlin
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

val mutex = Mutex()
val cache = mutableMapOf<String, Any>()

suspend fun getOrCompute(key: String): Any {
    cache[key]?.let { return it }

    return mutex.withLock {
        // 더블 체크
        cache[key]?.let { return it }
        val value = expensiveComputation(key)
        cache[key] = value
        value
    }
}
```

### Semaphore

```kotlin
import kotlinx.coroutines.sync.Semaphore

val semaphore = Semaphore(10)  // 최대 10개 동시

suspend fun rateLimitedRequest(url: String): Response {
    semaphore.acquire()
    return try {
        httpClient.get(url)
    } finally {
        semaphore.release()
    }
}
```

### Flow (비동기 스트림)

```kotlin
fun streamUsers(): Flow<UserResponse> = flow {
    var page = 1
    while (true) {
        val users = userRepository.findAll(PageRequest.of(page - 1, 100))
        if (users.isEmpty) break
        users.forEach { emit(UserResponse.from(it)) }
        page++
    }
}
```

---

## 5. Spring @Async

```kotlin
@Configuration
@EnableAsync
class AsyncConfig {
    @Bean("taskExecutor")
    fun taskExecutor(): TaskExecutor {
        return ThreadPoolTaskExecutor().apply {
            corePoolSize = 5
            maxPoolSize = 20
            queueCapacity = 100
            setThreadNamePrefix("async-")
            initialize()
        }
    }
}

@Async("taskExecutor")
fun sendNotification(userId: String, message: String) {
    // 별도 스레드에서 비동기 실행
    notificationService.send(userId, message)
}
```

---

## 6. 메시지 큐 (Spring AMQP / Kafka)

```kotlin
// RabbitMQ
@Component
class EmailProducer(
    private val rabbitTemplate: RabbitTemplate,
) {
    fun sendEmail(to: String, subject: String) {
        rabbitTemplate.convertAndSend("email-exchange", "email.send", EmailMessage(to, subject))
    }
}

@Component
class EmailConsumer {
    @RabbitListener(queues = ["email-queue"])
    fun handleEmail(message: EmailMessage) {
        mailer.send(message.to, message.subject)
    }
}

// Kafka
@Component
class EventProducer(
    private val kafkaTemplate: KafkaTemplate<String, String>,
) {
    fun publish(topic: String, key: String, payload: String) {
        kafkaTemplate.send(topic, key, payload)
    }
}

@KafkaListener(topics = ["user-events"], groupId = "notification-group")
fun handleUserEvent(record: ConsumerRecord<String, String>) {
    // 이벤트 처리
}
```

---

## 7. 동시성 안티패턴

```kotlin
// ❌ @Transactional + @Async 혼용 주의
@Transactional
@Async
fun riskyMethod() {
    // @Async는 별도 스레드 → 호출자의 트랜잭션과 무관
    // 트랜잭션 격리 불가!
}

// ✅ 분리
@Transactional
fun businessLogic() {
    // DB 작업
    asyncService.sendNotification()  // 비동기는 별도 빈에서
}

// ❌ synchronized + Spring Proxy 문제
@Synchronized  // 같은 인스턴스에서만 동작, 멀티 서버에서 무의미
fun updateCounter() { ... }

// ✅ 분산 환경에서는 Redis 분산 락 사용
```
