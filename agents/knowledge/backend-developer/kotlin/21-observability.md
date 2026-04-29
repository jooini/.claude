# Observability

> Kotlin/Spring Boot 버전 — 원본: Observability

---

## 1. Observability 3 기둥

```
Logs    — 무슨 일이 일어났는가 (이벤트)
Metrics — 얼마나 자주/빠르게 (수치)
Traces  — 어떻게 흘렀는가 (요청 경로)
```

---

## 2. 구조화 로깅 (Logback + MDC)

```xml
<!-- src/main/resources/logback-spring.xml -->
<configuration>
    <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <includeMdcKeyName>requestId</includeMdcKeyName>
            <includeMdcKeyName>userId</includeMdcKeyName>
        </encoder>
    </appender>

    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{HH:mm:ss.SSS} [%thread] [%X{requestId}] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <springProfile name="prod">
        <root level="INFO"><appender-ref ref="JSON" /></root>
    </springProfile>
    <springProfile name="local">
        <root level="DEBUG"><appender-ref ref="CONSOLE" /></root>
    </springProfile>
</configuration>
```

### MDC (Mapped Diagnostic Context)

```kotlin
// RequestId 자동 주입
class RequestIdFilter : OncePerRequestFilter() {
    override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
        val requestId = request.getHeader("X-Request-ID") ?: UUID.randomUUID().toString()
        MDC.put("requestId", requestId)
        response.setHeader("X-Request-ID", requestId)
        try {
            chain.doFilter(request, response)
        } finally {
            MDC.clear()
        }
    }
}

// 사용 — MDC가 자동으로 로그에 포함
private val logger = LoggerFactory.getLogger(javaClass)

logger.info("사용자 생성: userId={}, email={}", user.id, user.email)
// 출력: {"@timestamp":"...","requestId":"abc-123","message":"사용자 생성: userId=1, email=..."}
```

### 로그 레벨 가이드

```kotlin
logger.debug("쿼리 실행: {}", sql)          // 개발 시 상세 정보
logger.info("사용자 생성 완료: {}", userId)   // 주요 비즈니스 이벤트
logger.warn("Rate limit 근접: remaining={}", remaining)  // 잠재적 문제
logger.error("결제 실패", exception)          // 처리된 에러
```

---

## 3. 메트릭 (Micrometer + Prometheus)

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,prometheus,metrics
  metrics:
    export:
      prometheus:
        enabled: true
    tags:
      application: identity-hub
      environment: ${SPRING_PROFILES_ACTIVE:local}
```

### 커스텀 메트릭

```kotlin
@Component
class OrderMetrics(
    meterRegistry: MeterRegistry,
) {
    private val orderCounter = Counter.builder("orders.created")
        .description("생성된 주문 수")
        .tag("type", "total")
        .register(meterRegistry)

    private val orderDuration = Timer.builder("orders.processing.duration")
        .description("주문 처리 시간")
        .register(meterRegistry)

    private val activeOrders = Gauge.builder("orders.active") { getActiveOrderCount() }
        .description("현재 진행 중인 주문 수")
        .register(meterRegistry)

    fun recordOrderCreated() {
        orderCounter.increment()
    }

    fun <T> timeOrderProcessing(block: () -> T): T {
        return orderDuration.recordCallable(block)!!
    }
}
```

### Spring Boot 기본 메트릭

```
GET /actuator/prometheus

# JVM
jvm_memory_used_bytes{area="heap"}
jvm_gc_pause_seconds_count
jvm_threads_live_threads

# HTTP
http_server_requests_seconds_count{method="GET", uri="/api/v1/users", status="200"}
http_server_requests_seconds_sum

# DB
hikaricp_connections_active
hikaricp_connections_idle
hikaricp_connections_pending

# Cache
cache_gets_total{cache="users", result="hit"}
cache_gets_total{cache="users", result="miss"}
```

---

## 4. 분산 트레이싱 (Micrometer Tracing + OpenTelemetry)

```kotlin
// build.gradle.kts
dependencies {
    implementation("io.micrometer:micrometer-tracing-bridge-otel")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp")
}
```

```yaml
# application.yml
management:
  tracing:
    sampling:
      probability: 1.0  # 운영에서는 0.1 (10%)
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces
```

```kotlin
// 수동 스팬 추가
@Component
class OrderProcessor(
    private val tracer: Tracer,
) {
    fun processOrder(orderId: String) {
        val span = tracer.nextSpan().name("process-order").start()
        try {
            tracer.withSpan(span).use {
                span.tag("orderId", orderId)
                validateOrder(orderId)
                processPayment(orderId)
            }
        } finally {
            span.end()
        }
    }
}

// 또는 @Observed (Spring 6+)
@Observed(name = "order.process", contextualName = "process-order")
fun processOrder(orderId: String) { ... }
```

---

## 5. 헬스체크

```kotlin
@Component
class CustomHealthIndicator(
    private val redisTemplate: StringRedisTemplate,
) : HealthIndicator {

    override fun health(): Health {
        return try {
            redisTemplate.connectionFactory?.connection?.ping()
            Health.up().withDetail("redis", "connected").build()
        } catch (e: Exception) {
            Health.down().withDetail("redis", e.message).build()
        }
    }
}
```

```yaml
management:
  endpoint:
    health:
      show-details: when_authorized
      group:
        readiness:
          include: db, redis
        liveness:
          include: ping
```

---

## 6. 감사 로그

```kotlin
// JPA Auditing
@Configuration
@EnableJpaAuditing
class AuditConfig {
    @Bean
    fun auditorProvider(): AuditorAware<String> {
        return AuditorAware {
            Optional.ofNullable(SecurityContextHolder.getContext().authentication?.name)
        }
    }
}

@EntityListeners(AuditingEntityListener::class)
@MappedSuperclass
abstract class Auditable {
    @CreatedBy
    @Column(updatable = false)
    var createdBy: String? = null

    @LastModifiedBy
    var updatedBy: String? = null
}
```
