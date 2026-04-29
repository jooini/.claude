# Security

> Kotlin/Spring Boot 버전 — 원본: Security

---

## 1. 인증 (Authentication)

### JWT + Refresh Token

```kotlin
// common/util/JwtUtil.kt
@Component
class JwtUtil(
    @Value("\${jwt.secret}") private val secret: String,
    @Value("\${jwt.access-expiration}") private val accessExpiration: Long,
    @Value("\${jwt.refresh-expiration}") private val refreshExpiration: Long,
) {
    private val key: SecretKey = Keys.hmacShaKeyFor(secret.toByteArray())

    fun createAccessToken(userId: String): String {
        return Jwts.builder()
            .subject(userId)
            .issuedAt(Date())
            .expiration(Date(System.currentTimeMillis() + accessExpiration))
            .signWith(key)
            .compact()
    }

    fun createRefreshToken(userId: String): String {
        return Jwts.builder()
            .subject(userId)
            .issuedAt(Date())
            .expiration(Date(System.currentTimeMillis() + refreshExpiration))
            .signWith(key)
            .compact()
    }

    fun validateToken(token: String): Claims {
        return Jwts.parser()
            .verifyWith(key)
            .build()
            .parseSignedClaims(token)
            .payload
    }
}
```

### Spring Security Filter

```kotlin
// infrastructure/config/SecurityConfig.kt
@Configuration
@EnableWebSecurity
class SecurityConfig(
    private val jwtAuthFilter: JwtAuthenticationFilter,
) {
    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        return http
            .csrf { it.disable() }
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .authorizeHttpRequests {
                it.requestMatchers("/api/v1/auth/**").permitAll()
                it.requestMatchers("/health", "/metrics").permitAll()
                it.requestMatchers("/api/v1/admin/**").hasRole("ADMIN")
                it.anyRequest().authenticated()
            }
            .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter::class.java)
            .build()
    }

    @Bean
    fun passwordEncoder(): PasswordEncoder = BCryptPasswordEncoder()
}

// infrastructure/filter/JwtAuthenticationFilter.kt
@Component
class JwtAuthenticationFilter(
    private val jwtUtil: JwtUtil,
    private val userRepository: UserRepository,
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val token = extractToken(request)
        if (token != null) {
            try {
                val claims = jwtUtil.validateToken(token)
                val userId = claims.subject
                val user = userRepository.findById(userId).orElse(null)

                if (user != null) {
                    val auth = UsernamePasswordAuthenticationToken(user, null, user.authorities)
                    SecurityContextHolder.getContext().authentication = auth
                }
            } catch (e: Exception) {
                // 유효하지 않은 토큰 — 인증 없이 계속
            }
        }
        filterChain.doFilter(request, response)
    }

    private fun extractToken(request: HttpServletRequest): String? {
        return request.getHeader("Authorization")
            ?.takeIf { it.startsWith("Bearer ") }
            ?.substring(7)
    }
}
```

### Refresh Token (Redis)

```kotlin
// domain/service/AuthService.kt
@Service
class AuthService(
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder,
    private val jwtUtil: JwtUtil,
    private val redisTemplate: StringRedisTemplate,
) {
    fun login(email: String, password: String): TokenResponse {
        val user = userRepository.findByEmail(email)
            ?: throw UnauthorizedException("인증 실패")

        if (!passwordEncoder.matches(password, user.password)) {
            throw UnauthorizedException("인증 실패")
        }

        val accessToken = jwtUtil.createAccessToken(user.id)
        val refreshToken = jwtUtil.createRefreshToken(user.id)

        // Redis에 refresh token 저장
        redisTemplate.opsForValue().set(
            "refresh:${user.id}",
            refreshToken,
            Duration.ofDays(7),
        )

        return TokenResponse(accessToken, refreshToken)
    }

    fun refresh(refreshToken: String): TokenResponse {
        val claims = jwtUtil.validateToken(refreshToken)
        val userId = claims.subject

        val stored = redisTemplate.opsForValue().get("refresh:$userId")
        if (stored != refreshToken) {
            throw UnauthorizedException("유효하지 않은 refresh token")
        }

        val newAccess = jwtUtil.createAccessToken(userId)
        val newRefresh = jwtUtil.createRefreshToken(userId)
        redisTemplate.opsForValue().set("refresh:$userId", newRefresh, Duration.ofDays(7))

        return TokenResponse(newAccess, newRefresh)
    }
}
```

---

## 2. 인가 (Authorization)

### RBAC

```kotlin
// 메서드 레벨 보안
@PreAuthorize("hasRole('ADMIN')")
@DeleteMapping("/{userId}")
fun deleteUser(@PathVariable userId: String): ResponseEntity<Void> { ... }

@PreAuthorize("hasAnyRole('ADMIN', 'MANAGER')")
@GetMapping("/reports")
fun getReports(): ResponseEntity<List<Report>> { ... }

// 리소스 소유권 검증
@PreAuthorize("#userId == authentication.principal.id or hasRole('ADMIN')")
@GetMapping("/{userId}/profile")
fun getProfile(@PathVariable userId: String): ResponseEntity<UserProfile> { ... }
```

### 커스텀 권한 체크

```kotlin
@Component("authChecker")
class AuthorizationChecker(
    private val postRepository: PostRepository,
) {
    fun isPostOwner(postId: String, userId: String): Boolean {
        return postRepository.findById(postId)
            .map { it.author.id == userId }
            .orElse(false)
    }
}

// 사용
@PreAuthorize("@authChecker.isPostOwner(#postId, authentication.principal.id)")
@DeleteMapping("/posts/{postId}")
fun deletePost(@PathVariable postId: String) { ... }
```

---

## 3. 입력 검증 (Bean Validation)

```kotlin
data class CreateUserRequest(
    @field:NotBlank(message = "이메일은 필수입니다")
    @field:Email(message = "올바른 이메일 형식이 아닙니다")
    val email: String,

    @field:NotBlank
    @field:Size(min = 1, max = 100)
    val name: String,

    @field:NotBlank
    @field:Pattern(
        regexp = "^(?=.*[A-Z])(?=.*[0-9]).{8,128}$",
        message = "비밀번호는 대문자, 숫자 포함 8자 이상",
    )
    val password: String,
)
```

---

## 4. Rate Limiting (Bucket4j)

```kotlin
// infrastructure/filter/RateLimitFilter.kt
@Component
class RateLimitFilter(
    private val redisTemplate: StringRedisTemplate,
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val clientIp = request.remoteAddr
        val key = "rate:$clientIp"
        val count = redisTemplate.opsForValue().increment(key) ?: 0

        if (count == 1L) {
            redisTemplate.expire(key, Duration.ofMinutes(1))
        }

        if (count > 60) {  // 분당 60회
            response.status = 429
            response.writer.write("""{"error":"Too Many Requests"}""")
            return
        }

        filterChain.doFilter(request, response)
    }
}
```

---

## 5. CORS 설정

```kotlin
@Configuration
class CorsConfig : WebMvcConfigurer {
    override fun addCorsMappings(registry: CorsRegistry) {
        registry.addMapping("/api/**")
            .allowedOrigins("https://app.example.com")
            .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
            .allowedHeaders("Authorization", "Content-Type", "X-Request-ID")
            .allowCredentials(true)
            .maxAge(3600)
    }
}
```

---

## 6. 보안 헤더

```kotlin
// SecurityConfig에서 설정
http.headers {
    it.contentTypeOptions { }
    it.frameOptions { fo -> fo.deny() }
    it.xssProtection { xss -> xss.headerValue(XXssProtectionHeaderWriter.HeaderValue.ENABLED_MODE_BLOCK) }
    it.httpStrictTransportSecurity { hsts ->
        hsts.includeSubDomains(true)
        hsts.maxAgeInSeconds(31536000)
    }
    it.cacheControl { }
}
```
