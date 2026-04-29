# Database

> Kotlin/Spring Boot 버전 — 원본: Database

---

## 1. JPA Entity 설계

```kotlin
// domain/model/User.kt
@Entity
@Table(
    name = "users",
    indexes = [
        Index(name = "ix_users_email", columnList = "email", unique = true),
        Index(name = "ix_users_status_created", columnList = "status, created_at"),
    ],
)
class User(
    @Id
    @Column(length = 36)
    val id: String = UUID.randomUUID().toString(),

    @Column(unique = true, nullable = false, length = 255)
    val email: String,

    @Column(nullable = false, length = 100)
    var name: String,

    @Column(nullable = false, length = 255)
    var password: String,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    var status: UserStatus = UserStatus.ACTIVE,

    @Column(name = "deleted_at")
    var deletedAt: Instant? = null,

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    val createdAt: Instant = Instant.now(),

    @UpdateTimestamp
    @Column(name = "updated_at")
    var updatedAt: Instant = Instant.now(),
) {
    // 관계
    @OneToMany(mappedBy = "author", fetch = FetchType.LAZY)
    val posts: MutableList<Post> = mutableListOf()
}

enum class UserStatus {
    ACTIVE, INACTIVE, BANNED
}
```

---

## 2. 관계 매핑

```kotlin
// One-to-Many
@Entity
@Table(name = "posts")
class Post(
    @Id
    val id: String = UUID.randomUUID().toString(),

    @Column(nullable = false, length = 255)
    var title: String,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    val author: User,

    // Many-to-Many
    @ManyToMany
    @JoinTable(
        name = "post_tags",
        joinColumns = [JoinColumn(name = "post_id")],
        inverseJoinColumns = [JoinColumn(name = "tag_id")],
    )
    val tags: MutableSet<Tag> = mutableSetOf(),
)

@Entity
@Table(name = "tags")
class Tag(
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0,

    @Column(unique = true, nullable = false, length = 50)
    val name: String,

    @ManyToMany(mappedBy = "tags")
    val posts: MutableSet<Post> = mutableSetOf(),
)
```

---

## 3. Spring Data JPA Repository

```kotlin
// domain/repository/UserRepository.kt
interface UserRepository : JpaRepository<User, String> {
    fun findByEmail(email: String): User?
    fun findByStatus(status: UserStatus, pageable: Pageable): Page<User>
    fun findByDeletedAtIsNull(pageable: Pageable): Page<User>

    @Query("SELECT u FROM User u WHERE u.deletedAt IS NULL AND u.email = :email")
    fun findActiveByEmail(@Param("email") email: String): User?

    @Modifying
    @Query("UPDATE User u SET u.deletedAt = CURRENT_TIMESTAMP WHERE u.id = :id")
    fun softDelete(@Param("id") id: String): Int

    // Native Query
    @Query(
        value = "SELECT u.*, COUNT(p.id) as post_count FROM users u LEFT JOIN posts p ON u.id = p.user_id GROUP BY u.id ORDER BY post_count DESC",
        nativeQuery = true,
    )
    fun findUsersOrderByPostCount(): List<User>
}
```

---

## 4. QueryDSL (복잡한 동적 쿼리)

```kotlin
// 의존성: spring-boot-starter-data-jpa + querydsl-jpa

// infrastructure/repository/UserQueryRepository.kt
@Repository
class UserQueryRepository(
    private val queryFactory: JPAQueryFactory,
) {
    fun search(condition: UserSearchCondition, pageable: Pageable): Page<UserResponse> {
        val user = QUser.user
        val post = QPost.post

        val query = queryFactory
            .select(
                Projections.constructor(
                    UserResponse::class.java,
                    user.id, user.email, user.name, user.status,
                    user.createdAt, user.updatedAt,
                )
            )
            .from(user)
            .where(
                user.deletedAt.isNull,
                condition.status?.let { user.status.eq(it) },
                condition.name?.let { user.name.containsIgnoreCase(it) },
                condition.fromDate?.let { user.createdAt.goe(it) },
            )
            .orderBy(user.createdAt.desc())
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())

        val content = query.fetch()
        val total = query.fetchCount()

        return PageImpl(content, pageable, total)
    }
}
```

---

## 5. 마이그레이션 (Flyway)

```sql
-- src/main/resources/db/migration/V1__create_users_table.sql
CREATE TABLE users (
    id          VARCHAR(36) PRIMARY KEY,
    email       VARCHAR(255) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    password    VARCHAR(255) NOT NULL,
    status      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    deleted_at  TIMESTAMP,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_users_status_created ON users (status, created_at);
```

```yaml
# application.yml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true
```

---

## 6. 트랜잭션 관리

```kotlin
@Service
@Transactional(readOnly = true)  // 기본: 읽기 전용
class UserService(
    private val userRepository: UserRepository,
) {
    @Transactional  // 쓰기 트랜잭션
    fun createUser(request: CreateUserRequest): UserResponse {
        // 트랜잭션 내 실행
        val user = userRepository.save(User(...))
        return UserResponse.from(user)
    }

    // readOnly = true → 스냅샷 격리, 성능 향상
    fun getUser(userId: String): UserResponse {
        val user = userRepository.findById(userId)
            .orElseThrow { UserNotFoundException(userId) }
        return UserResponse.from(user)
    }
}
```

---

## 7. Soft Delete 패턴

```kotlin
// @SQLRestriction으로 자동 필터링 (Hibernate 6.3+)
@Entity
@SQLRestriction("deleted_at IS NULL")
class User(
    // ...
    var deletedAt: Instant? = null,
)

// 또는 @Where (구버전)
@Entity
@Where(clause = "deleted_at IS NULL")
class User(...)
```

---

## 8. Connection Pool (HikariCP)

```yaml
# application.yml — Spring Boot 기본 HikariCP
spring:
  datasource:
    url: ${DATABASE_URL}
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      idle-timeout: 300000       # 5분
      max-lifetime: 1800000      # 30분
      connection-timeout: 30000  # 30초
      pool-name: identity-hub-pool
```
