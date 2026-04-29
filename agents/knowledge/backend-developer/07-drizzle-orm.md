# Drizzle ORM

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/drizzle-orm

---

## 1. Drizzle ORM이란?

TypeScript 우선 ORM. SQL에 가깝고 타입 안전. TypeORM 대비 가볍고 번들 크기 작음.

**TypeORM vs Drizzle:**
| 항목 | TypeORM | Drizzle |
|------|---------|---------|
| 방식 | Decorator 기반 | 함수형 |
| SQL 접근성 | 추상화 높음 | SQL에 가까움 |
| 타입 안전성 | 제한적 | 완전한 추론 |
| 번들 크기 | 무거움 | 가벼움 |
| NestJS 통합 | 공식 지원 | 직접 설정 |

---

## 2. 스키마 정의

```ts
// schema/users.ts
import { pgTable, uuid, varchar, pgEnum, timestamp, boolean } from 'drizzle-orm/pg-core'

export const userStatusEnum = pgEnum('user_status', ['active', 'inactive', 'banned'])

export const users = pgTable('users', {
  id:        uuid('id').defaultRandom().primaryKey(),
  email:     varchar('email', { length: 255 }).notNull().unique(),
  name:      varchar('name', { length: 100 }).notNull(),
  password:  varchar('password', { length: 255 }).notNull(),
  status:    userStatusEnum('status').default('active').notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
})

// 관계 스키마
export const posts = pgTable('posts', {
  id:       uuid('id').defaultRandom().primaryKey(),
  title:    varchar('title', { length: 200 }).notNull(),
  content:  varchar('content').notNull(),
  authorId: uuid('author_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
})

// 관계 정의 (조인 쿼리에 사용)
import { relations } from 'drizzle-orm'

export const usersRelations = relations(users, ({ many }) => ({
  posts: many(posts),
}))

export const postsRelations = relations(posts, ({ one }) => ({
  author: one(users, {
    fields: [posts.authorId],
    references: [users.id],
  }),
}))

// 타입 추론
export type User = typeof users.$inferSelect
export type NewUser = typeof users.$inferInsert
```

---

## 3. 기본 CRUD

```ts
import { drizzle } from 'drizzle-orm/node-postgres'
import { eq, and, like, desc, count } from 'drizzle-orm'
import { users, posts } from './schema'

const db = drizzle(pool, { schema: { users, posts } })

// SELECT
const allUsers = await db.select().from(users)

// 특정 컬럼만
const userPreviews = await db
  .select({ id: users.id, name: users.name, email: users.email })
  .from(users)

// WHERE
const activeUser = await db
  .select()
  .from(users)
  .where(and(
    eq(users.id, userId),
    eq(users.status, 'active'),
  ))
  .limit(1)

// INSERT
const [newUser] = await db
  .insert(users)
  .values({ email: 'hong@example.com', name: '홍길동', password: hashedPw })
  .returning()  // 삽입된 행 반환

// UPDATE
const [updated] = await db
  .update(users)
  .set({ name: '홍길순', updatedAt: new Date() })
  .where(eq(users.id, userId))
  .returning()

// DELETE
await db.delete(users).where(eq(users.id, userId))
```

---

## 4. 조인 & 관계 쿼리

```ts
// JOIN
const usersWithPosts = await db
  .select({
    user: users,
    postCount: count(posts.id),
  })
  .from(users)
  .leftJoin(posts, eq(posts.authorId, users.id))
  .groupBy(users.id)
  .orderBy(desc(count(posts.id)))

// 관계 쿼리 (with)
const usersWithPosts = await db.query.users.findMany({
  with: {
    posts: {
      orderBy: [desc(posts.createdAt)],
      limit: 5,
    },
  },
  where: eq(users.status, 'active'),
})
// 타입: Array<User & { posts: Post[] }>
```

---

## 5. 페이지네이션

```ts
// Offset 기반
async function getUsers(page: number, limit: number) {
  const [data, [{ total }]] = await Promise.all([
    db
      .select()
      .from(users)
      .orderBy(desc(users.createdAt))
      .limit(limit)
      .offset((page - 1) * limit),
    db.select({ total: count() }).from(users),
  ])

  return {
    data,
    meta: {
      total: Number(total),
      page,
      limit,
      totalPages: Math.ceil(Number(total) / limit),
    },
  }
}

// Cursor 기반
async function getUsersCursor(cursor: string | null, limit: number) {
  const data = await db
    .select()
    .from(users)
    .where(cursor ? gt(users.createdAt, new Date(cursor)) : undefined)
    .orderBy(desc(users.createdAt))
    .limit(limit + 1)  // 다음 페이지 존재 여부 확인용

  const hasNextPage = data.length > limit
  return {
    data: data.slice(0, limit),
    nextCursor: hasNextPage ? data[limit - 1].createdAt.toISOString() : null,
  }
}
```

---

## 6. 트랜잭션

```ts
const result = await db.transaction(async tx => {
  const [order] = await tx
    .insert(orders)
    .values({ userId, total })
    .returning()

  for (const item of items) {
    // 재고 차감
    await tx
      .update(products)
      .set({ stock: sql`${products.stock} - ${item.quantity}` })
      .where(and(
        eq(products.id, item.productId),
        gte(products.stock, item.quantity),  // 재고 체크
      ))

    await tx.insert(orderItems).values({
      orderId: order.id,
      productId: item.productId,
      quantity: item.quantity,
    })
  }

  return order
})
```

---

## 7. 마이그레이션

```ts
// drizzle.config.ts
import { defineConfig } from 'drizzle-kit'

export default defineConfig({
  schema: './src/schema',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
})
```

```bash
# 마이그레이션 생성 (스키마 변경 감지)
npx drizzle-kit generate

# 마이그레이션 적용
npx drizzle-kit migrate

# Drizzle Studio (DB GUI)
npx drizzle-kit studio
```

---

## 8. NestJS 통합

```ts
// database/database.module.ts
import { drizzle } from 'drizzle-orm/node-postgres'
import { Pool } from 'pg'
import * as schema from './schema'

export const DRIZZLE = Symbol('DRIZZLE')

@Module({
  providers: [
    {
      provide: DRIZZLE,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const pool = new Pool({ connectionString: config.get('DATABASE_URL') })
        return drizzle(pool, { schema })
      },
    },
  ],
  exports: [DRIZZLE],
})
export class DatabaseModule {}

// 서비스에서 사용
@Injectable()
export class UsersRepository {
  constructor(@Inject(DRIZZLE) private db: NodePgDatabase<typeof schema>) {}

  async findById(id: string) {
    return this.db.query.users.findFirst({ where: eq(schema.users.id, id) })
  }
}
```

---

## 9. 안티패턴

- **raw SQL 문자열 직접 사용**: SQL 인젝션 위험. `sql` 태그드 템플릿 사용
- **스키마 없이 쿼리**: 타입 추론 불가
- **트랜잭션 밖의 연관 작업**: 일관성 보장 안 됨
- **select() 후 JS 필터링**: DB에서 WHERE로 필터링
