# API Design

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/api-design

---

## 1. REST API 설계 원칙

### 리소스 중심 URL

```
# ✅ 리소스(명사) 기반
GET    /users              # 목록 조회
GET    /users/:id          # 단건 조회
POST   /users              # 생성
PATCH  /users/:id          # 부분 수정
PUT    /users/:id          # 전체 교체
DELETE /users/:id          # 삭제

# 중첩 리소스
GET    /users/:id/posts    # 특정 유저의 게시물
POST   /users/:id/posts

# ❌ 동사 기반 (RPC 스타일)
POST   /getUser
POST   /createUser
POST   /deleteUser
```

### HTTP 메서드 의미

| 메서드 | 의미 | 멱등성 | 안전성 |
|--------|------|--------|--------|
| GET | 조회 | ✅ | ✅ |
| POST | 생성 | ❌ | ❌ |
| PUT | 전체 수정 | ✅ | ❌ |
| PATCH | 부분 수정 | ❌ | ❌ |
| DELETE | 삭제 | ✅ | ❌ |

---

## 2. HTTP 상태 코드

```
2xx 성공
  200 OK              — 일반 성공
  201 Created         — 리소스 생성 성공 (POST)
  204 No Content      — 성공, 응답 본문 없음 (DELETE)

3xx 리다이렉션
  301 Moved Permanently
  304 Not Modified    — 캐시 유효

4xx 클라이언트 에러
  400 Bad Request     — 잘못된 요청 (유효성 실패)
  401 Unauthorized    — 인증 필요
  403 Forbidden       — 권한 없음 (인증은 됐지만)
  404 Not Found       — 리소스 없음
  409 Conflict        — 충돌 (중복 이메일 등)
  422 Unprocessable   — 유효성 에러 상세
  429 Too Many Requests — 레이트 리밋

5xx 서버 에러
  500 Internal Server Error
  502 Bad Gateway
  503 Service Unavailable
```

---

## 3. 응답 형식 표준화

```ts
// 성공 응답
{
  "data": { ... },           // 단건
  "data": [ ... ],           // 목록
  "meta": {                  // 페이지네이션
    "total": 100,
    "page": 1,
    "limit": 20,
    "totalPages": 5
  }
}

// 에러 응답
{
  "error": {
    "code": "USER_NOT_FOUND",   // 클라이언트가 처리할 에러 코드
    "message": "사용자를 찾을 수 없습니다",
    "details": [               // 유효성 에러 상세 (선택)
      { "field": "email", "message": "이미 사용 중인 이메일" }
    ]
  }
}
```

```ts
// NestJS 응답 인터셉터
@Injectable()
export class ResponseInterceptor<T> implements NestInterceptor<T, ApiResponse<T>> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<ApiResponse<T>> {
    return next.handle().pipe(
      map(data => ({
        data,
        timestamp: new Date().toISOString(),
      }))
    )
  }
}
```

---

## 4. 페이지네이션

```ts
// Cursor 기반 (대용량, 실시간 데이터 권장)
GET /posts?cursor=eyJpZCI6MTAwfQ==&limit=20

// 응답
{
  "data": [...],
  "meta": {
    "nextCursor": "eyJpZCI6ODB9",
    "hasNextPage": true
  }
}

// Offset 기반 (관리자 페이지 등 페이지 이동 필요 시)
GET /posts?page=2&limit=20

// 응답
{
  "data": [...],
  "meta": { "total": 200, "page": 2, "limit": 20, "totalPages": 10 }
}
```

---

## 5. 필터링 & 정렬

```
GET /users?status=active&role=admin
GET /users?sort=createdAt:desc,name:asc
GET /users?fields=id,name,email          # 필드 선택 (Sparse Fieldsets)
GET /users?search=홍길동                  # 검색
```

```ts
// NestJS DTO
export class GetUsersDto {
  @IsOptional()
  @IsEnum(UserStatus)
  status?: UserStatus

  @IsOptional()
  @IsString()
  search?: string

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20
}
```

---

## 6. 버전 관리

```
# URL 버전 (가장 명시적, 권장)
/api/v1/users
/api/v2/users

# 헤더 버전
Accept: application/vnd.myapi.v2+json

# 쿼리 파라미터 (비권장)
/users?version=2
```

```ts
// NestJS 버전 관리
// main.ts
app.enableVersioning({ type: VersioningType.URI })

// 컨트롤러
@Controller({ version: '1', path: 'users' })
export class UsersV1Controller { ... }

@Controller({ version: '2', path: 'users' })
export class UsersV2Controller { ... }
```

---

## 7. API 문서화 (Swagger)

```ts
// NestJS Swagger
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger'

@ApiTags('users')
@ApiBearerAuth()
@Controller('users')
export class UsersController {
  @Get(':id')
  @ApiOperation({ summary: '사용자 조회' })
  @ApiResponse({ status: 200, type: UserResponseDto })
  @ApiResponse({ status: 404, description: '사용자 없음' })
  findOne(@Param('id') id: string) { ... }
}

// DTO에 Swagger 데코레이터
export class CreateUserDto {
  @ApiProperty({ example: 'hong@example.com', description: '이메일' })
  @IsEmail()
  email: string

  @ApiProperty({ example: '홍길동', minLength: 2 })
  @IsString()
  name: string
}
```

---

## 8. 안티패턴

- **동사 URL**: `/getUser`, `/deletePost` → 명사 + HTTP 메서드
- **200으로 에러 반환**: `{ success: false }` → 적절한 4xx/5xx
- **일관성 없는 응답 형식**: 엔드포인트마다 다른 구조
- **페이지네이션 없는 목록 API**: 데이터 증가 시 성능 폭탄
- **에러 코드 없는 에러 응답**: 메시지만으로는 클라이언트 처리 어려움
