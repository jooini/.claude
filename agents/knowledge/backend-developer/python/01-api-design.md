# API Design

> Python/FastAPI 버전 — 원본: API Design

---

## 1. REST API 설계 원칙

### 리소스 중심 URL

```
# ✅ 리소스(명사) 기반
GET    /users              # 목록 조회
GET    /users/{id}         # 단건 조회
POST   /users              # 생성
PATCH  /users/{id}         # 부분 수정
PUT    /users/{id}         # 전체 교체
DELETE /users/{id}         # 삭제

# 중첩 리소스
GET    /users/{id}/posts   # 특정 유저의 게시물
POST   /users/{id}/posts

# ❌ 동사 기반 (RPC 스타일)
POST   /getUser
POST   /createUser
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
  429 Too Many Requests — Rate limit 초과

5xx 서버 에러
  500 Internal Server Error
  502 Bad Gateway     — 업스트림 서버 오류
  503 Service Unavailable — 서비스 일시 불가
```

---

## 3. FastAPI 라우터 설계

```python
# app/api/v1/endpoints/users.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.user import UserCreate, UserUpdate, UserResponse, UserListResponse
from app.services.user_service import UserService

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/", response_model=UserListResponse)
async def list_users(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    status: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
):
    """사용자 목록 조회 — 페이지네이션 + 필터링"""
    service = UserService(db)
    users, total = await service.list_users(page=page, size=size, status=status)
    return UserListResponse(
        items=users,
        total=total,
        page=page,
        size=size,
    )


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    db: AsyncSession = Depends(get_db),
):
    """사용자 단건 조회"""
    service = UserService(db)
    user = await service.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다")
    return user


@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    body: UserCreate,
    db: AsyncSession = Depends(get_db),
):
    """사용자 생성"""
    service = UserService(db)
    return await service.create_user(body)


@router.patch("/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: str,
    body: UserUpdate,
    db: AsyncSession = Depends(get_db),
):
    """사용자 부분 수정"""
    service = UserService(db)
    return await service.update_user(user_id, body)


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: str,
    db: AsyncSession = Depends(get_db),
):
    """사용자 삭제"""
    service = UserService(db)
    await service.delete_user(user_id)
```

---

## 4. Pydantic 스키마 (DTO)

```python
# app/schemas/user.py
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field, ConfigDict


class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(..., min_length=1, max_length=100)
    password: str = Field(..., min_length=8, max_length=128)


class UserUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    status: str | None = None


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: str
    name: str
    status: str
    created_at: datetime
    updated_at: datetime


class UserListResponse(BaseModel):
    items: list[UserResponse]
    total: int
    page: int
    size: int
```

---

## 5. 페이지네이션 패턴

### Offset 기반

```python
# 간단하지만 대량 데이터에서 성능 저하
@router.get("/")
async def list_items(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    offset = (page - 1) * size
    stmt = select(Item).offset(offset).limit(size)
    result = await db.execute(stmt)
    items = result.scalars().all()

    count_stmt = select(func.count()).select_from(Item)
    total = (await db.execute(count_stmt)).scalar()

    return {"items": items, "total": total, "page": page, "size": size}
```

### Cursor 기반 (대량 데이터 권장)

```python
# 일관된 성능, 실시간 데이터에 적합
@router.get("/")
async def list_items(
    cursor: str | None = None,
    size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(Item).order_by(Item.created_at.desc())

    if cursor:
        cursor_date = datetime.fromisoformat(cursor)
        stmt = stmt.where(Item.created_at < cursor_date)

    stmt = stmt.limit(size + 1)  # 다음 페이지 존재 여부 확인
    result = await db.execute(stmt)
    items = list(result.scalars().all())

    has_next = len(items) > size
    if has_next:
        items = items[:size]

    next_cursor = items[-1].created_at.isoformat() if items and has_next else None

    return {"items": items, "next_cursor": next_cursor}
```

---

## 6. API 버저닝

```python
# app/main.py
from fastapi import FastAPI

app = FastAPI()

# URL 경로 기반 버저닝 (권장)
app.include_router(v1_router, prefix="/api/v1")
app.include_router(v2_router, prefix="/api/v2")
```

---

## 7. 응답 형식 표준화

```python
# app/schemas/common.py
from typing import Generic, TypeVar
from pydantic import BaseModel

T = TypeVar("T")


class ApiResponse(BaseModel, Generic[T]):
    success: bool = True
    data: T | None = None
    error: dict | None = None


class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    size: int
    has_next: bool
```

---

## 8. HATEOAS (선택)

```python
@router.get("/{user_id}")
async def get_user(user_id: str, request: Request):
    user = await service.get_user(user_id)
    return {
        **user.model_dump(),
        "_links": {
            "self": str(request.url),
            "posts": f"/api/v1/users/{user_id}/posts",
            "update": f"/api/v1/users/{user_id}",
        },
    }
```

---

## 9. Content Negotiation

```python
from fastapi.responses import JSONResponse, Response
import csv
import io


@router.get("/export")
async def export_users(
    format: str = Query("json", regex="^(json|csv)$"),
    db: AsyncSession = Depends(get_db),
):
    users = await service.list_all(db)

    if format == "csv":
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(["id", "email", "name"])
        for user in users:
            writer.writerow([user.id, user.email, user.name])
        return Response(
            content=output.getvalue(),
            media_type="text/csv",
            headers={"Content-Disposition": "attachment; filename=users.csv"},
        )

    return users
```
