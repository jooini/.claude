# Caching

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/caching

---

## 1. 캐싱 계층

```
클라이언트 캐시 (브라우저)
  └── CDN/엣지 캐시
        └── API Gateway 캐시
              └── 애플리케이션 캐시 (Redis)
                    └── DB 쿼리 캐시 (pg buffer)
                          └── DB
```

각 계층에서 캐시 히트 시 하위 계층 호출 없음.

---

## 2. Redis 기본 설정 (NestJS)

```bash
npm install @nestjs/cache-manager cache-manager ioredis
```

```ts
// app.module.ts
import { CacheModule } from '@nestjs/cache-manager'
import { redisStore } from 'cache-manager-ioredis-yet'

CacheModule.registerAsync({
  isGlobal: true,
  inject: [ConfigService],
  useFactory: async (config: ConfigService) => ({
    store: await redisStore({
      host: config.get('REDIS_HOST'),
      port: config.get('REDIS_PORT'),
      password: config.get('REDIS_PASSWORD'),
      ttl: 300,  // 기본 TTL 5분
    }),
  }),
})
```

---

## 3. Cache-Aside 패턴 (Look-Aside)

가장 일반적인 패턴. 애플리케이션이 캐시 직접 관리.

```ts
@Injectable()
export class UsersService {
  constructor(
    private readonly cacheManager: Cache,
    private readonly usersRepo: UsersRepository,
  ) {}

  private cacheKey(id: string) { return `user:${id}` }

  async findById(id: string): Promise<User> {
    // 1. 캐시 조회
    const cached = await this.cacheManager.get<User>(this.cacheKey(id))
    if (cached) return cached

    // 2. DB 조회
    const user = await this.usersRepo.findById(id)
    if (!user) throw new NotFoundException()

    // 3. 캐시 저장
    await this.cacheManager.set(this.cacheKey(id), user, 300)
    return user
  }

  async update(id: string, dto: UpdateUserDto): Promise<User> {
    const user = await this.usersRepo.update(id, dto)
    // 캐시 무효화
    await this.cacheManager.del(this.cacheKey(id))
    return user
  }

  async delete(id: string): Promise<void> {
    await this.usersRepo.delete(id)
    await this.cacheManager.del(this.cacheKey(id))
  }
}
```

---

## 4. 데코레이터 캐싱

```ts
// @CacheKey + @CacheTTL 데코레이터
@Controller('configs')
@UseInterceptors(CacheInterceptor)  // 자동 캐싱
export class ConfigsController {
  @Get()
  @CacheKey('app:configs')
  @CacheTTL(3600)  // 1시간
  getConfigs() {
    return this.configsService.getAll()
  }
}

// 커스텀 캐시 데코레이터
function Cacheable(key: string, ttl = 300) {
  return function (target: unknown, propertyKey: string, descriptor: PropertyDescriptor) {
    const originalMethod = descriptor.value

    descriptor.value = async function (...args: unknown[]) {
      const cacheKey = `${key}:${JSON.stringify(args)}`
      const cached = await this.cacheManager.get(cacheKey)
      if (cached) return cached

      const result = await originalMethod.apply(this, args)
      await this.cacheManager.set(cacheKey, result, ttl)
      return result
    }
  }
}
```

---

## 5. 캐시 키 설계

```ts
// 계층적 키 구조
const cacheKeys = {
  user:        (id: string) => `user:${id}`,
  userProfile: (id: string) => `user:${id}:profile`,
  users:       (query: string) => `users:list:${query}`,
  product:     (id: string) => `product:${id}`,
  products:    (category: string) => `products:${category}`,
}

// 패턴 삭제 — 특정 프리픽스 모두 삭제
async function invalidateUserCache(userId: string) {
  const redis = this.cacheManager.store.client
  const keys = await redis.keys(`user:${userId}:*`)
  if (keys.length > 0) {
    await redis.del(...keys)
  }
}
```

---

## 6. 캐시 무효화 전략

```ts
// 1. TTL 만료 — 가장 단순
await this.cacheManager.set(key, value, 300)

// 2. 이벤트 기반 무효화
@OnEvent('user.updated')
async onUserUpdated(event: UserUpdatedEvent) {
  await this.cacheManager.del(`user:${event.userId}`)
}

// 3. Write-Through — 쓰기 시 캐시도 함께 업데이트
async update(id: string, dto: UpdateUserDto): Promise<User> {
  const user = await this.usersRepo.update(id, dto)
  await this.cacheManager.set(`user:${id}`, user, 300)  // 삭제 대신 업데이트
  return user
}

// 4. 버전 기반 — 캐시 키에 버전 포함
const version = await this.redis.get('user:version')
const key = `user:${id}:v${version}`
```

---

## 7. Redis 고급 활용

```ts
// Rate Limiting — 레이트 리밋
@Injectable()
export class RateLimiterService {
  constructor(@InjectRedis() private redis: Redis) {}

  async isAllowed(key: string, limit: number, windowSec: number): Promise<boolean> {
    const current = await this.redis.incr(key)
    if (current === 1) {
      await this.redis.expire(key, windowSec)
    }
    return current <= limit
  }
}

// Distributed Lock — 분산 락
async function withLock<T>(key: string, ttl: number, fn: () => Promise<T>): Promise<T> {
  const lockKey = `lock:${key}`
  const acquired = await this.redis.set(lockKey, '1', 'NX', 'EX', ttl)
  if (!acquired) throw new ConflictException('다른 프로세스가 처리 중입니다')

  try {
    return await fn()
  } finally {
    await this.redis.del(lockKey)
  }
}

// Pub/Sub — 서버 간 메시지
this.redis.publish('user:updated', JSON.stringify({ userId }))
this.redis.subscribe('user:updated', (message) => {
  const { userId } = JSON.parse(message)
  // 이 서버의 로컬 캐시 무효화
})
```

---

## 8. 캐시 미스 대응 — Cache Stampede 방지

```ts
// 동시에 많은 요청이 캐시 미스 → DB 폭주
// 해결: 한 요청만 DB 조회, 나머지는 대기

async function getWithLock<T>(key: string, fn: () => Promise<T>): Promise<T> {
  const cached = await this.redis.get(key)
  if (cached) return JSON.parse(cached)

  const lockKey = `lock:${key}`
  const acquired = await this.redis.set(lockKey, '1', 'NX', 'EX', 5)

  if (!acquired) {
    // 락 획득 실패 → 잠시 후 재시도 (캐시가 채워질 때까지)
    await sleep(100)
    return this.getWithLock(key, fn)
  }

  try {
    const result = await fn()
    await this.redis.setex(key, 300, JSON.stringify(result))
    return result
  } finally {
    await this.redis.del(lockKey)
  }
}
```

---

## 9. 안티패턴

- **모든 것을 캐시**: 자주 변경되는 데이터는 무효화 비용이 더 큼
- **캐시 키 충돌**: 서비스/환경별 prefix 필수 (`prod:user:123`)
- **TTL 없는 캐시**: 메모리 무한 증가
- **캐시 직접 데이터 소스화**: 캐시 누락/만료 시 fallback 필수
- **분산 환경에서 로컬 메모리 캐시**: 서버마다 다른 캐시 → Redis 사용
