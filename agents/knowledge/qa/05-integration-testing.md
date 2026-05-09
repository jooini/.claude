# Integration Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/integration-testing

---

## 1. 통합 테스트란

두 개 이상의 컴포넌트가 함께 동작하는 것을 검증.
단위 테스트가 놓친 **인터페이스 버그** 탐지에 효과적.

**통합 테스트가 필요한 이유:**
- 각 모듈이 독립적으로는 완벽하지만 함께 쓰면 버그 발생
- DB 스키마와 ORM 매핑 오류
- API 계약(Contract) 위반

---

## 2. 테스트 범위

```
단위 테스트    [함수] [함수] [함수]
                 ↓
통합 테스트    [Service + Repository + DB]
통합 테스트    [Controller + Service + Guard]
                 ↓
E2E 테스트    [전체 스택 + 실제 HTTP]
```

---

## 3. DB 통합 테스트

```ts
// NestJS + TypeORM 통합 테스트
describe('UsersRepository (Integration)', () => {
  let app: INestApplication
  let repo: UsersRepository
  let dataSource: DataSource

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [
        TypeOrmModule.forRoot({
          type: 'postgres',
          url: process.env.TEST_DATABASE_URL,
          entities: [UserEntity, PostEntity],
          synchronize: true,
        }),
        TypeOrmModule.forFeature([UserEntity]),
      ],
      providers: [UsersRepository],
    }).compile()

    repo = module.get(UsersRepository)
    dataSource = module.get(DataSource)
    app = module.createNestApplication()
    await app.init()
  })

  // 각 테스트 후 데이터 정리
  afterEach(async () => {
    await dataSource.query('TRUNCATE users CASCADE')
  })

  afterAll(async () => {
    await app.close()
  })

  describe('create', () => {
    it('사용자 생성 및 ID 자동 할당', async () => {
      const user = await repo.create({
        email: 'test@example.com',
        name: '홍길동',
        password: 'hashed_password',
      })

      expect(user.id).toBeDefined()
      expect(user.id).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      )
      expect(user.createdAt).toBeInstanceOf(Date)
    })

    it('이메일 중복 생성 시 UniqueConstraintError', async () => {
      await repo.create({ email: 'dup@example.com', name: 'A', password: 'pw' })

      await expect(
        repo.create({ email: 'dup@example.com', name: 'B', password: 'pw' })
      ).rejects.toThrow()
    })
  })

  describe('findAll with pagination', () => {
    beforeEach(async () => {
      // 테스트 데이터 시딩
      await repo.create({ email: 'user1@test.com', name: '유저1', password: 'pw' })
      await repo.create({ email: 'user2@test.com', name: '유저2', password: 'pw' })
      await repo.create({ email: 'user3@test.com', name: '유저3', password: 'pw' })
    })

    it('페이지네이션 정상 동작', async () => {
      const result = await repo.findAll({ page: 1, limit: 2 })

      expect(result.data).toHaveLength(2)
      expect(result.meta.total).toBe(3)
      expect(result.meta.totalPages).toBe(2)
    })

    it('검색어로 필터링', async () => {
      const result = await repo.findAll({ page: 1, limit: 10, search: '유저1' })

      expect(result.data).toHaveLength(1)
      expect(result.data[0].name).toBe('유저1')
    })
  })
})
```

---

## 4. API 통합 테스트 (Supertest)

```ts
describe('Users API (Integration)', () => {
  let app: INestApplication
  let accessToken: string

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile()

    app = module.createNestApplication()
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }))
    app.useGlobalFilters(new AllExceptionsFilter())
    await app.init()

    // 테스트용 토큰 발급
    const authService = app.get(AuthService)
    const tokens = await authService.generateTokens('test-user-id')
    accessToken = tokens.accessToken
  })

  afterAll(() => app.close())

  describe('POST /users', () => {
    it('201 — 사용자 생성 성공', async () => {
      const res = await request(app.getHttpServer())
        .post('/users')
        .send({
          email: 'new@example.com',
          name: '홍길동',
          password: 'Password1!',
        })
        .expect(201)

      expect(res.body.data).toMatchObject({
        email: 'new@example.com',
        name: '홍길동',
      })
      expect(res.body.data).not.toHaveProperty('password')
      expect(res.body.data.id).toBeDefined()
    })

    it('400 — 유효성 검사 실패', async () => {
      const res = await request(app.getHttpServer())
        .post('/users')
        .send({ email: 'invalid-email', name: '홍', password: 'weak' })
        .expect(400)

      expect(res.body.error.code).toBe('VALIDATION_ERROR')
      expect(res.body.error.details).toBeInstanceOf(Array)
    })

    it('409 — 이메일 중복', async () => {
      const dto = { email: 'dup@example.com', name: '홍길동', password: 'Password1!' }
      await request(app.getHttpServer()).post('/users').send(dto).expect(201)

      const res = await request(app.getHttpServer())
        .post('/users')
        .send(dto)
        .expect(409)

      expect(res.body.error.code).toBe('DUPLICATE_EMAIL')
    })
  })

  describe('GET /users/:id', () => {
    it('401 — 인증 없이 접근', () => {
      return request(app.getHttpServer()).get('/users/some-id').expect(401)
    })

    it('404 — 존재하지 않는 사용자', () => {
      return request(app.getHttpServer())
        .get('/users/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(404)
    })
  })
})
```

---

## 5. 외부 서비스 통합 테스트 (MSW)

```ts
// MSW로 외부 API Mock
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'

const server = setupServer(
  http.post('https://api.payment-gateway.com/charge', async ({ request }) => {
    const body = await request.json() as any
    if (body.cardToken === 'invalid-token') {
      return HttpResponse.json(
        { error: 'INVALID_CARD', message: '유효하지 않은 카드' },
        { status: 400 }
      )
    }
    return HttpResponse.json({ transactionId: 'txn-123', status: 'success' })
  }),
)

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('PaymentService', () => {
  it('결제 성공 시 트랜잭션 ID 반환', async () => {
    const result = await paymentService.charge({
      amount: 10000,
      cardToken: 'valid-token',
    })
    expect(result.transactionId).toBe('txn-123')
  })

  it('잘못된 카드 토큰 → PaymentFailedException', async () => {
    await expect(
      paymentService.charge({ amount: 10000, cardToken: 'invalid-token' })
    ).rejects.toThrow(PaymentFailedException)
  })
})
```

---

## 6. 테스트 DB 관리

```ts
// 테스트 격리 전략

// 1. TRUNCATE — 빠르지만 autoincrement 리셋 안 됨
afterEach(async () => {
  await dataSource.query('TRUNCATE users, orders, order_items CASCADE')
})

// 2. Transaction Rollback — 가장 빠름
beforeEach(async () => {
  await dataSource.query('BEGIN')
})
afterEach(async () => {
  await dataSource.query('ROLLBACK')
})

// 3. 별도 스키마 — 병렬 실행 시
// 각 워커마다 별도 스키마 사용
const schema = `test_${process.env.JEST_WORKER_ID}`
await dataSource.query(`CREATE SCHEMA IF NOT EXISTS ${schema}`)
await dataSource.query(`SET search_path TO ${schema}`)
```

---

## 7. 안티패턴

- **프로덕션 DB 사용**: 반드시 별도 TEST_DATABASE_URL
- **테스트 간 데이터 공유**: afterEach 정리 필수
- **느린 외부 API 호출**: MSW 또는 Test Double 사용
- **통합 테스트로 단위 대체**: 느린 피드백 루프
- **환경별 다른 결과**: 시드 데이터, 시간 의존성 제거
