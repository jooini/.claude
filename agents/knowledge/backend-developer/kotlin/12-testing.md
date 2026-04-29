# Testing

> Kotlin/Spring Boot 버전 — 원본: Testing

---

## 1. 테스트 전략

```
Unit Test       빠름, 격리, 로직 검증
Integration     DB/외부 서비스 포함, 슬로우
E2E             실제 HTTP 요청, 가장 느림

권장 비율: Unit 70% / Integration 20% / E2E 10%
```

Kotlin 테스트 스택: JUnit 5 + MockK + Testcontainers + Spring Boot Test

---

## 2. Unit Test — Service

```kotlin
// src/test/kotlin/com/example/app/domain/service/UserServiceTest.kt
@ExtendWith(MockKExtension::class)
class UserServiceTest {

    @MockK
    lateinit var userRepository: UserRepository

    @MockK
    lateinit var passwordEncoder: PasswordEncoder

    @InjectMockKs
    lateinit var userService: UserService

    @Test
    fun `이메일 중복 시 DuplicateEmailException`() {
        // given
        every { userRepository.findByEmail("test@test.com") } returns User(email = "test@test.com", ...)

        // when & then
        assertThrows<DuplicateEmailException> {
            userService.createUser(CreateUserRequest("test@test.com", "테스트", "Test1234!"))
        }

        verify(exactly = 0) { userRepository.save(any()) }
    }

    @Test
    fun `정상 생성`() {
        // given
        every { userRepository.findByEmail("new@test.com") } returns null
        every { passwordEncoder.encode(any()) } returns "hashed"
        every { userRepository.save(any()) } answers { firstArg() }

        // when
        val result = userService.createUser(
            CreateUserRequest("new@test.com", "신규", "Test1234!")
        )

        // then
        assertThat(result.email).isEqualTo("new@test.com")
        verify(exactly = 1) { userRepository.findByEmail("new@test.com") }
        verify(exactly = 1) { userRepository.save(any()) }
    }
}
```

---

## 3. Integration Test — API

```kotlin
// src/test/kotlin/com/example/app/api/controller/UserControllerIntegrationTest.kt
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
@Transactional  // 각 테스트 후 롤백
class UserControllerIntegrationTest {

    @Autowired
    lateinit var mockMvc: MockMvc

    @Autowired
    lateinit var objectMapper: ObjectMapper

    @Test
    fun `사용자 생성 — 201 Created`() {
        val request = CreateUserRequest("test@example.com", "테스트", "Test1234!")

        mockMvc.perform(
            post("/api/v1/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request))
        )
            .andExpect(status().isCreated)
            .andExpect(jsonPath("$.email").value("test@example.com"))
    }

    @Test
    fun `존재하지 않는 사용자 — 404`() {
        mockMvc.perform(get("/api/v1/users/nonexistent-id"))
            .andExpect(status().isNotFound)
            .andExpect(jsonPath("$.error.code").value("USER_NOT_FOUND"))
    }

    @Test
    fun `유효성 실패 — 422`() {
        val request = mapOf("email" to "invalid", "name" to "", "password" to "short")

        mockMvc.perform(
            post("/api/v1/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request))
        )
            .andExpect(status().isUnprocessableEntity)
            .andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
    }
}
```

---

## 4. Testcontainers (실제 DB)

```kotlin
// src/test/kotlin/com/example/app/config/TestContainersConfig.kt
@TestConfiguration
class TestContainersConfig {
    companion object {
        @Container
        val postgres = PostgreSQLContainer("postgres:16-alpine").apply {
            withDatabaseName("test_db")
            withUsername("test")
            withPassword("test")
        }

        @JvmStatic
        @DynamicPropertySource
        fun properties(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url") { postgres.jdbcUrl }
            registry.add("spring.datasource.username") { postgres.username }
            registry.add("spring.datasource.password") { postgres.password }
        }
    }
}

@SpringBootTest
@Testcontainers
@Import(TestContainersConfig::class)
class UserRepositoryTest {
    @Autowired lateinit var userRepository: UserRepository

    @Test
    fun `이메일로 조회`() {
        userRepository.save(User(email = "test@test.com", name = "테스트", password = "hashed"))
        val found = userRepository.findByEmail("test@test.com")
        assertThat(found).isNotNull
        assertThat(found!!.email).isEqualTo("test@test.com")
    }
}
```

---

## 5. MockK 패턴

```kotlin
// Mock 생성
val mockService = mockk<UserService>()

// 동작 정의
every { mockService.getUser("1") } returns UserResponse(...)
every { mockService.createUser(any()) } throws DuplicateEmailException("test@test.com")

// Coroutine Mock
coEvery { mockService.getUser("1") } returns UserResponse(...)

// 호출 검증
verify(exactly = 1) { mockService.getUser("1") }
verify { mockService.createUser(match { it.email == "test@test.com" }) }

// Relaxed Mock (모든 메서드 기본값 반환)
val relaxedMock = mockk<UserService>(relaxed = true)

// Capture
val slot = slot<User>()
every { userRepository.save(capture(slot)) } answers { firstArg() }
// slot.captured.email 접근 가능
```

---

## 6. 테스트 설정

```kotlin
// build.gradle.kts
dependencies {
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("io.mockk:mockk:1.13.+")
    testImplementation("org.testcontainers:postgresql:1.19.+")
    testImplementation("org.testcontainers:junit-jupiter:1.19.+")
}

tasks.test {
    useJUnitPlatform()
    jvmArgs("-Xmx512m")
}
```

```yaml
# src/test/resources/application-test.yml
spring:
  datasource:
    url: jdbc:h2:mem:testdb  # H2 인메모리 (빠른 테스트)
  jpa:
    hibernate:
      ddl-auto: create-drop
  flyway:
    enabled: false  # 테스트에서 Flyway 비활성화
```

```bash
# 실행
./gradlew test                           # 전체
./gradlew test --tests "*UserService*"   # 특정 클래스
./gradlew test --tests "*이메일*"         # 패턴 매칭
./gradlew test -x integrationTest        # 통합 테스트 제외
./gradlew jacocoTestReport               # 커버리지
```
