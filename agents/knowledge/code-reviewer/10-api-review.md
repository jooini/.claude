# API 설계 리뷰

> 참조 링크: https://restfulapi.net/, https://google.aip.dev/, https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design

---

## 개요

API 리뷰는 RESTful 원칙 준수, 스키마 일관성, 버저닝 전략, 하위 호환성, 에러 응답 구조를 중심으로 검토한다. API는 한번 배포하면 변경 비용이 크므로, 리뷰 시점에서 설계 결함을 잡는 것이 핵심이다.

## 1. RESTful 원칙

### 리소스 네이밍

```typescript
// ❌ 동사 기반 URL, 일관성 없음
@Get('/getUsers')
@Post('/createUser')
@Put('/updateUserInfo/:id')
@Delete('/removeUser/:id')
@Get('/getUserOrders/:userId')

// ✅ 명사 기반 리소스, 복수형, 계층 구조
@Get('/users')
@Post('/users')
@Put('/users/:id')
@Delete('/users/:id')
@Get('/users/:userId/orders')
```

### HTTP 메서드 올바른 사용

```typescript
// ❌ 모든 작업을 POST로 처리
@Post('/users/search')     // 조회인데 POST
@Post('/users/:id/delete') // 삭제인데 POST

// ✅ HTTP 메서드 의미에 맞게
@Get('/users')                      // 목록 조회
@Get('/users/:id')                  // 단건 조회
@Post('/users')                     // 생성
@Put('/users/:id')                  // 전체 수정
@Patch('/users/:id')                // 부분 수정
@Delete('/users/:id')               // 삭제
@Post('/users/search')              // 복잡한 검색 (body 필요 시 예외적 허용)
```

### 상태 코드 적절성

```typescript
// ❌ 모든 응답에 200
@Post('/users')
async createUser(@Body() dto: CreateUserDto) {
  const user = await this.userService.create(dto);
  return { status: 200, data: user }; // 생성인데 200
}

// ✅ 의미에 맞는 상태 코드
@Post('/users')
@HttpCode(HttpStatus.CREATED) // 201
async createUser(@Body() dto: CreateUserDto): Promise<UserResponseDto> {
  return this.userService.create(dto);
}

// 주요 상태 코드 가이드
// 200 OK — 조회/수정 성공
// 201 Created — 리소스 생성 성공 (Location 헤더 포함 권장)
// 204 No Content — 삭제 성공 (응답 body 없음)
// 400 Bad Request — 유효성 검증 실패
// 401 Unauthorized — 인증 필요
// 403 Forbidden — 권한 부족
// 404 Not Found — 리소스 없음
// 409 Conflict — 중복/충돌
// 422 Unprocessable Entity — 구문은 맞지만 처리 불가
// 429 Too Many Requests — 요청 제한 초과
// 500 Internal Server Error — 서버 에러
```

### RESTful 리뷰 체크리스트

- [ ] URL에 동사가 포함되어 있지 않은가?
- [ ] 리소스 이름이 복수형으로 통일되어 있는가?
- [ ] HTTP 메서드가 CRUD 의미와 일치하는가?
- [ ] 상태 코드가 응답 내용과 일치하는가?
- [ ] 중첩 리소스 깊이가 3단계를 넘지 않는가?

## 2. 스키마 일관성

### 요청/응답 DTO 설계

```typescript
// ❌ 일관성 없는 응답 구조
// GET /users/:id → { id, name, email }
// GET /users → [{ user_id, userName, mail }]  // 필드명 불일치

// ✅ 일관된 응답 구조
interface ApiResponse<T> {
  data: T;
  meta?: PaginationMeta;
}

interface UserResponseDto {
  id: string;
  name: string;
  email: string;
  createdAt: string; // ISO 8601
}

// GET /users/:id → { data: UserResponseDto }
// GET /users → { data: UserResponseDto[], meta: { total, page, limit } }
```

### 네이밍 컨벤션 통일

```typescript
// ❌ 혼재된 네이밍
interface UserResponse {
  user_id: string;       // snake_case
  userName: string;      // camelCase
  'email-address': string; // kebab-case
  CreatedAt: string;     // PascalCase
}

// ✅ camelCase 통일 (JSON 응답)
interface UserResponse {
  userId: string;
  userName: string;
  emailAddress: string;
  createdAt: string;
}
```

### 스키마 체크리스트

- [ ] 요청/응답 DTO가 명시적으로 정의되어 있는가?
- [ ] 날짜 형식이 ISO 8601로 통일되어 있는가?
- [ ] null과 undefined의 의미가 구분되어 있는가?
- [ ] 페이지네이션 응답 구조가 전체 API에서 동일한가?
- [ ] 필드명 컨벤션(camelCase)이 통일되어 있는가?

## 3. 버저닝

### 버저닝 전략

```typescript
// 방법 1: URL 경로 버저닝 (가장 명시적)
@Controller('v1/users')
class UserControllerV1 { /* ... */ }

@Controller('v2/users')
class UserControllerV2 { /* ... */ }

// 방법 2: NestJS 내장 버저닝
@Controller('users')
class UserController {
  @Version('1')
  @Get(':id')
  getUserV1(@Param('id') id: string): Promise<UserV1ResponseDto> { /* ... */ }

  @Version('2')
  @Get(':id')
  getUserV2(@Param('id') id: string): Promise<UserV2ResponseDto> { /* ... */ }
}

// 방법 3: Header 버저닝
// Accept: application/vnd.myapp.v2+json
```

### 버저닝 체크리스트

- [ ] 버저닝 전략이 프로젝트 내에서 통일되어 있는가?
- [ ] 새 버전 도입 시 이전 버전의 지원 종료 계획이 있는가?
- [ ] 버전 간 응답 구조 변환 로직이 격리되어 있는가?

## 4. 하위 호환성

### Breaking Change 식별

```typescript
// ❌ Breaking Changes (기존 클라이언트 깨짐)
// 1. 필수 필드 추가
interface CreateUserDtoV1 { name: string; email: string; }
interface CreateUserDtoV2 { name: string; email: string; phone: string; } // phone 필수 추가

// 2. 필드 제거
interface UserResponseV1 { id: string; name: string; email: string; }
interface UserResponseV2 { id: string; name: string; } // email 제거

// 3. 필드 타입 변경
interface UserResponseV1 { id: number; }  // number
interface UserResponseV2 { id: string; }  // string으로 변경

// 4. URL 변경
// /users/:id → /members/:id

// ✅ 하위 호환 유지하는 변경
// 1. 선택적 필드 추가
interface CreateUserDtoV2 { name: string; email: string; phone?: string; } // optional

// 2. 기존 필드 유지 + 새 필드 추가
interface UserResponseV2 { id: string; name: string; email: string; avatarUrl?: string; }

// 3. 새 엔드포인트 추가 (기존 유지)
@Get('/users/:id')        // 기존 유지
@Get('/users/:id/detail') // 새로 추가
```

### 하위 호환성 체크리스트

- [ ] 기존 필수 필드를 제거하거나 이름을 변경하지 않았는가?
- [ ] 새 필수 필드를 추가하지 않았는가? (optional로 추가)
- [ ] 기존 엔드포인트 URL이 변경되지 않았는가?
- [ ] 응답 필드의 타입이 변경되지 않았는가?
- [ ] enum에 새 값 추가 시 클라이언트 side에서 안전한가?

## 5. 에러 응답

### 표준화된 에러 구조

```typescript
// ❌ 일관성 없는 에러 응답
// 케이스 1: { error: "Not found" }
// 케이스 2: { message: "Validation failed", errors: [...] }
// 케이스 3: { success: false, msg: "Server error" }

// ✅ 통일된 에러 응답 포맷
interface ErrorResponse {
  error: {
    code: string;          // 머신 리더블 (예: USER_NOT_FOUND)
    message: string;       // 사람 읽기용
    details?: ErrorDetail[]; // 유효성 검증 등 상세 정보
    traceId?: string;      // 디버깅용 추적 ID
  };
}

interface ErrorDetail {
  field: string;
  message: string;
  code: string;
}

// 사용 예시
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "입력 데이터가 유효하지 않습니다.",
    "details": [
      { "field": "email", "message": "유효한 이메일 형식이 아닙니다.", "code": "INVALID_FORMAT" },
      { "field": "name", "message": "이름은 필수입니다.", "code": "REQUIRED" }
    ],
    "traceId": "abc-123-def"
  }
}
```

### 에러 응답 체크리스트

- [ ] 에러 응답 구조가 전체 API에서 통일되어 있는가?
- [ ] 에러 코드가 머신 리더블(상수)인가?
- [ ] 유효성 검증 에러에 필드별 상세 정보가 포함되는가?
- [ ] 500 에러에서 내부 구현(스택 트레이스 등)이 노출되지 않는가?
- [ ] 에러 메시지에 민감 정보(DB 쿼리, 파일 경로)가 포함되지 않는가?

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| 내부 정보 노출 | 에러에 스택 트레이스/쿼리 노출 | P0 |
| Breaking Change | 기존 클라이언트 호환성 파괴 | P0 |
| 상태 코드 오용 | 의미와 불일치하는 상태 코드 | P1 |
| 스키마 불일치 | 엔드포인트별 응답 구조 상이 | P1 |
| 에러 포맷 불일치 | 엔드포인트별 에러 구조 상이 | P2 |
| 네이밍 불일치 | camelCase/snake_case 혼용 | P2 |
| 버저닝 미적용 | Breaking Change 시 버전 미분리 | P1 |
