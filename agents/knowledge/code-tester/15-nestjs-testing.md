# NestJS Testing

> 참조 링크: https://docs.nestjs.com/fundamentals/testing

---

## 1. TestingModule

NestJS 테스트의 핵심. 실제 모듈과 동일한 DI 컨테이너를 생성한다.

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { UserService } from './user.service';
import { UserRepository } from './user.repository';

describe('UserService', () => {
  let service: UserService;
  let repository: jest.Mocked<UserRepository>;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UserService,
        {
          provide: UserRepository,
          useValue: {
            findOne: jest.fn(),
            save: jest.fn(),
            find: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<UserService>(UserService);
    repository = module.get(UserRepository);
  });

  it('should find user by id', async () => {
    const mockUser = { id: 1, name: 'John', email: 'john@example.com' };
    repository.findOne.mockResolvedValue(mockUser);

    const result = await service.findById(1);

    expect(result).toEqual(mockUser);
    expect(repository.findOne).toHaveBeenCalledWith({ where: { id: 1 } });
  });

  it('should throw if user not found', async () => {
    repository.findOne.mockResolvedValue(null);

    await expect(service.findById(999)).rejects.toThrow('User not found');
  });
});
```

## 2. 서비스 단위 테스트

### 의존성 Mock 패턴

```typescript
describe('AuthService', () => {
  let authService: AuthService;
  let userService: jest.Mocked<UserService>;
  let jwtService: jest.Mocked<JwtService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: UserService,
          useValue: {
            findByEmail: jest.fn(),
            create: jest.fn(),
          },
        },
        {
          provide: JwtService,
          useValue: {
            sign: jest.fn(),
            verify: jest.fn(),
          },
        },
      ],
    }).compile();

    authService = module.get(AuthService);
    userService = module.get(UserService);
    jwtService = module.get(JwtService);
  });

  describe('login', () => {
    it('should return access token for valid credentials', async () => {
      const user = { id: 1, email: 'test@test.com', password: 'hashed' };
      userService.findByEmail.mockResolvedValue(user);
      jwtService.sign.mockReturnValue('jwt-token');

      const result = await authService.login('test@test.com', 'password');

      expect(result).toEqual({ accessToken: 'jwt-token' });
    });

    it('should throw UnauthorizedException for invalid password', async () => {
      userService.findByEmail.mockResolvedValue(null);

      await expect(
        authService.login('test@test.com', 'wrong'),
      ).rejects.toThrow(UnauthorizedException);
    });
  });
});
```

## 3. 컨트롤러 단위 테스트

```typescript
import { UserController } from './user.controller';
import { UserService } from './user.service';

describe('UserController', () => {
  let controller: UserController;
  let service: jest.Mocked<UserService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [UserController],
      providers: [
        {
          provide: UserService,
          useValue: {
            findAll: jest.fn(),
            findById: jest.fn(),
            create: jest.fn(),
            update: jest.fn(),
            delete: jest.fn(),
          },
        },
      ],
    }).compile();

    controller = module.get(UserController);
    service = module.get(UserService);
  });

  describe('findAll', () => {
    it('should return array of users', async () => {
      const users = [{ id: 1, name: 'John' }];
      service.findAll.mockResolvedValue(users);

      const result = await controller.findAll();

      expect(result).toEqual(users);
    });
  });

  describe('create', () => {
    it('should create and return user', async () => {
      const dto = { name: 'John', email: 'john@test.com' };
      const created = { id: 1, ...dto };
      service.create.mockResolvedValue(created);

      const result = await controller.create(dto);

      expect(result).toEqual(created);
      expect(service.create).toHaveBeenCalledWith(dto);
    });
  });
});
```

## 4. E2E 테스트

```typescript
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';

describe('UserController (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = module.createNestApplication();
    app.useGlobalPipes(new ValidationPipe()); // 실제 파이프 적용
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe('POST /users', () => {
    it('should create user', () => {
      return request(app.getHttpServer())
        .post('/users')
        .send({ name: 'John', email: 'john@test.com' })
        .expect(201)
        .expect((res) => {
          expect(res.body.id).toBeDefined();
          expect(res.body.name).toBe('John');
        });
    });

    it('should return 400 for invalid input', () => {
      return request(app.getHttpServer())
        .post('/users')
        .send({ name: '' }) // validation 실패
        .expect(400);
    });
  });

  describe('GET /users/:id', () => {
    it('should return user', async () => {
      // 먼저 생성
      const { body: created } = await request(app.getHttpServer())
        .post('/users')
        .send({ name: 'John', email: 'john@test.com' });

      // 조회
      return request(app.getHttpServer())
        .get(`/users/${created.id}`)
        .expect(200)
        .expect((res) => {
          expect(res.body.name).toBe('John');
        });
    });

    it('should return 404 for non-existent user', () => {
      return request(app.getHttpServer())
        .get('/users/99999')
        .expect(404);
    });
  });
});
```

## 5. Guard / Interceptor 테스트

### Guard 테스트

```typescript
describe('AuthGuard', () => {
  let guard: AuthGuard;
  let jwtService: jest.Mocked<JwtService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        AuthGuard,
        { provide: JwtService, useValue: { verify: jest.fn() } },
      ],
    }).compile();

    guard = module.get(AuthGuard);
    jwtService = module.get(JwtService);
  });

  it('should allow valid token', () => {
    const context = createMockExecutionContext({
      headers: { authorization: 'Bearer valid-token' },
    });
    jwtService.verify.mockReturnValue({ userId: 1 });

    expect(guard.canActivate(context)).toBe(true);
  });

  it('should reject missing token', () => {
    const context = createMockExecutionContext({ headers: {} });

    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });
});
```

## 6. TypeORM 테스트 패턴

### Repository Mock

```typescript
const mockRepository = {
  find: jest.fn(),
  findOne: jest.fn(),
  save: jest.fn(),
  create: jest.fn(),
  update: jest.fn(),
  delete: jest.fn(),
  createQueryBuilder: jest.fn().mockReturnValue({
    where: jest.fn().mockReturnThis(),
    andWhere: jest.fn().mockReturnThis(),
    orderBy: jest.fn().mockReturnThis(),
    skip: jest.fn().mockReturnThis(),
    take: jest.fn().mockReturnThis(),
    getManyAndCount: jest.fn(),
    getOne: jest.fn(),
  }),
};

// 등록
{
  provide: getRepositoryToken(User),
  useValue: mockRepository,
}
```

## 7. 테스트 실행 설정

```jsonc
// package.json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:cov": "jest --coverage",
    "test:debug": "node --inspect-brk -r tsconfig-paths/register -r ts-node/register node_modules/.bin/jest --runInBand",
    "test:e2e": "jest --config ./test/jest-e2e.json"
  }
}
```

```typescript
// test/jest-e2e.json
{
  "moduleFileExtensions": ["js", "json", "ts"],
  "rootDir": ".",
  "testEnvironment": "node",
  "testRegex": ".e2e-spec.ts$",
  "transform": {
    "^.+\\.(t|j)s$": "ts-jest"
  },
  "moduleNameMapper": {
    "^@/(.*)$": "<rootDir>/../src/$1"
  }
}
```
