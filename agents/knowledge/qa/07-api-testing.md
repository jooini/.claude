# API Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/api-testing

---

## 1. API 테스트 범위

```
기능 테스트    — 올바른 요청에 올바른 응답
부정 테스트    — 잘못된 요청에 올바른 에러
인증/인가     — 권한 없는 접근 차단
계약 테스트   — API 스펙과 실제 동작 일치
성능 테스트   — 응답 시간, 동시 요청 처리
```

---

## 2. Supertest (NestJS)

```ts
// users.api.spec.ts
import * as request from 'supertest'

describe('Users API', () => {
  let app: INestApplication
  let authToken: string

  beforeAll(async () => {
    app = await createTestApp()

    // 테스트용 토큰
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email: 'admin@test.com', password: 'AdminPass1!' })

    authToken = res.body.data.accessToken
  })

  afterAll(() => app.close())

  // 성공 케이스
  describe('GET /users', () => {
    it('200 — 목록 반환', async () => {
      const res = await request(app.getHttpServer())
        .get('/users')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200)

      expect(res.body.data).toBeInstanceOf(Array)
      expect(res.body.meta).toMatchObject({
        total: expect.any(Number),
        page: 1,
        limit: expect.any(Number),
      })
    })

    it('200 — 검색 필터 동작', async () => {
      const res = await request(app.getHttpServer())
        .get('/users?search=홍길동')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(200)

      res.body.data.forEach((user: any) => {
        expect(user.name).toContain('홍길동')
      })
    })
  })

  // 에러 케이스
  describe('POST /users — 에러 케이스', () => {
    it('400 — 필수 필드 누락', async () => {
      const res = await request(app.getHttpServer())
        .post('/users')
        .send({ email: 'test@test.com' })  // name, password 누락
        .expect(400)

      expect(res.body.error.code).toBe('VALIDATION_ERROR')
      expect(res.body.error.details).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ field: 'name' }),
          expect.objectContaining({ field: 'password' }),
        ])
      )
    })

    it('401 — 인증 없이 접근', () => {
      return request(app.getHttpServer()).get('/users').expect(401)
    })

    it('403 — 권한 없는 접근', async () => {
      // 일반 유저 토큰
      const userRes = await request(app.getHttpServer())
        .post('/auth/login')
        .send({ email: 'user@test.com', password: 'UserPass1!' })
      const userToken = userRes.body.data.accessToken

      await request(app.getHttpServer())
        .delete('/users/some-id')
        .set('Authorization', `Bearer ${userToken}`)
        .expect(403)
    })
  })
})
```

---

## 3. 응답 스키마 검증

```ts
import { z } from 'zod'

// 응답 스키마 정의
const UserResponseSchema = z.object({
  id:    z.string().uuid(),
  email: z.string().email(),
  name:  z.string(),
  status: z.enum(['active', 'inactive']),
  createdAt: z.string().datetime(),
})

const PaginatedUsersSchema = z.object({
  data: z.array(UserResponseSchema),
  meta: z.object({
    total:      z.number(),
    page:       z.number(),
    limit:      z.number(),
    totalPages: z.number(),
  }),
})

it('응답 스키마 일치', async () => {
  const res = await request(app.getHttpServer())
    .get('/users')
    .set('Authorization', `Bearer ${authToken}`)
    .expect(200)

  // Zod로 런타임 스키마 검증
  const parsed = PaginatedUsersSchema.safeParse(res.body)
  expect(parsed.success).toBe(true)
  if (!parsed.success) console.error(parsed.error.issues)
})
```

---

## 4. Postman / Newman (수동 + CI)

```json
// postman/collection.json 구조
{
  "info": { "name": "API Test Suite" },
  "item": [
    {
      "name": "Auth",
      "item": [
        {
          "name": "Login",
          "request": {
            "method": "POST",
            "url": "{{base_url}}/auth/login",
            "body": {
              "email": "{{test_email}}",
              "password": "{{test_password}}"
            }
          },
          "event": [{
            "listen": "test",
            "script": {
              "exec": [
                "pm.test('Status 200', () => pm.response.to.have.status(200));",
                "pm.test('Has access token', () => {",
                "  const json = pm.response.json();",
                "  pm.expect(json.data.accessToken).to.be.a('string');",
                "  pm.environment.set('access_token', json.data.accessToken);",
                "});"
              ]
            }
          }]
        }
      ]
    }
  ]
}
```

```bash
# Newman으로 CI 실행
npx newman run postman/collection.json \
  --environment postman/staging.env.json \
  --reporters cli,junit \
  --reporter-junit-export results/newman.xml
```

---

## 5. Contract Testing (Pact)

소비자-제공자 간 API 계약 테스트.

```ts
// 소비자 측 (FE)
describe('Users API Contract', () => {
  const provider = new PactV3({
    consumer: 'frontend',
    provider: 'user-service',
  })

  it('GET /users/:id 계약', async () => {
    await provider
      .given('user exists with id 1')
      .uponReceiving('GET user by id')
      .withRequest({ method: 'GET', path: '/users/1' })
      .willRespondWith({
        status: 200,
        body: {
          id: '1',
          name: like('홍길동'),
          email: like('hong@example.com'),
        },
      })
      .executeTest(async (mockServer) => {
        const user = await fetchUser(mockServer.url, '1')
        expect(user.name).toBeDefined()
      })
  })
})
```

---

## 6. 보안 관련 API 테스트

```ts
describe('API 보안 테스트', () => {
  it('SQL Injection 방어', async () => {
    const res = await request(app.getHttpServer())
      .get("/users?search=' OR '1'='1")
      .set('Authorization', `Bearer ${authToken}`)

    expect(res.status).toBe(200)
    // 정상 응답 — SQL 인젝션으로 모든 데이터 노출 안 됨
    expect(res.body.data.length).toBeLessThan(100)
  })

  it('다른 사용자 데이터 접근 불가', async () => {
    const otherUserId = 'other-user-uuid'
    await request(app.getHttpServer())
      .patch(`/users/${otherUserId}`)
      .set('Authorization', `Bearer ${authToken}`)
      .send({ name: '해킹' })
      .expect(403)
  })

  it('만료된 토큰 거부', async () => {
    const expiredToken = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMiLCJleHAiOjF9.invalid'
    await request(app.getHttpServer())
      .get('/users')
      .set('Authorization', `Bearer ${expiredToken}`)
      .expect(401)
  })
})
```

---

## 7. 안티패턴

- **행복 경로만 테스트**: 에러/보안/경계값 반드시 포함
- **환경 하드코딩**: 환경 변수로 base URL, 토큰 관리
- **테스트 순서 의존**: 각 테스트는 독립 실행 가능해야
- **응답 코드만 검증**: body 구조, 데이터 정확성도 검증
- **느린 수동 테스트**: 반복 케이스는 자동화
