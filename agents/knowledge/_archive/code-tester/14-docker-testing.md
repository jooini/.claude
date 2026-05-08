# Docker Testing

> 참조 링크: https://docs.docker.com/compose/, https://node.testcontainers.org/

---

## 1. Docker Compose 테스트 환경

### 기본 구성

```yaml
# docker-compose.test.yml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: testdb
    ports:
      - "5433:5432"  # 호스트 포트 충돌 방지
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6380:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  mariadb:
    image: mariadb:11
    environment:
      MARIADB_ROOT_PASSWORD: test
      MARIADB_DATABASE: testdb
      MARIADB_USER: test
      MARIADB_PASSWORD: test
    ports:
      - "3307:3306"
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 5s
      timeout: 3s
      retries: 5
```

### 테스트 실행 스크립트

```bash
#!/bin/bash
# scripts/test-with-docker.sh

# 서비스 시작
docker compose -f docker-compose.test.yml up -d --wait

# 테스트 실행
DATABASE_URL="postgresql://test:test@localhost:5433/testdb" \
REDIS_URL="redis://localhost:6380" \
npx jest --runInBand

# 결과 저장
TEST_EXIT_CODE=$?

# 정리
docker compose -f docker-compose.test.yml down -v

exit $TEST_EXIT_CODE
```

## 2. Testcontainers

프로그래밍 방식으로 Docker 컨테이너를 관리한다. 테스트 코드에서 직접 컨테이너를 생성/삭제한다.

### Node.js (testcontainers)

```typescript
import { PostgreSqlContainer } from '@testcontainers/postgresql';
import { RedisContainer } from '@testcontainers/redis';

describe('UserService (integration)', () => {
  let pgContainer: any;
  let pgUrl: string;

  beforeAll(async () => {
    pgContainer = await new PostgreSqlContainer('postgres:16')
      .withDatabase('testdb')
      .withUsername('test')
      .withPassword('test')
      .start();

    pgUrl = pgContainer.getConnectionUri();
    // pgUrl = "postgresql://test:test@localhost:32768/testdb"
  }, 60000); // 컨테이너 시작 시간 고려

  afterAll(async () => {
    await pgContainer.stop();
  });

  it('should create user', async () => {
    const service = new UserService(pgUrl);
    const user = await service.create({ name: 'John' });
    expect(user.id).toBeDefined();
  });
});
```

### MariaDB Testcontainer

```typescript
import { MariaDbContainer } from '@testcontainers/mariadb';

let container: any;

beforeAll(async () => {
  container = await new MariaDbContainer('mariadb:11')
    .withDatabase('testdb')
    .withUsername('test')
    .withRootPassword('test')
    .start();

  const url = `mysql://test:test@${container.getHost()}:${container.getMappedPort(3306)}/testdb`;
}, 60000);

afterAll(async () => {
  await container.stop();
});
```

### Python (testcontainers-python)

```python
from testcontainers.postgres import PostgresContainer
import pytest

@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:16") as pg:
        yield pg.get_connection_url()

def test_create_user(postgres):
    engine = create_engine(postgres)
    # ... 테스트
```

## 3. DB 초기화 전략

### 트랜잭션 롤백 (가장 빠름)

```typescript
describe('UserService', () => {
  let queryRunner: QueryRunner;

  beforeEach(async () => {
    queryRunner = dataSource.createQueryRunner();
    await queryRunner.startTransaction();
  });

  afterEach(async () => {
    await queryRunner.rollbackTransaction();
    await queryRunner.release();
  });

  it('should create user', async () => {
    // 이 트랜잭션은 롤백되므로 다른 테스트에 영향 없음
  });
});
```

### 테이블 TRUNCATE

```typescript
beforeEach(async () => {
  const entities = dataSource.entityMetadatas;
  for (const entity of entities) {
    const repo = dataSource.getRepository(entity.name);
    await repo.query(`TRUNCATE TABLE "${entity.tableName}" CASCADE`);
  }
});
```

### 마이그레이션 재실행

```typescript
beforeAll(async () => {
  await dataSource.dropDatabase();
  await dataSource.runMigrations();
});
```

## 4. 네트워크 격리

```yaml
# docker-compose.test.yml
services:
  app:
    build: .
    networks:
      - test-net
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16
    networks:
      - test-net

networks:
  test-net:
    driver: bridge
```

## 5. CI에서 Docker 테스트

### GitHub Actions

```yaml
jobs:
  integration-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm install
      - run: npm run test:e2e
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/testdb
```

### Testcontainers in CI

```yaml
# Testcontainers는 Docker socket 접근 필요
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm install
      - run: npm run test:integration
        # GitHub Actions runner에는 Docker가 기본 설치됨
```

## 6. 테스트 성능 최적화

| 방법 | 효과 | 적용 |
|------|------|------|
| Alpine 이미지 | 이미지 pull 시간 감소 | `postgres:16-alpine` |
| tmpfs 마운트 | DB I/O 속도 향상 | `--mount type=tmpfs,destination=/var/lib/postgresql/data` |
| 컨테이너 재사용 | 시작 시간 제거 | `scope="session"` fixture |
| 병렬 DB | 테스트 격리 + 병렬 | 테스트별 DB 생성 |
| 이미지 캐시 | CI pull 시간 감소 | Docker layer cache |

```yaml
# tmpfs로 DB 성능 향상
services:
  postgres:
    image: postgres:16-alpine
    tmpfs:
      - /var/lib/postgresql/data
    command: >
      postgres
      -c fsync=off
      -c synchronous_commit=off
      -c full_page_writes=off
```
