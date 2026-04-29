# Architecture

> Python/FastAPI 버전 — 원본: Architecture

---

## 1. FastAPI 레이어드 아키텍처

```
HTTP Request
    ↓
Router/Endpoint   (요청/응답 처리, Pydantic 스키마 변환)
    ↓
Service           (비즈니스 로직)
    ↓
Repository        (데이터 접근)
    ↓
Database
```

```
app/
  api/v1/
    endpoints/
      users.py            # HTTP 레이어 (Router)
      posts.py
    router.py             # 라우터 통합
  services/
    user_service.py       # 비즈니스 로직
    post_service.py
  db/
    base.py               # Base, Mixin
    models.py             # ORM 모델
    session.py            # 엔진, get_db()
    repositories/
      user_repository.py  # 데이터 접근
      post_repository.py
  schemas/
    user.py               # Pydantic DTO
    post.py
    common.py             # 공통 응답 스키마
  core/
    config.py             # Pydantic Settings
    security.py           # 인증/인가
    exceptions.py         # 커스텀 예외 + 글로벌 핸들러
    logging.py            # 구조화 로깅
  middleware/
    request_id.py         # Request ID 주입
    timing.py             # 응답 시간 측정
  utils/
    jwt.py
    hash.py
  main.py                 # FastAPI 진입점
```

---

## 2. 레이어별 책임

### Router (Endpoint)

```python
# app/api/v1/endpoints/users.py
# 역할: 요청 파싱, 응답 반환, 의존성 주입
# 금지: 비즈니스 로직, DB 직접 접근

@router.post("/", response_model=UserResponse, status_code=201)
async def create_user(
    body: UserCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_admin),  # 인가
):
    service = UserService(db)
    return await service.create_user(body)
```

### Service

```python
# app/services/user_service.py
# 역할: 비즈니스 로직, 트랜잭션 관리, 외부 서비스 호출
# 금지: HTTP 관련 로직, SQLAlchemy 직접 쿼리

class UserService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = UserRepository(db)

    async def create_user(self, data: UserCreate) -> User:
        # 비즈니스 규칙 검증
        existing = await self.repo.find_by_email(data.email)
        if existing:
            raise DuplicateEmailException(data.email)

        hashed = hash_password(data.password)
        user = await self.repo.create(
            email=data.email,
            name=data.name,
            password=hashed,
        )
        # 후속 처리 (이메일 발송 등)
        return user
```

### Repository

```python
# app/db/repositories/user_repository.py
# 역할: DB 쿼리, 데이터 매핑
# 금지: 비즈니스 로직, HTTP 관련 로직

class UserRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def find_by_email(self, email: str) -> User | None:
        stmt = select(User).where(User.email == email)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def create(self, **kwargs) -> User:
        user = User(**kwargs)
        self.db.add(user)
        await self.db.flush()
        await self.db.refresh(user)
        return user
```

---

## 3. 의존성 주입 (FastAPI Depends)

```python
# app/core/dependencies.py
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.services.user_service import UserService


def get_user_service(db: AsyncSession = Depends(get_db)) -> UserService:
    return UserService(db)


# 라우터에서 사용
@router.get("/{user_id}")
async def get_user(
    user_id: str,
    service: UserService = Depends(get_user_service),
):
    return await service.get_user(user_id)
```

---

## 4. 설정 관리

```python
# app/core/config.py
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # App
    APP_NAME: str = "identity-hub"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    # Database
    DATABASE_URL: str
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20

    # Redis
    REDIS_URL: str
    SESSION_TTL: int = 86400

    # Keycloak
    KEYCLOAK_SERVER_URL: str
    KEYCLOAK_INTERNAL_URL: str
    KEYCLOAK_ADMIN_USERNAME: str
    KEYCLOAK_ADMIN_PASSWORD: str

    # Security
    ALLOWED_REDIRECT_URI_PATTERNS: list[str] = []

    model_config = {"env_file": ".env", "case_sensitive": True}


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

---

## 5. 미들웨어 패턴

```python
# app/middleware/request_id.py
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.request_id = request_id

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response
```

```python
# app/main.py
app = FastAPI(title="Identity Hub")
app.add_middleware(RequestIdMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)
```

---

## 6. 라이프사이클 관리

```python
# app/main.py
from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 시작 시
    await init_db()
    await init_redis()
    yield
    # 종료 시
    await close_db()
    await close_redis()


app = FastAPI(lifespan=lifespan)
```

---

## 7. 모듈 구성 패턴

```python
# app/api/v1/router.py — 라우터 통합
from fastapi import APIRouter

from app.api.v1.endpoints import users, posts, auth, admin

api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(posts.router, prefix="/posts", tags=["posts"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
```

---

## 8. 클린 아키텍처 고려사항

```
규칙: 의존성은 안쪽으로만 향한다

  [Router] → [Service] → [Repository] → [DB]
     ↑           ↑
  [Schema]    [Domain Model]

- Router는 Service를 알지만, Service는 Router를 모른다
- Service는 Repository를 알지만, Repository는 Service를 모른다
- Domain 모델은 아무것도 의존하지 않는다
```
