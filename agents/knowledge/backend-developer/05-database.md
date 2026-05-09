# Database

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/database

---

## 1. TypeORM 엔티티 설계

```ts
@Entity('users')
export class UserEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string

  @Column({ unique: true, length: 255 })
  email: string

  @Column({ length: 100 })
  name: string

  @Column({ select: false })  // 기본 조회에서 제외
  password: string

  @Column({ type: 'enum', enum: UserStatus, default: UserStatus.ACTIVE })
  status: UserStatus

  @CreateDateColumn()
  createdAt: Date

  @UpdateDateColumn()
  updatedAt: Date

  @DeleteDateColumn()  // Soft Delete
  deletedAt: Date | null

  // 관계
  @OneToMany(() => PostEntity, post => post.author)
  posts: PostEntity[]
}

@Entity('posts')
export class PostEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string

  @Column({ length: 200 })
  title: string

  @Column('text')
  content: string

  @ManyToOne(() => UserEntity, user => user.posts)
  @JoinColumn({ name: 'author_id' })
  author: UserEntity

  @Column()
  authorId: string  // FK 직접 접근용

  @CreateDateColumn()
  createdAt: Date
}
```

---

## 2. 관계 설정

```ts
// One-to-Many / Many-to-One
@OneToMany(() => OrderItemEntity, item => item.order, {
  cascade: true,        // Order 저장 시 OrderItem도 함께
  eager: false,         // 명시적 로딩 (기본값)
})
items: OrderItemEntity[]

@ManyToOne(() => OrderEntity, order => order.items, {
  onDelete: 'CASCADE',  // Order 삭제 시 Item도 삭제
})
order: OrderEntity

// Many-to-Many
@ManyToMany(() => TagEntity)
@JoinTable({
  name: 'post_tags',
  joinColumn: { name: 'post_id' },
  inverseJoinColumn: { name: 'tag_id' },
})
tags: TagEntity[]

// One-to-One
@OneToOne(() => ProfileEntity, { cascade: true })
@JoinColumn()
profile: ProfileEntity
```

---

## 3. 마이그레이션

```ts
// typeorm 설정 — 운영에서는 synchronize: false 필수
TypeOrmModule.forRoot({
  synchronize: process.env.NODE_ENV !== 'production',  // 개발만 true
  migrations: ['dist/migrations/*.js'],
  migrationsRun: true,  // 앱 시작 시 자동 실행
})
```

```bash
# 마이그레이션 생성
npx typeorm migration:generate src/migrations/AddUserStatus -d src/data-source.ts

# 마이그레이션 실행
npx typeorm migration:run -d src/data-source.ts

# 마이그레이션 롤백
npx typeorm migration:revert -d src/data-source.ts
```

```ts
// 마이그레이션 파일
export class AddUserStatus1699000000000 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE users
      ADD COLUMN status ENUM('active', 'inactive', 'banned') NOT NULL DEFAULT 'active'
    `)
    await queryRunner.query(`
      CREATE INDEX idx_users_status ON users(status)
    `)
  }

  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX idx_users_status ON users`)
    await queryRunner.query(`ALTER TABLE users DROP COLUMN status`)
  }
}
```

---

## 4. 쿼리 최적화

### N+1 문제

```ts
// ❌ N+1 — 유저 조회 후 각각 posts 조회 (유저 수 + 1번 쿼리)
const users = await userRepo.find()
for (const user of users) {
  user.posts = await postRepo.find({ where: { authorId: user.id } })
}

// ✅ JOIN으로 한 번에
const users = await userRepo.find({
  relations: ['posts'],  // 자동 LEFT JOIN
})

// 또는 QueryBuilder
const users = await userRepo
  .createQueryBuilder('user')
  .leftJoinAndSelect('user.posts', 'post')
  .where('user.status = :status', { status: 'active' })
  .getMany()
```

### 인덱스

```ts
@Entity('orders')
@Index(['userId', 'status'])     // 복합 인덱스
@Index(['createdAt'])
export class OrderEntity {
  @Column()
  @Index()                       // 단일 컬럼 인덱스
  userId: string

  @Column()
  status: string
}

// 인덱스 설계 원칙
// - WHERE 조건에 자주 쓰이는 컬럼
// - JOIN ON 조건 컬럼 (FK는 자동)
// - ORDER BY 컬럼
// - 카디널리티 높은 컬럼 우선 (status보단 userId)
```

---

## 5. 트랜잭션

```ts
// TypeORM DataSource 트랜잭션
@Injectable()
export class OrdersService {
  constructor(private readonly dataSource: DataSource) {}

  async createOrder(dto: CreateOrderDto): Promise<Order> {
    return this.dataSource.transaction(async manager => {
      // 모두 성공하거나 모두 실패
      const order = await manager.save(OrderEntity, {
        userId: dto.userId,
        status: 'pending',
      })

      for (const item of dto.items) {
        // 재고 차감
        await manager.decrement(
          ProductEntity,
          { id: item.productId },
          'stock',
          item.quantity,
        )

        await manager.save(OrderItemEntity, {
          orderId: order.id,
          productId: item.productId,
          quantity: item.quantity,
        })
      }

      return order
    })
  }
}
```

---

## 6. Soft Delete

```ts
// TypeORM Soft Delete — deletedAt 컬럼 활용
@Entity()
export class UserEntity {
  @DeleteDateColumn()
  deletedAt: Date | null
}

// 삭제 (실제 삭제 X, deletedAt 설정)
await userRepo.softDelete(id)

// 조회 — 삭제된 것 자동 제외
await userRepo.find()

// 삭제된 것 포함 조회
await userRepo.find({ withDeleted: true })

// 복구
await userRepo.restore(id)
```

---

## 7. 안티패턴

- **운영에서 synchronize: true**: 스키마 자동 변경으로 데이터 손실 위험
- **N+1 무시**: 관계 조회 시 relations 또는 QueryBuilder 사용
- **인덱스 없는 FK/검색 컬럼**: 데이터 증가 시 쿼리 급격히 느려짐
- **긴 트랜잭션**: 락 경합, 데드락 위험 → 최소 범위로
- **SELECT * 습관**: 필요한 컬럼만 select (특히 text/blob)
