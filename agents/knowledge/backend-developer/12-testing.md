# Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/testing

---

## 1. 테스트 전략

```
Unit Test       빠름, 격리, 로직 검증
Integration     DB/외부 서비스 포함, 슬로우
E2E             실제 HTTP 요청, 가장 느림

권장 비율: Unit 70% / Integration 20% / E2E 10%
```

NestJS 기본 제공: Jest + `@nestjs/testing`

---

## 2. Unit Test — Service

```ts
// users.service.spec.ts
describe('UsersService', () => {
  let service: UsersService
  let repo: jest.Mocked<UsersRepository>
  let mailer: jest.Mocked<MailerService>

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        UsersService,
        {
          provide: UsersRepository,
          useValue: {
            findById: jest.fn(),
            findByEmail: jest.fn(),
            create: jest.fn(),
            update: jest.fn(),
            delete: jest.fn(),
          },
        },
        {
          provide: MailerService,
          useValue: { sendWelcome: jest.fn() },
        },
      ],
    }).compile()

    service = module.get(UsersService)
    repo = module.get(UsersRepository)
    mailer = module.get(MailerService)
  })

  describe('create', () => {
    it('이메일 중복 시 ConflictException', async () => {
      repo.findByEmail.mockResolvedValue({ id: '1', email: 'test@test.com' } as User)

      await expect(
        service.create({ email: 'test@test.com', name: '홍길동', password: 'pw' }),
      ).rejects.toThrow(ConflictException)
    })

    it('사용자 생성 후 환영 이메일 발송', async () => {
      repo.findByEmail.mockResolvedValue(null)
      repo.create.mockResolvedValue({ id: '1', email: 'new@test.com', name: '홍길동' } as User)

      await service.create({ email: 'new@test.com', name: '홍길동', password: 'password123' })

      expect(repo.create).toHaveBeenCalledTimes(1)
      expect(mailer.sendWelcome).toHaveBeenCalledWith('new@test.com')
    })
  })

  describe('findOneOrFail', () => {
    it('존재하지 않는 ID → NotFoundException', async () => {
      repo.findById.mockResolvedValue(null)

      await expect(service.findOneOrFail('non-existent')).rejects.toThrow(NotFoundException)
    })
  })
})
```

---

## 3. Unit Test — Controller

```ts
describe('UsersController', () => {
  let controller: UsersController
  let service: jest.Mocked<UsersService>

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [UsersController],
      providers: [
        {
          provide: UsersService,
          useValue: {
            findAll: jest.fn(),
            findOneOrFail: jest.fn(),
            create: jest.fn(),
            update: jest.fn(),
            remove: jest.fn(),
          },
        },
      ],
    }).compile()

    controller = module.get(UsersController)
    service = module.get(UsersService)
  })

  it('findAll — service 결과를 그대로 반환', async () => {
    const expected = { data: [], meta: { total: 0 } }
    service.findAll.mockResolvedValue(expected as any)

    const result = await controller.findAll({ page: 1, limit: 20 } as any)

    expect(result).toBe(expected)
    expect(service.findAll).toHaveBeenCalledWith({ page: 1, limit: 20 })
  })
})
```

---

## 4. Integration Test — Repository

```ts
// TypeORM 테스트 DB 사용
describe('UsersRepository (integration)', () => {
  let app: INestApplication
  let repo: UsersRepository
  let dataSource: DataSource

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [
        TypeOrmModule.forRoot({
          type: 'postgres',
          url: process.env.TEST_DATABASE_URL,
          entities: [UserEntity],
          synchronize: true,  // 테스트에서만
        }),
        TypeOrmModule.forFeature([UserEntity]),
      ],
      providers: [UsersRepository],
    }).compile()

    repo = module.get(UsersRepository)
    dataSource = module.get(DataSource)
  })

  afterEach(async () => {
    await dataSource.query('TRUNCATE users CASCADE')
  })

  afterAll(async () => {
    await dataSource.destroy()
  })

  it('사용자 생성 및 조회', async () => {
    const created = await repo.create({
      email: 'test@example.com',
      name: '홍길동',
      password: 'hashed',
    })

    expect(created.id).toBeDefined()

    const found = await repo.findById(created.id)
    expect(found?.email).toBe('test@example.com')
  })

  it('이메일 중복 생성 → 에러', async () => {
    await repo.create({ email: 'dup@example.com', name: 'A', password: 'pw' })
    await expect(
      repo.create({ email: 'dup@example.com', name: 'B', password: 'pw' }),
    ).rejects.toThrow()
  })
})
```

---

## 5. E2E Test

```ts
// test/users.e2e-spec.ts
describe('Users E2E', () => {
  let app: INestApplication

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile()

    app = module.createNestApplication()
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }))
    app.useGlobalFilters(new AllExceptionsFilter())
    await app.init()
  })

  afterAll(() => app.close())

  describe('POST /users', () => {
    it('201 — 사용자 생성', async () => {
      const res = await request(app.getHttpServer())
        .post('/users')
        .send({ email: 'test@example.com', name: '홍길동', password: 'password123' })
        .expect(201)

      expect(res.body.data).toMatchObject({
        email: 'test@example.com',
        name: '홍길동',
      })
      expect(res.body.data.password).toBeUndefined()  // 패스워드 미노출
    })

    it('400 — 유효하지 않은 이메일', async () => {
      const res = await request(app.getHttpServer())
        .post('/users')
        .send({ email: 'invalid', name: '홍길동', password: 'password123' })
        .expect(400)

      expect(res.body.error.code).toBe('VALIDATION_ERROR')
    })

    it('409 — 이메일 중복', async () => {
      const dto = { email: 'dup@example.com', name: '홍길동', password: 'password123' }
      await request(app.getHttpServer()).post('/users').send(dto).expect(201)
      await request(app.getHttpServer()).post('/users').send(dto).expect(409)
    })
  })

  describe('GET /users/:id', () => {
    it('401 — 인증 없음', () => {
      return request(app.getHttpServer()).get('/users/some-id').expect(401)
    })
  })
})
```

---

## 6. 테스트 유틸리티

```ts
// test/helpers/create-test-user.ts
export async function createTestUser(
  dataSource: DataSource,
  override: Partial<UserEntity> = {},
): Promise<UserEntity> {
  return dataSource.getRepository(UserEntity).save({
    email: `test-${Date.now()}@example.com`,
    name: '테스트 유저',
    password: await bcrypt.hash('password123', 10),
    status: 'active',
    ...override,
  })
}

// test/helpers/get-auth-token.ts
export async function getAuthToken(app: INestApplication, userId: string): Promise<string> {
  const authService = app.get(AuthService)
  const { accessToken } = await authService.generateTokens(userId)
  return accessToken
}
```

---

## 7. 안티패턴

- **프로덕션 DB로 테스트**: 별도 TEST_DATABASE_URL 사용
- **테스트 간 상태 공유**: afterEach에서 TRUNCATE 또는 롤백
- **Mock 과도 사용**: Integration 테스트에서 실제 DB 사용이 더 신뢰성 높음
- **E2E 테스트로 유닛 대체**: 느리고 디버깅 어려움
- **테스트 없는 예외 케이스**: 에러 경로도 반드시 테스트
