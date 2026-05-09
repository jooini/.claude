# Spring Data JPA

> Kotlin/Spring Boot 버전 — 원본: Drizzle ORM

---

## 1. Spring Data JPA란?

JPA(Hibernate) 기반 Repository 추상화. 메서드 이름만으로 쿼리 자동 생성, 페이지네이션 기본 지원.

**TypeORM vs Spring Data JPA:**

| 항목 | TypeORM | Spring Data JPA |
|------|---------|-----------------|
| 방식 | Decorator 기반 | 인터페이스 메서드명 |
| SQL 접근성 | QueryBuilder | JPQL / QueryDSL |
| 타입 안전성 | 제한적 | QueryDSL로 완전 타입 안전 |
| 마이그레이션 | TypeORM CLI | Flyway / Liquibase |
| 캐시 | 없음 | 1차/2차 캐시 내장 |

---

## 2. CRUD 작업

### Create

```kotlin
// 단건 저장
val user = User(email = "test@test.com", name = "테스트", password = encoded)
val saved = userRepository.save(user)  // INSERT

// 벌크 삽입
val users = listOf(User(...), User(...), User(...))
userRepository.saveAll(users)  // 각각 INSERT (배치 가능)
```

```yaml
# 배치 INSERT 활성화
spring:
  jpa:
    properties:
      hibernate:
        jdbc.batch_size: 50
        order_inserts: true
```

### Read

```kotlin
// PK 조회
val user = userRepository.findById(userId).orElseThrow { UserNotFoundException(userId) }

// 메서드명 쿼리 자동 생성
interface UserRepository : JpaRepository<User, String> {
    fun findByEmail(email: String): User?
    fun findByStatusAndCreatedAtAfter(status: UserStatus, after: Instant): List<User>
    fun findByNameContainingIgnoreCase(name: String): List<User>
    fun countByStatus(status: UserStatus): Long
    fun existsByEmail(email: String): Boolean
}

// N+1 방지 — @EntityGraph
@EntityGraph(attributePaths = ["posts"])
fun findWithPostsById(id: String): User?

// N+1 방지 — JPQL FETCH JOIN
@Query("SELECT u FROM User u LEFT JOIN FETCH u.posts WHERE u.id = :id")
fun findWithPostsJpql(@Param("id") id: String): User?
```

### Update

```kotlin
// 더티 체킹 (JPA 기본)
@Transactional
fun updateUser(userId: String, request: UpdateUserRequest): UserResponse {
    val user = userRepository.findById(userId).orElseThrow { UserNotFoundException(userId) }
    request.name?.let { user.name = it }       // 변경 감지 → 자동 UPDATE
    request.status?.let { user.status = UserStatus.valueOf(it) }
    return UserResponse.from(user)  // flush 시 UPDATE 실행
}

// 벌크 수정 (더티 체킹 우회, 대량 데이터에 유리)
@Modifying(clearAutomatically = true)
@Query("UPDATE User u SET u.status = :status WHERE u.createdAt < :before")
fun deactivateOldUsers(@Param("status") status: UserStatus, @Param("before") before: Instant): Int
```

### Delete

```kotlin
// Hard delete
userRepository.deleteById(userId)

// Soft delete
@Modifying
@Query("UPDATE User u SET u.deletedAt = CURRENT_TIMESTAMP WHERE u.id = :id")
fun softDelete(@Param("id") id: String): Int
```

---

## 3. 페이지네이션

```kotlin
// Spring Data Pageable
fun listUsers(page: Int, size: Int): Page<UserResponse> {
    val pageable = PageRequest.of(page - 1, size, Sort.by("createdAt").descending())
    return userRepository.findByDeletedAtIsNull(pageable)
        .map { UserResponse.from(it) }
}

// Slice (전체 카운트 없음 — 무한 스크롤에 적합)
fun findByStatus(status: UserStatus, pageable: Pageable): Slice<User>
```

---

## 4. Specification (동적 쿼리)

```kotlin
// Spring Data Specification
class UserSpecs {
    companion object {
        fun hasStatus(status: UserStatus?): Specification<User> =
            Specification { root, _, cb ->
                status?.let { cb.equal(root.get<UserStatus>("status"), it) }
            }

        fun nameContains(name: String?): Specification<User> =
            Specification { root, _, cb ->
                name?.let { cb.like(cb.lower(root.get("name")), "%${it.lowercase()}%") }
            }

        fun isActive(): Specification<User> =
            Specification { root, _, cb ->
                cb.isNull(root.get<Instant>("deletedAt"))
            }
    }
}

// 사용
val spec = UserSpecs.isActive()
    .and(UserSpecs.hasStatus(status))
    .and(UserSpecs.nameContains(name))

userRepository.findAll(spec, pageable)
```

---

## 5. Raw SQL (필요 시)

```kotlin
// Native Query
@Query(
    value = """
        SELECT u.id, u.email, COUNT(p.id) as post_count
        FROM users u
        LEFT JOIN posts p ON u.id = p.user_id
        WHERE u.status = :status
        GROUP BY u.id, u.email
        HAVING COUNT(p.id) > :minPosts
    """,
    nativeQuery = true,
)
fun findActiveUsersWithPosts(
    @Param("status") status: String,
    @Param("minPosts") minPosts: Int,
): List<Array<Any>>

// JdbcTemplate (완전한 SQL 제어)
@Repository
class UserJdbcRepository(
    private val jdbcTemplate: JdbcTemplate,
) {
    fun findByCustomQuery(status: String): List<UserDto> {
        return jdbcTemplate.query(
            "SELECT id, email, name FROM users WHERE status = ?",
            { rs, _ -> UserDto(rs.getString("id"), rs.getString("email"), rs.getString("name")) },
            status,
        )
    }
}
```

---

## 6. 인덱스 전략

```kotlin
@Entity
@Table(
    name = "orders",
    indexes = [
        Index(name = "ix_orders_user_status", columnList = "user_id, status"),
        Index(name = "ix_orders_created", columnList = "created_at"),
    ],
    uniqueConstraints = [
        UniqueConstraint(name = "uk_orders_number", columnNames = ["order_number"]),
    ],
)
class Order(
    @Id val id: String = UUID.randomUUID().toString(),
    @Column(name = "user_id", nullable = false) val userId: String,
    @Column(nullable = false, length = 20) val status: String,
    @Column(nullable = false) val amount: Long,
    @Column(name = "order_number", unique = true) val orderNumber: String,
    @Column(name = "created_at") val createdAt: Instant = Instant.now(),
)
```
