# Architecture

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/architecture

---

## 1. NestJS 레이어드 아키텍처

```
HTTP Request
    ↓
Controller     (요청/응답 처리, DTO 변환)
    ↓
Service        (비즈니스 로직)
    ↓
Repository     (데이터 접근)
    ↓
Database
```

```
src/
  modules/
    users/
      users.controller.ts    # HTTP 레이어
      users.service.ts       # 비즈니스 로직
      users.repository.ts    # 데이터 접근
      users.module.ts        # 모듈 정의
      dto/
        create-user.dto.ts
        update-user.dto.ts
        user-response.dto.ts
      entities/
        user.entity.ts
  common/
    filters/                 # 예외 필터
    guards/                  # 인증/권한 가드
    interceptors/            # 응답 변환
    decorators/              # 커스텀 데코레이터
    pipes/                   # 입력 변환/검증
```

---

## 2. 모듈 설계

```ts
// users.module.ts
@Module({
  imports: [
    TypeOrmModule.forFeature([User]),  // 엔티티 등록
    AuthModule,                         // 의존 모듈
  ],
  controllers: [UsersController],
  providers: [UsersService, UsersRepository],
  exports: [UsersService],             // 다른 모듈에서 사용 가능하게
})
export class UsersModule {}

// app.module.ts — root 모듈
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRootAsync({ ... }),
    UsersModule,
    AuthModule,
    PostsModule,
  ],
})
export class AppModule {}
```

---

## 3. Controller

```ts
@ApiTags('users')
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  @UseGuards(JwtAuthGuard)
  findAll(@Query() query: GetUsersDto): Promise<PaginatedResult<UserResponseDto>> {
    return this.usersService.findAll(query)
  }

  @Get(':id')
  async findOne(@Param('id', ParseUUIDPipe) id: string): Promise<UserResponseDto> {
    return this.usersService.findOneOrFail(id)
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: CreateUserDto): Promise<UserResponseDto> {
    return this.usersService.create(dto)
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, UserOwnerGuard)
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateUserDto,
  ): Promise<UserResponseDto> {
    return this.usersService.update(id, dto)
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(JwtAuthGuard, UserOwnerGuard)
  remove(@Param('id', ParseUUIDPipe) id: string): Promise<void> {
    return this.usersService.remove(id)
  }
}
```

**컨트롤러 원칙:**
- HTTP 변환만 담당 (DTO 파싱, 상태 코드)
- 비즈니스 로직 없음
- Service 호출 후 결과 반환

---

## 4. Service

```ts
@Injectable()
export class UsersService {
  constructor(
    private readonly usersRepository: UsersRepository,
    private readonly mailerService: MailerService,
  ) {}

  async create(dto: CreateUserDto): Promise<UserResponseDto> {
    // 비즈니스 규칙 검증
    const exists = await this.usersRepository.existsByEmail(dto.email)
    if (exists) throw new ConflictException('이미 사용 중인 이메일')

    const hashedPassword = await bcrypt.hash(dto.password, 10)
    const user = await this.usersRepository.create({
      ...dto,
      password: hashedPassword,
    })

    // 사이드 이펙트 (이메일 발송 등)
    await this.mailerService.sendWelcome(user.email)

    return UserResponseDto.from(user)
  }

  async findOneOrFail(id: string): Promise<UserResponseDto> {
    const user = await this.usersRepository.findById(id)
    if (!user) throw new NotFoundException('사용자를 찾을 수 없습니다')
    return UserResponseDto.from(user)
  }
}
```

---

## 5. Repository

```ts
@Injectable()
export class UsersRepository {
  constructor(
    @InjectRepository(User)
    private readonly repo: Repository<User>,
  ) {}

  async findById(id: string): Promise<User | null> {
    return this.repo.findOne({ where: { id } })
  }

  async existsByEmail(email: string): Promise<boolean> {
    return this.repo.exists({ where: { email } })
  }

  async create(data: Partial<User>): Promise<User> {
    const user = this.repo.create(data)
    return this.repo.save(user)
  }

  async findAll(query: GetUsersDto): Promise<[User[], number]> {
    const qb = this.repo.createQueryBuilder('user')

    if (query.search) {
      qb.where('user.name ILIKE :search', { search: `%${query.search}%` })
    }
    if (query.status) {
      qb.andWhere('user.status = :status', { status: query.status })
    }

    return qb
      .orderBy('user.createdAt', 'DESC')
      .skip((query.page - 1) * query.limit)
      .take(query.limit)
      .getManyAndCount()
  }
}
```

---

## 6. 예외 처리

```ts
// common/filters/http-exception.filter.ts
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp()
    const res = ctx.getResponse<Response>()

    let status = HttpStatus.INTERNAL_SERVER_ERROR
    let message = '서버 오류가 발생했습니다'
    let code = 'INTERNAL_ERROR'

    if (exception instanceof HttpException) {
      status = exception.getStatus()
      const body = exception.getResponse()
      message = typeof body === 'string' ? body : (body as any).message
      code = (body as any).error ?? exception.constructor.name
    }

    // 운영에서는 5xx 에러 상세 숨기기
    if (status >= 500 && process.env.NODE_ENV === 'production') {
      logger.error(exception)
      message = '서버 오류가 발생했습니다'
    }

    res.status(status).json({
      error: { code, message },
      timestamp: new Date().toISOString(),
    })
  }
}
```

---

## 7. 안티패턴

- **Controller에 비즈니스 로직**: Service로 이동
- **Service에서 직접 TypeORM repo 사용**: Repository 레이어 분리
- **순환 의존**: A모듈 ↔ B모듈 직접 참조 → 공통 모듈로 분리
- **God Service**: 모든 것을 하는 서비스 → 도메인별 분리
- **DTO 없이 엔티티 직접 노출**: 패스워드 등 민감 정보 유출 위험
