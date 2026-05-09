# Testing

> Python 버전 — 원본: Testing

---

## 1. 테스트 전략

```
Unit Test       빠름, 격리, 로직 검증
Integration     DB/외부 서비스 포함, 슬로우
E2E             실제 HTTP 요청, 가장 느림

권장 비율: Unit 70% / Integration 20% / E2E 10%
```

Python 테스트 스택: pytest + pytest-asyncio + httpx + factory_boy

---

## 2. Unit Test — Service

```python
# tests/unit/test_user_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock
from app.services.user_service import UserService
from app.core.exceptions import DuplicateEmailException


@pytest.fixture
def mock_repo():
    repo = AsyncMock()
    repo.find_by_email = AsyncMock(return_value=None)
    repo.create = AsyncMock()
    return repo


@pytest.fixture
def service(mock_repo):
    svc = UserService.__new__(UserService)
    svc.repo = mock_repo
    return svc


class TestUserServiceCreate:
    async def test_이메일_중복_시_예외(self, service, mock_repo):
        mock_repo.find_by_email.return_value = MagicMock(id="1", email="test@test.com")

        with pytest.raises(DuplicateEmailException):
            await service.create_user(
                UserCreate(email="test@test.com", name="테스트", password="Test1234!")
            )

        mock_repo.create.assert_not_called()

    async def test_정상_생성(self, service, mock_repo):
        mock_repo.create.return_value = MagicMock(id="1", email="new@test.com")

        result = await service.create_user(
            UserCreate(email="new@test.com", name="신규", password="Test1234!")
        )

        mock_repo.find_by_email.assert_called_once_with("new@test.com")
        mock_repo.create.assert_called_once()
        assert result.email == "new@test.com"
```

---

## 3. Integration Test — API

```python
# tests/integration/test_users_api.py
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


class TestUsersAPI:
    async def test_사용자_생성(self, client: AsyncClient):
        response = await client.post(
            "/api/v1/users/",
            json={
                "email": "test@example.com",
                "name": "테스트",
                "password": "Test1234!",
            },
        )
        assert response.status_code == 201
        data = response.json()
        assert data["email"] == "test@example.com"

    async def test_중복_이메일_409(self, client: AsyncClient):
        # 첫 번째 생성
        await client.post("/api/v1/users/", json={...})

        # 중복 생성
        response = await client.post("/api/v1/users/", json={...})
        assert response.status_code == 409

    async def test_존재하지_않는_사용자_404(self, client: AsyncClient):
        response = await client.get("/api/v1/users/nonexistent-id")
        assert response.status_code == 404
```

---

## 4. DB 테스트 Fixture

```python
# tests/conftest.py
import pytest_asyncio
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.db.base import Base
from app.db.session import get_db
from app.main import app

TEST_DB_URL = "postgresql+asyncpg://test:test@localhost:5432/test_db"


@pytest_asyncio.fixture(scope="session")
async def engine():
    engine = create_async_engine(TEST_DB_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(engine):
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        yield session
        await session.rollback()  # 각 테스트 후 롤백


@pytest_asyncio.fixture
async def client(db_session):
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
```

---

## 5. Factory 패턴

```python
# tests/factories.py
import factory
from factory.alchemy import SQLAlchemyModelFactory
from app.db.models import User, UserStatus


class UserFactory(SQLAlchemyModelFactory):
    class Meta:
        model = User
        sqlalchemy_session_persistence = "flush"

    id = factory.LazyFunction(lambda: str(uuid.uuid4()))
    email = factory.Sequence(lambda n: f"user{n}@test.com")
    name = factory.Faker("name", locale="ko_KR")
    password = "$2b$12$hashed_password"  # pre-hashed
    status = UserStatus.ACTIVE


# 사용
async def test_사용자_목록_조회(db_session):
    UserFactory._meta.sqlalchemy_session = db_session
    UserFactory.create_batch(5)
    await db_session.flush()

    users = await repo.list_users(page=1, size=10)
    assert len(users[0]) == 5
```

---

## 6. Mock 패턴

```python
from unittest.mock import patch, AsyncMock

# 외부 서비스 Mock
async def test_결제_실패_처리():
    with patch.object(PaymentService, "charge", new_callable=AsyncMock) as mock_charge:
        mock_charge.side_effect = PaymentFailedException()

        with pytest.raises(PaymentFailedException):
            await order_service.create_order(...)

        mock_charge.assert_called_once()


# Redis Mock
async def test_캐시_히트():
    with patch("app.services.cache_service.redis") as mock_redis:
        mock_redis.get = AsyncMock(return_value=b'{"id": "1", "name": "cached"}')

        result = await cache_service.get("user:1")
        assert result["name"] == "cached"
```

---

## 7. pytest 설정

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
markers = [
    "slow: 느린 테스트",
    "integration: 통합 테스트",
]
filterwarnings = ["ignore::DeprecationWarning"]

[tool.coverage.run]
source = ["app"]
omit = ["tests/*", "alembic/*"]

[tool.coverage.report]
fail_under = 80
```

```bash
# 실행
pytest tests/ -v                      # 전체
pytest tests/unit/ -v                 # 단위 테스트만
pytest tests/ -v --cov=app            # 커버리지
pytest tests/ -v -m "not slow"        # 느린 테스트 제외
pytest tests/ -v -x                   # 첫 실패 시 중단
pytest tests/ -v -n auto              # 병렬 실행 (pytest-xdist)
```
