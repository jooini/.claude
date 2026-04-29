# Security

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/security

---

## 1. 인증 (Authentication)

### JWT + Refresh Token

```ts
// auth.service.ts
@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly usersService: UsersService,
    @InjectRedis() private readonly redis: Redis,
  ) {}

  async login(email: string, password: string) {
    const user = await this.usersService.findByEmail(email)
    if (!user) throw new UnauthorizedException()

    const isValid = await bcrypt.compare(password, user.password)
    if (!isValid) throw new UnauthorizedException()

    return this.generateTokens(user.id)
  }

  async generateTokens(userId: string) {
    const [accessToken, refreshToken] = await Promise.all([
      this.jwtService.signAsync(
        { sub: userId },
        { expiresIn: '15m', secret: process.env.JWT_ACCESS_SECRET },
      ),
      this.jwtService.signAsync(
        { sub: userId },
        { expiresIn: '7d', secret: process.env.JWT_REFRESH_SECRET },
      ),
    ])

    // Refresh Token은 Redis에 저장 (revocation 가능)
    await this.redis.setex(`refresh:${userId}`, 60 * 60 * 24 * 7, refreshToken)

    return { accessToken, refreshToken }
  }

  async refresh(refreshToken: string) {
    const payload = await this.jwtService.verifyAsync(refreshToken, {
      secret: process.env.JWT_REFRESH_SECRET,
    })

    // Redis에서 유효성 확인
    const stored = await this.redis.get(`refresh:${payload.sub}`)
    if (stored !== refreshToken) throw new UnauthorizedException('Invalid refresh token')

    return this.generateTokens(payload.sub)
  }

  async logout(userId: string) {
    await this.redis.del(`refresh:${userId}`)
  }
}
```

### JWT Guard

```ts
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  handleRequest(err: unknown, user: unknown) {
    if (err || !user) throw new UnauthorizedException()
    return user
  }
}

// JWT Strategy
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: config.get('JWT_ACCESS_SECRET'),
    })
  }

  async validate(payload: { sub: string }) {
    return { id: payload.sub }  // request.user에 주입
  }
}
```

---

## 2. 인가 (Authorization)

### RBAC (Role-Based Access Control)

```ts
// 역할 정의
export enum Role {
  USER = 'user',
  ADMIN = 'admin',
  SUPER_ADMIN = 'super_admin',
}

// 역할 데코레이터
export const Roles = (...roles: Role[]) => SetMetadata('roles', roles)

// 역할 가드
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>('roles', [
      context.getHandler(),
      context.getClass(),
    ])
    if (!requiredRoles) return true  // 역할 제한 없음

    const { user } = context.switchToHttp().getRequest()
    return requiredRoles.some(role => user.roles?.includes(role))
  }
}

// 사용
@Delete(':id')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)
remove(@Param('id') id: string) {
  return this.usersService.remove(id)
}
```

### 리소스 소유권 검사

```ts
@Injectable()
export class ResourceOwnerGuard implements CanActivate {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest()
    const userId = request.user.id
    const resourceId = request.params.id

    const resource = await this.resourceService.findById(resourceId)
    if (!resource) throw new NotFoundException()

    // 소유자이거나 관리자인 경우 허용
    return resource.userId === userId || request.user.roles.includes(Role.ADMIN)
  }
}
```

---

## 3. 입력 검증

```ts
// main.ts — 전역 ValidationPipe
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,            // DTO에 없는 필드 자동 제거
    forbidNonWhitelisted: true, // 없는 필드 있으면 400 에러
    transform: true,            // 타입 자동 변환 (string → number)
    transformOptions: { enableImplicitConversion: true },
  })
)

// DTO 검증
import { IsEmail, IsString, MinLength, IsEnum, IsOptional } from 'class-validator'
import { Transform } from 'class-transformer'

export class CreateUserDto {
  @IsEmail({}, { message: '유효한 이메일을 입력하세요' })
  @Transform(({ value }) => value.toLowerCase().trim())
  email: string

  @IsString()
  @MinLength(8, { message: '비밀번호는 8자 이상이어야 합니다' })
  password: string

  @IsString()
  @MinLength(2)
  @MaxLength(50)
  name: string

  @IsOptional()
  @IsEnum(Role)
  role?: Role
}
```

---

## 4. SQL Injection 방어

```ts
// TypeORM — 파라미터 바인딩 (자동 방어)
// ✅ 안전
await userRepo
  .createQueryBuilder('user')
  .where('user.email = :email', { email })  // 파라미터 바인딩
  .getOne()

// ❌ 위험 — 문자열 보간
await userRepo
  .createQueryBuilder('user')
  .where(`user.email = '${email}'`)  // SQL Injection 가능

// Raw query 사용 시
await dataSource.query(
  'SELECT * FROM users WHERE email = $1',
  [email]  // 반드시 파라미터 배열 사용
)
```

---

## 5. Rate Limiting

```ts
// NestJS Throttler
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler'

ThrottlerModule.forRoot([
  { name: 'short', ttl: 1000, limit: 10 },    // 1초에 10번
  { name: 'long', ttl: 60000, limit: 100 },   // 1분에 100번
])

// 전역 적용
app.useGlobalGuards(new ThrottlerGuard())

// 특정 엔드포인트 설정
@Post('login')
@Throttle({ short: { ttl: 60000, limit: 5 } })  // 로그인은 1분에 5번
login(@Body() dto: LoginDto) { ... }

// 특정 엔드포인트 제외
@Get('health')
@SkipThrottle()
health() { return 'ok' }
```

---

## 6. 보안 헤더

```ts
// main.ts
import helmet from 'helmet'

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
    },
  },
  hsts: { maxAge: 31536000, includeSubDomains: true },
}))

// CORS
app.enableCors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') ?? [],
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
  credentials: true,
})
```

---

## 7. 민감 정보 보호

```ts
// 응답 DTO에서 패스워드 제외
export class UserResponseDto {
  id: string
  email: string
  name: string
  // password 없음

  static from(user: User): UserResponseDto {
    const dto = new UserResponseDto()
    dto.id = user.id
    dto.email = user.email
    dto.name = user.name
    return dto
  }
}

// class-transformer @Exclude
import { Exclude, Expose } from 'class-transformer'

export class UserResponseDto {
  @Expose() id: string
  @Expose() email: string
  @Expose() name: string
  @Exclude() password: string  // 응답에서 자동 제외
}
```

---

## 8. 안티패턴

- **JWT Secret 하드코딩**: 환경 변수로 관리
- **비밀번호 평문 저장**: bcrypt (cost factor 12 이상)
- **Access Token 장기 만료**: 15분~1시간, Refresh Token으로 갱신
- **에러 메시지 과노출**: DB 에러, 스택 트레이스 클라이언트 전송 금지
- **인증 없는 관리자 API**: 모든 민감 엔드포인트에 Guard 필수
