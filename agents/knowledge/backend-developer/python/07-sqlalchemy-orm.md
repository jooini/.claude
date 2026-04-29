# SQLAlchemy ORM

> Python/FastAPI 버전 — 원본: Drizzle ORM

---

## 1. SQLAlchemy ORM이란?

Python의 표준 ORM. SQL에 대한 높은 제어권과 타입 안전성 제공. 2.0 스타일은 더 명시적이고 async 지원.

**TypeORM vs SQLAlchemy:**

| 항목 | TypeORM | SQLAlchemy 2.0 |
|------|---------|----------------|
| 방식 | Decorator 기반 | Mapped class |
| SQL 접근성 | 추상화 높음 | SQL에 가까움 |
| 타입 안전성 | 제한적 | Mapped[] 타입 추론 |
| Async | 제한적 | 완전 지원 (asyncpg) |
| 마이그레이션 | TypeORM migrations | Alembic |

---

## 2. 스키마 정의

```python
# app/db/models.py
from sqlalchemy import String, Integer, Boolean, ForeignKey, Enum, Index, Table, Column
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import uuid
import enum


class Base(DeclarativeBase):
    pass


class UserStatus(str, enum.Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    BANNED = "banned"


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(UUID(as_uuid=False), primary_key=True, default=lambda: str(uuid.uuid4()))
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    password: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[UserStatus] = mapped_column(Enum(UserStatus), default=UserStatus.ACTIVE)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())
```

---

## 3. CRUD 작업

### Create

```python
async def create_user(db: AsyncSession, email: str, name: str, password: str) -> User:
    user = User(email=email, name=name, password=password)
    db.add(user)
    await db.flush()
    await db.refresh(user)
    return user

# 벌크 삽입
async def create_many(db: AsyncSession, users_data: list[dict]) -> None:
    db.add_all([User(**data) for data in users_data])
    await db.flush()
```

### Read

```python
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload, joinedload

# 단건 조회
async def find_by_id(db: AsyncSession, user_id: str) -> User | None:
    stmt = select(User).where(User.id == user_id)
    result = await db.execute(stmt)
    return result.scalar_one_or_none()

# 조건 조회
async def find_active_users(db: AsyncSession) -> list[User]:
    stmt = select(User).where(User.status == UserStatus.ACTIVE).order_by(User.created_at.desc())
    result = await db.execute(stmt)
    return list(result.scalars().all())

# 관계 로딩 (N+1 방지)
async def find_with_posts(db: AsyncSession, user_id: str) -> User | None:
    stmt = (
        select(User)
        .where(User.id == user_id)
        .options(selectinload(User.posts))  # Eager loading
    )
    result = await db.execute(stmt)
    return result.scalar_one_or_none()

# 페이지네이션
async def paginate(db: AsyncSession, page: int, size: int) -> tuple[list[User], int]:
    stmt = select(User).offset((page - 1) * size).limit(size)
    count_stmt = select(func.count()).select_from(User)

    result = await db.execute(stmt)
    total = (await db.execute(count_stmt)).scalar()
    return list(result.scalars().all()), total
```

### Update

```python
from sqlalchemy import update

# 단건 수정
async def update_user(db: AsyncSession, user_id: str, **kwargs) -> User | None:
    user = await find_by_id(db, user_id)
    if not user:
        return None
    for key, value in kwargs.items():
        setattr(user, key, value)
    await db.flush()
    await db.refresh(user)
    return user

# 벌크 수정
async def deactivate_old_users(db: AsyncSession, before: datetime) -> int:
    stmt = (
        update(User)
        .where(User.last_login < before, User.status == UserStatus.ACTIVE)
        .values(status=UserStatus.INACTIVE)
    )
    result = await db.execute(stmt)
    return result.rowcount
```

### Delete

```python
from sqlalchemy import delete

# Hard delete
async def delete_user(db: AsyncSession, user_id: str) -> None:
    stmt = delete(User).where(User.id == user_id)
    await db.execute(stmt)

# Soft delete (권장)
async def soft_delete(db: AsyncSession, user_id: str) -> None:
    stmt = update(User).where(User.id == user_id).values(deleted_at=func.now())
    await db.execute(stmt)
```

---

## 4. 조인 & 서브쿼리

```python
# Inner Join
stmt = (
    select(User, Post)
    .join(Post, User.id == Post.user_id)
    .where(Post.published == True)
)

# Left Join
stmt = select(User, Post).outerjoin(Post, User.id == Post.user_id)

# 서브쿼리
subquery = (
    select(func.count(Post.id).label("post_count"), Post.user_id)
    .group_by(Post.user_id)
    .subquery()
)

stmt = (
    select(User, subquery.c.post_count)
    .outerjoin(subquery, User.id == subquery.c.user_id)
    .order_by(subquery.c.post_count.desc().nulls_last())
)
```

---

## 5. Raw SQL (필요 시)

```python
from sqlalchemy import text

# 복잡한 쿼리는 Raw SQL 사용 가능
stmt = text("""
    SELECT u.id, u.email, COUNT(p.id) as post_count
    FROM users u
    LEFT JOIN posts p ON u.id = p.user_id
    WHERE u.status = :status
    GROUP BY u.id, u.email
    HAVING COUNT(p.id) > :min_posts
""")

result = await db.execute(stmt, {"status": "active", "min_posts": 5})
rows = result.fetchall()
```

---

## 6. 트랜잭션

```python
# 자동 트랜잭션 (get_db 의존성에서 관리)
async def get_db():
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

# 명시적 중첩 트랜잭션 (Savepoint)
async def complex_operation(db: AsyncSession):
    async with db.begin_nested():  # SAVEPOINT
        await db.execute(...)
        # 이 블록 실패 시 savepoint만 롤백
```

---

## 7. 인덱스 전략

```python
class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (
        Index("ix_orders_user_status", "user_id", "status"),  # 복합 인덱스
        Index("ix_orders_created", "created_at"),
        Index("ix_orders_amount", "amount", postgresql_using="btree"),
    )

    id: Mapped[str] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(20))
    amount: Mapped[int] = mapped_column()
    created_at: Mapped[datetime] = mapped_column()
```
