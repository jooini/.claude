# Debugging

> Kotlin/Spring Boot 버전 — 원본: Debugging

---

## 1. IntelliJ IDEA 디버거

```
기본 단축키:
  F8          — Step Over (다음 줄)
  F7          — Step Into (함수 안으로)
  Shift+F8    — Step Out (함수 밖으로)
  F9          — Resume (다음 브레이크포인트까지)
  Alt+F8      — Evaluate Expression (표현식 평가)
  Ctrl+F8     — 브레이크포인트 토글
```

### 조건부 브레이크포인트

```
브레이크포인트 우클릭 → Condition:
  userId == "특정유저ID"
  amount > 10000
  items.size > 5
```

### 원격 디버깅

```bash
# JVM 원격 디버그 포트 열기
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 -jar app.jar

# Docker
ENV JAVA_TOOL_OPTIONS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
```

```
IntelliJ → Run → Edit Configurations → Remote JVM Debug
  Host: localhost, Port: 5005
```

---

## 2. 로그 디버깅

```kotlin
private val logger = LoggerFactory.getLogger(javaClass)

// 구조화 로그
logger.debug("쿼리 실행: sql={}, params={}, duration={}ms", sql, params, elapsed)

// 임시 디버그 (커밋 전 제거)
logger.debug(">>> DEBUG: value={}, type={}", suspiciousVariable, suspiciousVariable::class.simpleName)
```

### 런타임 로그 레벨 변경

```bash
# Spring Actuator로 동적 변경
curl -X POST http://localhost:8080/actuator/loggers/com.example.app.service \
  -H "Content-Type: application/json" \
  -d '{"configuredLevel": "DEBUG"}'

# 확인
curl http://localhost:8080/actuator/loggers/com.example.app.service
```

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: loggers
```

---

## 3. 프로파일링

### JFR (Java Flight Recorder)

```bash
# 프로덕션 안전 — 오버헤드 < 2%
# 시작
jcmd <PID> JFR.start duration=60s filename=recording.jfr

# 또는 JVM 옵션으로
java -XX:StartFlightRecording=duration=60s,filename=recording.jfr -jar app.jar

# JFR 파일 분석 → JDK Mission Control (jmc)
```

### async-profiler

```bash
# CPU 프로파일링 (Flame Graph)
./profiler.sh -d 30 -f flamegraph.html <PID>

# 메모리 할당 프로파일링
./profiler.sh -d 30 -e alloc -f alloc.html <PID>

# 락 프로파일링
./profiler.sh -d 30 -e lock -f locks.html <PID>
```

### Spring Boot DevTools

```kotlin
// build.gradle.kts
dependencies {
    developmentOnly("org.springframework.boot:spring-boot-devtools")
}
// 자동 재시작, 라이브 리로드
```

---

## 4. 메모리 디버깅

### Heap Dump

```bash
# OOM 시 자동 힙 덤프
java -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/heap.hprof -jar app.jar

# 수동 힙 덤프
jcmd <PID> GC.heap_dump /tmp/heap.hprof
jmap -dump:format=b,file=/tmp/heap.hprof <PID>
```

### 메모리 분석 (Eclipse MAT)

```
1. heap.hprof 파일을 Eclipse MAT으로 열기
2. Leak Suspects Report → 메모리 누수 의심 객체
3. Dominator Tree → 가장 많은 메모리 차지 객체
4. Histogram → 객체 타입별 인스턴스 수
```

### 런타임 메모리 확인

```bash
# JVM 메모리 상태
jcmd <PID> GC.heap_info

# Actuator 메트릭
curl http://localhost:8080/actuator/metrics/jvm.memory.used
curl http://localhost:8080/actuator/metrics/jvm.gc.pause
```

---

## 5. 스레드 디버깅

### Thread Dump

```bash
# 스레드 덤프 (데드락 감지 포함)
jcmd <PID> Thread.print
jstack <PID>

# 또는 kill -3 <PID> (stdout으로 출력)
```

### 데드락 감지

```
Actuator 엔드포인트에서도 확인 가능:
GET /actuator/threaddump

찾을 것:
- BLOCKED 상태 스레드
- "Found one Java-level deadlock" 메시지
- 대기 중인 락 체인
```

---

## 6. 느린 쿼리 감지

```yaml
# application.yml
spring:
  jpa:
    properties:
      hibernate:
        generate_statistics: true  # 쿼리 통계 (개발용)

logging:
  level:
    org.hibernate.SQL: DEBUG                          # SQL 출력
    org.hibernate.type.descriptor.sql: TRACE          # 바인딩 파라미터
    org.hibernate.stat: DEBUG                         # 통계 (쿼리 수, 시간)
```

```kotlin
// 커스텀 느린 쿼리 감지 (Hibernate Interceptor)
@Component
class SlowQueryInterceptor : EmptyInterceptor() {
    private val logger = LoggerFactory.getLogger(javaClass)

    override fun onPrepareStatement(sql: String): String {
        // P6Spy 또는 datasource-proxy 사용 권장
        return sql
    }
}

// datasource-proxy (권장)
// build.gradle.kts: implementation("net.ttddyy:datasource-proxy:1.9")
```

---

## 7. 에러 재현

```bash
# 특정 테스트만 재실행
./gradlew test --tests "com.example.app.service.UserServiceTest.이메일 중복 시*"

# 실패한 테스트만 재실행
./gradlew test --rerun-tasks

# 디버그 모드로 테스트
./gradlew test --debug-jvm  # 5005 포트 대기
```

```kotlin
// 조건부 테스트
@Test
@EnabledIfEnvironmentVariable(named = "CI", matches = "true")
fun `CI에서만 실행되는 테스트`() { ... }

@Test
@DisabledOnOs(OS.WINDOWS)
fun `Linux/Mac에서만 실행`() { ... }
```
