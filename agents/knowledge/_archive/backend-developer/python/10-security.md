# Security

> Python/FastAPI 버전 — 원본: Security

---

## 1. 인증 (Authentication)

### JWT + Refresh Token

```python
# app/core/security.py
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

SECRET_KEY = "your-secret-key"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 15
REFRESH_TOKEN_EXPIRE_DAYS = 7


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode({"sub": user_id, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    return jwt.encode({"sub": user_id, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise InvalidTokenException()
```

### FastAPI 인증 의존성

```python
# app/core/deps.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

bearer_scheme = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    payload = decode_token(credentials.credentials)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="유효하지 않은 토큰")

    user = await UserRepository(db).find_by_id(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="사용자를 찾을 수 없습니다")
    return user


async def get_current_admin(
    current_user: User = Depends(get_current_user),
) -> User:
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="관리자 권한이 필요합니다")
    return current_user
```

### Refresh Token 저장 (Redis)

```python
# app/services/auth_service.py
import redis.asyncio as redis


class AuthService:
    def __init__(self, db: AsyncSession, redis_client: redis.Redis):
        self.db = db
        self.redis = redis_client

    async def login(self, email: str, password: str) -> dict:
        user = await self.repo.find_by_email(email)
        if not user or not verify_password(password, user.password):
            raise HTTPException(status_code=401, detail="인증 실패")

        access_token = create_access_token(user.id)
        refresh_token = create_refresh_token(user.id)

        # Redis에 refresh token 저장 (revocation 가능)
        await self.redis.setex(
            f"refresh:{user.id}",
            REFRESH_TOKEN_EXPIRE_DAYS * 86400,
            refresh_token,
        )

        return {"access_token": access_token, "refresh_token": refresh_token}

    async def refresh(self, refresh_token: str) -> dict:
        payload = decode_token(refresh_token)
        user_id = payload["sub"]

        # Redis에서 유효성 확인
        stored = await self.redis.get(f"refresh:{user_id}")
        if stored is None or stored.decode() != refresh_token:
            raise HTTPException(status_code=401, detail="유효하지 않은 refresh token")

        # 새 토큰 발급 (Rotation)
        new_access = create_access_token(user_id)
        new_refresh = create_refresh_token(user_id)
        await self.redis.setex(f"refresh:{user_id}", REFRESH_TOKEN_EXPIRE_DAYS * 86400, new_refresh)

        return {"access_token": new_access, "refresh_token": new_refresh}
```

---

## 2. 인가 (Authorization)

### RBAC (Role-Based Access Control)

```python
# app/core/permissions.py
from enum import Enum
from functools import wraps
from fastapi import HTTPException


class Role(str, Enum):
    USER = "user"
    ADMIN = "admin"
    SUPER_ADMIN = "super_admin"


def require_roles(*roles: Role):
    """역할 기반 접근 제어 의존성"""
    async def dependency(current_user: User = Depends(get_current_user)):
        if current_user.role not in roles:
            raise HTTPException(status_code=403, detail="권한이 없습니다")
        return current_user
    return dependency


# 사용
@router.delete("/{user_id}")
async def delete_user(
    user_id: str,
    current_user: User = Depends(require_roles(Role.ADMIN, Role.SUPER_ADMIN)),
    db: AsyncSession = Depends(get_db),
):
    ...
```

### 리소스 소유권 검증

```python
async def verify_resource_owner(
    user_id: str,
    current_user: User = Depends(get_current_user),
) -> User:
    """본인 또는 관리자만 접근 가능"""
    if current_user.id != user_id and current_user.role != Role.ADMIN:
        raise HTTPException(status_code=403, detail="접근 권한이 없습니다")
    return current_user
```

---

## 3. 입력 검증

```python
# Pydantic v2로 자동 검증
from pydantic import BaseModel, EmailStr, Field, field_validator
import re


class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(..., min_length=1, max_length=100)
    password: str = Field(..., min_length=8, max_length=128)

    @field_validator("name")
    @classmethod
    def sanitize_name(cls, v: str) -> str:
        # HTML 태그 제거
        return re.sub(r"<[^>]+>", "", v).strip()

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if not re.search(r"[A-Z]", v):
            raise ValueError("대문자 1자 이상 포함 필요")
        if not re.search(r"[0-9]", v):
            raise ValueError("숫자 1자 이상 포함 필요")
        return v
```

---

## 4. Rate Limiting

```python
# slowapi 사용
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)


@router.post("/login")
@limiter.limit("5/minute")
async def login(request: Request, body: LoginRequest):
    ...


@router.post("/password-reset")
@limiter.limit("3/hour")
async def reset_password(request: Request, body: ResetRequest):
    ...
```

---

## 5. CORS 설정

```python
# app/main.py
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,  # ["https://app.example.com"]
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    max_age=3600,
)
```

---

## 6. 보안 헤더

```python
# app/middleware/security_headers.py
class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Cache-Control"] = "no-store"
        return response
```

---

## 7. 시크릿 관리

```python
# ✅ 환경변수 사용 (pydantic-settings)
class Settings(BaseSettings):
    DATABASE_URL: str
    JWT_SECRET: str
    REDIS_URL: str

    model_config = {"env_file": ".env"}

# ❌ 하드코딩 금지
SECRET = "my-secret-key"  # 절대 하지 말 것

# ✅ .env 파일은 .gitignore에 추가
# .gitignore
# .env
# .env.local
```
