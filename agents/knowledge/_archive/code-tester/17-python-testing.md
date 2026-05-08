# Python Testing

> 참조 링크: https://docs.pytest.org/en/stable/, https://docs.python.org/3/library/unittest.mock.html

---

## 1. pytest 기본

### 디렉토리 구조

```
project/
├── src/
│   └── myapp/
│       ├── __init__.py
│       ├── services/
│       │   └── user_service.py
│       └── models/
│           └── user.py
├── tests/
│   ├── conftest.py          # 공유 fixture
│   ├── unit/
│   │   └── test_user_service.py
│   ├── integration/
│   │   └── test_user_api.py
│   └── e2e/
│       └── test_user_flow.py
└── pyproject.toml
```

### 기본 테스트

```python
# tests/unit/test_user_service.py
from myapp.services.user_service import UserService

class TestUserService:
    def test_create_user(self):
        service = UserService()
        user = service.create(name="John", email="john@test.com")
        assert user.name == "John"
        assert user.email == "john@test.com"
        assert user.id is not None

    def test_create_user_invalid_email(self):
        service = UserService()
        with pytest.raises(ValueError, match="Invalid email"):
            service.create(name="John", email="invalid")

    def test_find_user_not_found(self):
        service = UserService()
        with pytest.raises(UserNotFoundError):
            service.find_by_id(999)
```

## 2. Fixture

### 기본 fixture

```python
# tests/conftest.py
import pytest
from myapp.database import create_engine, Session

@pytest.fixture
def db_session():
    """각 테스트마다 새 DB 세션 (롤백)"""
    engine = create_engine("sqlite:///:memory:")
    session = Session(bind=engine)
    yield session
    session.rollback()
    session.close()

@pytest.fixture
def user_service(db_session):
    """UserService with DB session"""
    return UserService(session=db_session)

@pytest.fixture
def sample_user(user_service):
    """테스트용 사용자"""
    return user_service.create(name="John", email="john@test.com")
```

### Fixture scope

```python
@pytest.fixture(scope="session")   # 전체 테스트 세션에서 1번
def database():
    engine = create_engine(TEST_DB_URL)
    Base.metadata.create_all(engine)
    yield engine
    Base.metadata.drop_all(engine)

@pytest.fixture(scope="module")    # 모듈(파일)당 1번
def api_client():
    app = create_app()
    return app.test_client()

@pytest.fixture(scope="function")  # 기본값: 각 테스트마다
def clean_db(database):
    yield
    # 테스트 후 정리
```

### Factory fixture

```python
@pytest.fixture
def create_user(db_session):
    """사용자 팩토리 — 테스트마다 다른 데이터 생성"""
    created = []

    def _create(name="John", email=None, **kwargs):
        email = email or f"{name.lower()}@test.com"
        user = User(name=name, email=email, **kwargs)
        db_session.add(user)
        db_session.flush()
        created.append(user)
        return user

    yield _create

    for user in created:
        db_session.delete(user)

# 사용
def test_multiple_users(create_user):
    alice = create_user(name="Alice")
    bob = create_user(name="Bob")
    assert alice.id != bob.id
```

## 3. Parametrize

```python
@pytest.mark.parametrize("input,expected", [
    ("john@test.com", True),
    ("invalid", False),
    ("", False),
    ("a@b.c", True),
    ("test@.com", False),
])
def test_validate_email(input, expected):
    assert validate_email(input) == expected

# 여러 파라미터 조합
@pytest.mark.parametrize("role", ["admin", "user", "guest"])
@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_permissions(role, method):
    result = check_permission(role, method)
    # 9가지 조합 (3 roles × 3 methods) 자동 생성
```

## 4. Mock

### unittest.mock

```python
from unittest.mock import Mock, patch, MagicMock, AsyncMock

# 기본 Mock
def test_send_email(user_service):
    mock_mailer = Mock()
    mock_mailer.send.return_value = True
    user_service.mailer = mock_mailer

    user_service.create_and_notify(name="John", email="john@test.com")

    mock_mailer.send.assert_called_once_with(
        to="john@test.com",
        subject="Welcome",
    )

# patch decorator
@patch("myapp.services.user_service.send_email")
def test_create_user(mock_send, user_service):
    user_service.create(name="John", email="john@test.com")
    mock_send.assert_called_once()

# context manager
def test_external_api():
    with patch("myapp.clients.api_client.get") as mock_get:
        mock_get.return_value = {"status": "ok"}
        result = check_health()
        assert result is True
```

### Async Mock

```python
@pytest.mark.asyncio
async def test_async_service():
    mock_repo = AsyncMock()
    mock_repo.find_by_id.return_value = User(id=1, name="John")

    service = UserService(repo=mock_repo)
    user = await service.get_user(1)

    assert user.name == "John"
    mock_repo.find_by_id.assert_awaited_once_with(1)
```

## 5. 마커 (Marker)

```python
# pyproject.toml에 마커 등록
# [tool.pytest.ini_options]
# markers = ["slow", "integration", "e2e"]

@pytest.mark.slow
def test_heavy_computation():
    ...

@pytest.mark.integration
def test_database_query():
    ...

@pytest.mark.skip(reason="API 미구현")
def test_upcoming_feature():
    ...

@pytest.mark.skipif(sys.platform == "win32", reason="Linux only")
def test_unix_specific():
    ...

@pytest.mark.xfail(reason="Known bug #123")
def test_known_issue():
    ...
```

```bash
# 마커로 필터 실행
pytest -m "not slow"
pytest -m "integration"
pytest -m "not (slow or e2e)"
```

## 6. FastAPI 테스트

```python
from fastapi.testclient import TestClient
from myapp.main import app

@pytest.fixture
def client():
    return TestClient(app)

def test_create_user(client):
    response = client.post("/users", json={"name": "John", "email": "john@test.com"})
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "John"

def test_get_users(client):
    response = client.get("/users")
    assert response.status_code == 200
    assert isinstance(response.json(), list)

# Async 테스트 (httpx)
import httpx
from asgi_lifespan import LifespanManager

@pytest.fixture
async def async_client():
    async with LifespanManager(app):
        async with httpx.AsyncClient(app=app, base_url="http://test") as client:
            yield client

@pytest.mark.asyncio
async def test_async_endpoint(async_client):
    response = await async_client.get("/users")
    assert response.status_code == 200
```

## 7. conftest.py 계층

```
tests/
├── conftest.py              # 전역 fixture (DB, 클라이언트)
├── unit/
│   ├── conftest.py          # 단위 테스트 전용 fixture
│   └── test_service.py
└── integration/
    ├── conftest.py          # 통합 테스트 전용 fixture
    └── test_api.py
```

하위 conftest는 상위 conftest의 fixture를 자동으로 상속한다.
