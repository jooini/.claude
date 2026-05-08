# Error Handling

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/error-handling

---

## 1. 예외 계층 설계

```ts
// 커스텀 예외 기반 클래스
export class AppException extends HttpException {
  constructor(
    public readonly code: string,
    message: string,
    status: HttpStatus,
    public readonly details?: unknown,
  ) {
    super({ code, message, details }, status)
  }
}

// 도메인별 예외
export class UserNotFoundException extends AppException {
  constructor(id?: string) {
    super(
      'USER_NOT_FOUND',
      id ? `사용자(${id})를 찾을 수 없습니다` : '사용자를 찾을 수 없습니다',
      HttpStatus.NOT_FOUND,
    )
  }
}

export class DuplicateEmailException extends AppException {
  constructor(email: string) {
    super('DUPLICATE_EMAIL', `이미 사용 중인 이메일: ${email}`, HttpStatus.CONFLICT)
  }
}

export class InsufficientStockException extends AppException {
  constructor(productId: string, requested: number, available: number) {
    super('INSUFFICIENT_STOCK', '재고가 부족합니다', HttpStatus.UNPROCESSABLE_ENTITY, {
      productId,
      requested,
      available,
    })
  }
}

// 도메인 예외 (인프라 무관)
export class DomainException extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'DomainException'
  }
}
```

---

## 2. 전역 예외 필터

```ts
// common/filters/all-exceptions.filter.ts
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name)

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp()
    const request = ctx.getRequest<Request>()
    const response = ctx.getResponse<Response>()

    const { status, body } = this.resolveException(exception)

    // 5xx는 서버 로그에 기록
    if (status >= 500) {
      this.logger.error(
        `${request.method} ${request.url} → ${status}`,
        exception instanceof Error ? exception.stack : String(exception),
      )
    }

    response.status(status).json({
      error: body,
      timestamp: new Date().toISOString(),
      path: request.url,
    })
  }

  private resolveException(exception: unknown): { status: number; body: object } {
    // NestJS HttpException
    if (exception instanceof HttpException) {
      const status = exception.getStatus()
      const res = exception.getResponse()
      return {
        status,
        body: {
          code: (res as any).code ?? exception.constructor.name,
          message:
            typeof res === 'string' ? res : (res as any).message ?? 'Unknown error',
          details: (res as any).details,
        },
      }
    }

    // 도메인 예외 → 400
    if (exception instanceof DomainException) {
      return {
        status: HttpStatus.BAD_REQUEST,
        body: { code: 'DOMAIN_ERROR', message: exception.message },
      }
    }

    // TypeORM 에러
    if (exception instanceof QueryFailedError) {
      if ((exception as any).code === '23505') {  // unique violation
        return {
          status: HttpStatus.CONFLICT,
          body: { code: 'DUPLICATE_ENTRY', message: '중복된 데이터가 존재합니다' },
        }
      }
    }

    // 알 수 없는 에러 → 500
    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      body: {
        code: 'INTERNAL_ERROR',
        message:
          process.env.NODE_ENV === 'production'
            ? '서버 오류가 발생했습니다'
            : (exception as Error).message,
      },
    }
  }
}

// main.ts 등록
app.useGlobalFilters(new AllExceptionsFilter())
```

---

## 3. 유효성 검증 에러 포맷

```ts
// ValidationPipe 에러를 일관된 형식으로 변환
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,
    transform: true,
    exceptionFactory: (errors) => {
      const details = errors.map(err => ({
        field: err.property,
        messages: Object.values(err.constraints ?? {}),
      }))
      return new AppException(
        'VALIDATION_ERROR',
        '입력 값이 올바르지 않습니다',
        HttpStatus.BAD_REQUEST,
        details,
      )
    },
  }),
)

// 에러 응답 예시
// {
//   "error": {
//     "code": "VALIDATION_ERROR",
//     "message": "입력 값이 올바르지 않습니다",
//     "details": [
//       { "field": "email", "messages": ["유효한 이메일을 입력하세요"] },
//       { "field": "password", "messages": ["비밀번호는 8자 이상이어야 합니다"] }
//     ]
//   }
// }
```

---

## 4. 비동기 에러 처리

```ts
// async/await 에러는 NestJS가 자동으로 처리
@Get(':id')
async findOne(@Param('id') id: string) {
  // throw가 발생하면 필터가 자동으로 캐치
  return this.usersService.findOneOrFail(id)
}

// Promise 체인에서 명시적 처리
@Post()
async create(@Body() dto: CreateUserDto) {
  return this.usersService
    .create(dto)
    .catch(err => {
      if (err instanceof DuplicateEmailException) throw err
      throw new InternalServerErrorException()
    })
}
```

---

## 5. 에러 코드 카탈로그

```ts
// common/errors/error-codes.ts
export const ErrorCodes = {
  // 공통
  VALIDATION_ERROR:   'VALIDATION_ERROR',
  UNAUTHORIZED:       'UNAUTHORIZED',
  FORBIDDEN:          'FORBIDDEN',
  NOT_FOUND:          'NOT_FOUND',
  INTERNAL_ERROR:     'INTERNAL_ERROR',
  RATE_LIMIT_EXCEEDED:'RATE_LIMIT_EXCEEDED',

  // 사용자
  USER_NOT_FOUND:     'USER_NOT_FOUND',
  DUPLICATE_EMAIL:    'DUPLICATE_EMAIL',
  INVALID_PASSWORD:   'INVALID_PASSWORD',
  USER_BANNED:        'USER_BANNED',

  // 주문
  ORDER_NOT_FOUND:    'ORDER_NOT_FOUND',
  INSUFFICIENT_STOCK: 'INSUFFICIENT_STOCK',
  ORDER_ALREADY_PAID: 'ORDER_ALREADY_PAID',

  // 결제
  PAYMENT_FAILED:     'PAYMENT_FAILED',
  INVALID_CARD:       'INVALID_CARD',
} as const

export type ErrorCode = typeof ErrorCodes[keyof typeof ErrorCodes]
```

---

## 6. 에러 로깅 & 알림

```ts
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const status = this.getStatus(exception)

    if (status >= 500) {
      // Sentry로 전송
      Sentry.withScope(scope => {
        const request = host.switchToHttp().getRequest<Request>()
        scope.setTag('url', request.url)
        scope.setTag('method', request.method)
        scope.setUser({ id: request.user?.id })
        Sentry.captureException(exception)
      })
    }
  }
}
```

---

## 7. 안티패턴

- **빈 catch 블록**: 에러를 삼키면 디버깅 불가
- **모든 에러에 500**: 클라이언트 에러(4xx)와 서버 에러(5xx) 구분
- **에러 코드 없이 메시지만**: 클라이언트가 programmatic 처리 불가
- **스택 트레이스 운영 노출**: `NODE_ENV === 'production'`에서 숨기기
- **도메인 로직에 HttpException**: 도메인은 인프라(HTTP) 모름 → DomainException
