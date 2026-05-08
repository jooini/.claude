# Database Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/database-testing

---

## 1. DB 테스트 범위

```
스키마 검증    — 마이그레이션 올바르게 적용됐는가
쿼리 검증      — 의도한 결과를 반환하는가
제약 조건      — Unique, FK, Not Null 등 동작 확인
트랜잭션       — 원자성, 롤백 동작 확인
성능           — 인덱스 효율, 슬로우 쿼리
```

---

## 2. 마이그레이션 테스트

```ts
describe('Database Migration', () => {
  let dataSource: DataSource

  beforeAll(async () => {
    dataSource = new DataSource({
      type: 'postgres',
      url: process.env.TEST_DATABASE_URL,
      entities: ['src/**/*.entity.ts'],
      migrations: ['src/migrations/*.ts'],
    })
    await dataSource.initialize()
  })

  afterAll(() => dataSource.destroy())

  it('마이그레이션이 오류 없이 실행됨', async () => {
    await expect(dataSource.runMigrations()).resolves.not.toThrow()
  })

  it('마이그레이션 롤백이 동작함', async () => {
    await dataSource.runMigrations()
    await expect(dataSource.undoLastMigration()).resolves.not.toThrow()
    await expect(dataSource.runMigrations()).resolves.not.toThrow()
  })

  it('users 테이블 스키마 확인', async () => {
    const columns = await dataSource.query(`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'users'
    `)

    const columnMap = Object.fromEntries(
      columns.map((c: any) => [c.column_name, c])
    )

    expect(columnMap.id.data_type).toBe('uuid')
    expect(columnMap.email.is_nullable).toBe('NO')
    expect(columnMap.created_at.data_type).toBe('timestamp with time zone')
  })
})
```

---

## 3. 제약 조건 테스트

```ts
describe('DB 제약 조건', () => {
  it('이메일 Unique 제약 — 중복 삽입 거부', async () => {
    await dataSource.query(
      "INSERT INTO users (id, email, name) VALUES (gen_random_uuid(), 'test@test.com', 'User1')"
    )
    await expect(
      dataSource.query(
        "INSERT INTO users (id, email, name) VALUES (gen_random_uuid(), 'test@test.com', 'User2')"
      )
    ).rejects.toThrow()  // unique violation
  })

  it('NOT NULL 제약 — 이름 없이 삽입 거부', async () => {
    await expect(
      dataSource.query(
        "INSERT INTO users (id, email) VALUES (gen_random_uuid(), 'test2@test.com')"
      )
    ).rejects.toThrow()
  })

  it('FK 제약 — 존재하지 않는 userId로 주문 생성 거부', async () => {
    await expect(
      dataSource.query(
        "INSERT INTO orders (id, user_id, total) VALUES (gen_random_uuid(), gen_random_uuid(), 10000)"
      )
    ).rejects.toThrow()  // FK violation
  })

  it('Cascade Delete — 사용자 삭제 시 주문도 삭제', async () => {
    const [user] = await dataSource.query(
      "INSERT INTO users (id, email, name) VALUES (gen_random_uuid(), 'cascade@test.com', 'User') RETURNING id"
    )
    await dataSource.query(
      `INSERT INTO orders (id, user_id, total) VALUES (gen_random_uuid(), '${user.id}', 10000)`
    )

    await dataSource.query(`DELETE FROM users WHERE id = '${user.id}'`)

    const orders = await dataSource.query(`SELECT * FROM orders WHERE user_id = '${user.id}'`)
    expect(orders).toHaveLength(0)
  })
})
```

---

## 4. 쿼리 성능 테스트

```ts
describe('쿼리 성능', () => {
  beforeAll(async () => {
    // 대용량 테스트 데이터 생성
    await seedUsers(10000)
    await seedOrders(50000)
  })

  it('사용자 이메일 조회가 50ms 이내', async () => {
    const start = Date.now()
    await userRepo.findOne({ where: { email: 'user5000@test.com' } })
    const duration = Date.now() - start

    expect(duration).toBeLessThan(50)
  })

  it('사용자별 주문 목록 조회 — EXPLAIN으로 인덱스 사용 확인', async () => {
    const plan = await dataSource.query(`
      EXPLAIN (FORMAT JSON)
      SELECT * FROM orders WHERE user_id = $1
    `, ['some-uuid'])

    const planText = JSON.stringify(plan)
    expect(planText).toContain('Index Scan')  // Seq Scan이면 인덱스 없음
    expect(planText).not.toContain('Seq Scan')
  })
})
```

---

## 5. 트랜잭션 테스트

```ts
describe('트랜잭션', () => {
  it('재고 차감 실패 시 주문 생성도 롤백', async () => {
    const initialStock = await getStock('product-1')

    await expect(
      orderService.create({
        productId: 'product-1',
        quantity: initialStock + 10,  // 재고 초과 → 실패
      })
    ).rejects.toThrow()

    // 주문이 생성되지 않았어야 함
    const orders = await orderRepo.findBy({ productId: 'product-1' })
    expect(orders).toHaveLength(0)

    // 재고가 변경되지 않았어야 함
    const currentStock = await getStock('product-1')
    expect(currentStock).toBe(initialStock)
  })
})
```

---

## 6. 안티패턴

- **프로덕션 DB 테스트**: 전용 TEST_DATABASE_URL 필수
- **마이그레이션 롤백 테스트 없음**: 배포 실패 시 롤백 불가
- **제약 조건 테스트 없음**: 운영에서 데이터 무결성 문제 발생
- **대용량 데이터 성능 테스트 없음**: 소량에서 빠르지만 대량에서 느림
- **테스트 후 정리 없음**: 남은 데이터가 다른 테스트에 영향
