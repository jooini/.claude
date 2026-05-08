# Database

> Python/FastAPI 버전 — 원본: Database

---

## 1. SQLAlchemy 2.0 모델 설계

```python
# app/db/base.py
from datetime import datetime, timezone
from sqlalchemy import func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        default=func.now(),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        default=func.now(),
        onupdate=func.now(),
        server_default=func.now(),
    )
```

```python
# app/db/models.py
import uuid
from enum import Enum as PyEnum
from sqlalchemy import String, Enum, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin


class UserStatus(str, PyEnum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    BANNED = "banned"


class User(Base, TimestampMixin):
    __tablename__ = "users"
    __table_args__ = (
        Index("ix_users_email", "email", unique=True),
        Index("ix_users_status_created", "status", "created_at"),
    )

    id: Mapped[str] = mapped_column(
        UUID(as_uuid=False),
        primary_key=True,
        default=lambda: str(uuid.uuid4()),
    )
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    password: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[UserStatus] = mapped_column(
        Enum(UserStatus), default=UserStatus.ACTIVE, nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(default=None)

    # 관계
    posts: Mapped[list["Post"]] = relationship(back_populates="author", lazy="selectin")
```

---

## 2. 관계 매핑

```python
# One-to-Many
class Post(Base, TimestampMixin):
    __tablename__ = "posts"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True)
    title: Mapped[str] = mapped_column(String(255))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))

    author: Mapped["User"] = relationship(back_populates="posts")
    tags: Mapped[list["Tag"]] = relationship(
        secondary="post_tags", back_populates="posts"
    )


# Many-to-Many
post_tags = Table(
    "post_tags",
    Base.metadata,
    Column("post_id", ForeignKey("posts.id"), primary_key=True),
    Column("tag_id", ForeignKey("tags.id"), primary_key=True),
)


class Tag(Base):
    __tablename__ = "tags"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(50), unique=True)
    posts: Mapped[list["Post"]] = relationship(
        secondary="post_tags", back_populates="tags"
    )
```

---

## 3. 세션 관리

```python
# app/db/session.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.core.config import get_settings

settings = get_settings()

engine = create_async_engine(
    settings.DATABASE_URL,
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_pre_ping=True,  # 연결 유효성 검사
    echo=settings.DEBUG,
)

async_session = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncSession:
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

---

## 4. Repository 패턴

```python
# app/db/repositories/user_repository.py
from sqlalchemy import select, update, func
from sqlalchemy.ext.asyncio import AsyncSession


class UserRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def find_by_id(self, user_id: str) -> User | None:
        stmt = select(User).where(User.id == user_id, User.deleted_at.is_(None))
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def find_by_email(self, email: str) -> User | None:
        stmt = select(User).where(User.email == email)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def list_users(
        self, page: int = 1, size: int = 20, status: str | None = None,
    ) -> tuple[list[User], int]:
        stmt = select(User).where(User.deleted_at.is_(None))
        count_stmt = select(func.count()).select_from(User).where(User.deleted_at.is_(None))

        if status:
            stmt = stmt.where(User.status == status)
            count_stmt = count_stmt.where(User.status == status)

        stmt = stmt.offset((page - 1) * size).limit(size)
        result = await self.db.execute(stmt)
        total = (await self.db.execute(count_stmt)).scalar()
        return list(result.scalars().all()), total

    async def create(self, **kwargs) -> User:
        user = User(**kwargs)
        self.db.add(user)
        await self.db.flush()
        await self.db.refresh(user)
        return user

    async def soft_delete(self, user_id: str) -> None:
        stmt = (
            update(User)
            .where(User.id == user_id)
            .values(deleted_at=func.now())
        )
        await self.db.execute(stmt)
```

---

## 5. 마이그레이션 (Alembic)

```bash
# 초기 설정
alembic init alembic

# 마이그레이션 생성
alembic revision --autogenerate -m "create users table"

# 마이그레이션 적용
alembic upgrade head

# 롤백
alembic downgrade -1
```

```python
# alembic/env.py
from app.db.base import Base
from app.db.models import *  # 모든 모델 임포트

target_metadata = Base.metadata
```

---

## 6. Soft Delete 패턴

```python
# Repository에서 기본 필터링
async def find_active(self, **filters) -> list[User]:
    stmt = select(User).where(
        User.deleted_at.is_(None),  # soft delete 필터
        *[getattr(User, k) == v for k, v in filters.items()],
    )
    result = await self.db.execute(stmt)
    return list(result.scalars().all())
```

---

## 7. 트랜잭션 관리

```python
# 명시적 트랜잭션 (서비스 레이어)
async def transfer_funds(self, from_id: str, to_id: str, amount: int):
    async with self.db.begin():  # 자동 commit/rollback
        sender = await self.repo.find_by_id_for_update(from_id)
        receiver = await self.repo.find_by_id_for_update(to_id)

        if sender.balance < amount:
            raise InsufficientBalanceException()

        sender.balance -= amount
        receiver.balance += amount
```
