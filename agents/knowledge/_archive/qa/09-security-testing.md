# Security Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/security-testing

---

## 1. 보안 테스트 유형

```
SAST (Static Application Security Testing)
  코드 분석 — 빌드 전, 빠름
  도구: SonarQube, ESLint Security Plugin, Semgrep

DAST (Dynamic Application Security Testing)
  실행 중인 앱 분석 — 런타임 취약점
  도구: OWASP ZAP, Burp Suite

SCA (Software Composition Analysis)
  의존성 취약점 — npm audit, Snyk

Penetration Testing
  화이트햇 해커가 실제 공격 시도
  정기적 (분기 또는 연간)
```

---

## 2. OWASP Top 10 테스트 체크리스트

### A01. 접근 제어 취약점

```ts
describe('접근 제어', () => {
  it('인증 없이 보호된 리소스 접근 불가', async () => {
    await request(app.getHttpServer()).get('/api/users').expect(401)
  })

  it('다른 사용자 데이터 수정 불가', async () => {
    const { token: userAToken } = await loginAs('userA@test.com')
    const { id: userBId } = await getUser('userB@test.com')

    await request(app.getHttpServer())
      .patch(`/api/users/${userBId}`)
      .set('Authorization', `Bearer ${userAToken}`)
      .send({ name: '해킹시도' })
      .expect(403)
  })

  it('일반 유저가 관리자 API 호출 불가', async () => {
    const { token } = await loginAs('user@test.com')
    await request(app.getHttpServer())
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .expect(403)
  })
})
```

### A02. 암호화 실패

```ts
describe('암호화', () => {
  it('비밀번호가 평문으로 저장되지 않음', async () => {
    await createUser({ email: 'test@test.com', password: 'PlainPassword1!' })
    const dbUser = await userRepo.findByEmail('test@test.com')

    expect(dbUser.password).not.toBe('PlainPassword1!')
    expect(dbUser.password).toMatch(/^\$2[aby]\$/)  // bcrypt 해시 패턴
  })

  it('응답에 비밀번호 미포함', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/users/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200)

    expect(res.body.data).not.toHaveProperty('password')
  })
})
```

### A03. SQL Injection

```ts
describe('SQL Injection 방어', () => {
  const injectionPayloads = [
    "' OR '1'='1",
    "'; DROP TABLE users; --",
    "' UNION SELECT * FROM users --",
    "1; SELECT SLEEP(5) --",
  ]

  injectionPayloads.forEach(payload => {
    it(`SQL Injection 방어: ${payload.slice(0, 20)}...`, async () => {
      const res = await request(app.getHttpServer())
        .get(`/api/users?search=${encodeURIComponent(payload)}`)
        .set('Authorization', `Bearer ${token}`)

      // 정상 응답 (빈 결과 또는 에러 없이)
      expect([200, 400]).toContain(res.status)
      // 전체 데이터 노출 안 됨
      if (res.status === 200) {
        expect(res.body.data.length).toBeLessThan(100)
      }
    })
  })
})
```

### A07. 인증 실패

```ts
describe('인증 보안', () => {
  it('만료된 JWT 토큰 거부', async () => {
    const expiredToken = generateExpiredToken()
    await request(app.getHttpServer())
      .get('/api/users')
      .set('Authorization', `Bearer ${expiredToken}`)
      .expect(401)
  })

  it('변조된 JWT 토큰 거부', async () => {
    const [header, payload, sig] = validToken.split('.')
    const tamperedToken = `${header}.${payload}.invalidsignature`
    await request(app.getHttpServer())
      .get('/api/users')
      .set('Authorization', `Bearer ${tamperedToken}`)
      .expect(401)
  })

  it('브루트포스 방어 — 레이트 리밋', async () => {
    const attempts = Array(10).fill(null).map(() =>
      request(app.getHttpServer())
        .post('/api/auth/login')
        .send({ email: 'user@test.com', password: 'wrongpassword' })
    )
    const results = await Promise.all(attempts)
    const tooManyRequests = results.filter(r => r.status === 429)
    expect(tooManyRequests.length).toBeGreaterThan(0)
  })
})
```

---

## 3. SAST 도구 설정

```json
// .eslintrc — 보안 플러그인
{
  "plugins": ["security"],
  "extends": ["plugin:security/recommended"],
  "rules": {
    "security/detect-object-injection": "error",
    "security/detect-non-literal-regexp": "warn",
    "security/detect-unsafe-regex": "error",
    "security/detect-buffer-noassert": "error",
    "security/detect-eval-with-expression": "error"
  }
}
```

```yaml
# GitHub Actions — Snyk 의존성 스캔
- name: Run Snyk Security Scan
  uses: snyk/actions/node@master
  env:
    SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
  with:
    args: --severity-threshold=high
```

---

## 4. OWASP ZAP 자동화

```bash
# Docker로 ZAP 실행
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t https://staging.example.com \
  -r zap-report.html \
  -I  # informational 알림은 실패로 처리 안 함
```

---

## 5. 보안 테스트 체크리스트

```
인증/인가:
  [ ] 모든 API에 인증 필요 여부 확인
  [ ] 역할별 권한 분리 동작 확인
  [ ] 세션 만료/로그아웃 동작 확인

입력 검증:
  [ ] SQL Injection 페이로드 테스트
  [ ] XSS 페이로드 테스트
  [ ] 파일 업로드 타입/크기 제한 확인

데이터 보호:
  [ ] 비밀번호 해시 저장 확인
  [ ] 응답에 민감 정보 미포함 확인
  [ ] HTTPS 강제 확인

API 보안:
  [ ] 레이트 리밋 동작 확인
  [ ] CORS 설정 확인
  [ ] 보안 헤더 (CSP, HSTS 등) 확인
```

---

## 6. 안티패턴

- **보안 테스트를 릴리스 직전에만**: CI에 SAST 통합, 개발 중 상시 실행
- **의존성 업데이트 방치**: `npm audit` 정기 실행, Dependabot 설정
- **Happy Path 보안 테스트**: 경계값, 권한 우회 시나리오 필수
- **보안 테스트 결과 무시**: Critical/High는 반드시 수정 후 배포
