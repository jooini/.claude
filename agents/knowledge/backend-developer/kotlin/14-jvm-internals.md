# JVM Internals

> Kotlin/Spring Boot 버전 — 원본: Node.js Internals

---

## 1. JVM 메모리 구조

```
┌─────────────────────────────────────────┐
│              JVM Memory                  │
│                                          │
│  ┌──────────┐  ┌──────────┐             │
│  │   Heap   │  │ Non-Heap │             │
│  │          │  │          │             │
│  │ Young Gen│  │ Metaspace│ (클래스 메타) │
│  │  Eden    │  │ Code Cache│            │
│  │  S0, S1  │  └──────────┘             │
│  │ Old Gen  │  ┌──────────┐             │
│  │          │  │  Stack   │ (스레드별)   │
│  └──────────┘  └──────────┘             │
└─────────────────────────────────────────┘

Young Gen: 새 객체 할당 (Minor GC 빈번)
Old Gen: 오래 살아남은 객체 (Major GC 드묾)
Metaspace: 클래스 정보 (네이티브 메모리)
Stack: 스레드별 호출 스택 (기본 1MB)
```

---

## 2. GC (Garbage Collection)

```
주요 GC 알고리즘:

G1 GC (기본, JDK 11+)
  - Region 기반, 예측 가능한 pause time
  - -XX:+UseG1GC -XX:MaxGCPauseMillis=200

ZGC (초저지연, JDK 15+)
  - Sub-millisecond pause (< 1ms)
  - -XX:+UseZGC
  - 대규모 힙(수십 GB)에서도 짧은 pause

Shenandoah (Red Hat)
  - ZGC와 유사, concurrent compaction
  - -XX:+UseShenandoahGC
```

```bash
# GC 로그 활성화
java -jar app.jar \
  -Xlog:gc*:file=gc.log:time,uptime,level,tags \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200
```

---

## 3. 스레드 모델

```
전통적 Spring MVC (Thread-per-request):
  ┌─────────────────────────┐
  │     Tomcat Thread Pool  │
  │  Thread 1 → Request 1   │  각 요청에 스레드 1개
  │  Thread 2 → Request 2   │  기본 200개
  │  ...                     │  I/O 대기 시 스레드 블로킹
  └─────────────────────────┘

Kotlin Coroutine + WebFlux (Non-blocking):
  ┌─────────────────────────┐
  │     Netty Event Loop    │
  │  Thread 1 → Request 1,3 │  적은 스레드로 많은 요청
  │  Thread 2 → Request 2,4 │  I/O 대기 시 suspend
  └─────────────────────────┘
```

```kotlin
// ❌ 스레드 블로킹
@GetMapping("/heavy")
fun heavyEndpoint(): String {
    Thread.sleep(5000)  // 스레드 블로킹! Tomcat 스레드 고갈
    return "done"
}

// ✅ Coroutine (WebFlux)
@GetMapping("/heavy")
suspend fun heavyEndpoint(): String {
    delay(5000)  // suspend — 스레드 반환, 나중에 재개
    return "done"
}

// ✅ @Async (Spring MVC)
@Async
fun asyncTask(): CompletableFuture<String> {
    // 별도 스레드풀에서 실행
    return CompletableFuture.completedFuture("done")
}
```

---

## 4. Virtual Threads (Java 21+)

```kotlin
// Project Loom — 경량 스레드 (Spring Boot 3.2+)
// application.yml
spring:
  threads:
    virtual:
      enabled: true  # Tomcat이 Virtual Thread 사용

// 기존 Thread-per-request 모델 유지하면서
// 수만 개의 동시 요청 처리 가능
// Coroutine 대안으로 사용 가능
```

```kotlin
// 프로그래매틱 사용
val executor = Executors.newVirtualThreadPerTaskExecutor()

executor.submit {
    // 블로킹 I/O도 OK — Virtual Thread가 자동 suspend
    val result = httpClient.send(request, BodyHandlers.ofString())
}
```

---

## 5. Connection Pool 이해

```
HikariCP (Spring Boot 기본):

  Application Thread → HikariCP Pool → DB Connection
       ↕                    ↕
  pool-size=10일 때:
  - 최대 10개 동시 DB 쿼리
  - 11번째 요청은 connectionTimeout까지 대기
  - timeout 초과 시 SQLTransientConnectionException

  최적 풀 크기 공식:
  connections = (core_count * 2) + effective_spindle_count
  예: 4코어 서버 → 10~15 정도
```

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10
      connection-timeout: 30000
      leak-detection-threshold: 60000  # 커넥션 누수 감지
```

---

## 6. ClassLoader & 클래스 로딩

```
Bootstrap ClassLoader → JDK 기본 클래스 (java.lang 등)
    ↓
Platform ClassLoader → JDK 확장 (java.sql 등)
    ↓
Application ClassLoader → 애플리케이션 + 의존성

Spring Boot:
  LaunchedURLClassLoader → fat jar 내부 클래스 로딩
  DevTools Restarter → 변경된 클래스만 재로딩
```

---

## 7. JVM 모니터링

```bash
# JFR (Java Flight Recorder) — 프로덕션 안전
java -XX:StartFlightRecording=duration=60s,filename=recording.jfr -jar app.jar

# jcmd — 런타임 진단
jcmd <PID> VM.info                  # JVM 정보
jcmd <PID> GC.heap_info             # 힙 상태
jcmd <PID> Thread.print             # 스레드 덤프
jcmd <PID> VM.native_memory summary # 네이티브 메모리

# VisualVM — GUI 프로파일러
# jvisualvm

# async-profiler — 네이티브 프로파일러
./profiler.sh -d 30 -f flamegraph.html <PID>
```

---

## 8. Spring Boot Actuator

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when_authorized
  metrics:
    export:
      prometheus:
        enabled: true
```

```
GET /actuator/health          → 헬스체크
GET /actuator/metrics         → 메트릭 목록
GET /actuator/prometheus      → Prometheus 형식 메트릭
GET /actuator/metrics/jvm.memory.used → JVM 메모리
GET /actuator/metrics/hikaricp.connections.active → DB 풀
```
