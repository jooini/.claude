# 보안 리뷰

> 참조 링크: https://owasp.org/www-project-top-ten/, https://cheatsheetseries.owasp.org/

---

## 개요

보안 리뷰는 코드 리뷰에서 가장 높은 우선순위(P0)를 가진다. OWASP Top 10을 기반으로 Injection, XSS, CSRF, 인증/인가 우회, 시크릿 노출 등 주요 보안 취약점을 탐지하는 리뷰 기법을 다룬다.

## 1. SQL Injection

### 취약 패턴

```typescript
// ❌ 문자열 보간으로 쿼리 생성
async function findUser(email: string): Promise<User> {
  return await dataSource.query(`SELECT * FROM users WHERE email = '${email}'`);
  // email에 "'; DROP TABLE users; --" 입력 가능
}

// ❌ TypeORM에서도 raw query 사용 시 취약
const users = await repo.query(`SELECT * FROM users WHERE name LIKE '%${search}%'`);

// ✅ 파라미터 바인딩 사용
async function findUser(email: string): Promise<User> {
  return await dataSource.query('SELECT * FROM users WHERE email = ?', [email]);
}

// ✅ QueryBuilder 사용
const users = await repo
  .createQueryBuilder('user')
  .where('user.name LIKE :search', { search: `%${search}%` })
  .getMany();
```

### 리뷰 포인트

- [ ] raw query에 문자열 보간이 사용되지 않는가?
- [ ] QueryBuilder 사용 시 파라미터 바인딩을 사용하는가?
- [ ] LIKE 쿼리에서 와일드카드 이스케이프를 하는가?
- [ ] ORDER BY 절에 동적 컬럼명이 화이트리스트 검증되는가?

## 2. XSS (Cross-Site Scripting)

### Stored XSS

```typescript
// ❌ 사용자 입력을 그대로 저장/출력
app.post('/comments', async (req, res) => {
  const { body } = req.body; // body에 <script>alert('xss')</script> 가능
  await commentRepo.save({ body, userId: req.user.id });
});

// ❌ React에서 dangerouslySetInnerHTML 사용
function Comment({ body }: { body: string }) {
  return <div dangerouslySetInnerHTML={{ __html: body }} />;
}

// ✅ 입력 검증 + 출력 이스케이프
import DOMPurify from 'dompurify';

app.post('/comments', async (req, res) => {
  const sanitized = DOMPurify.sanitize(req.body.body);
  await commentRepo.save({ body: sanitized, userId: req.user.id });
});

// ✅ React는 기본적으로 이스케이프하므로 텍스트로 렌더링
function Comment({ body }: { body: string }) {
  return <div>{body}</div>; // 자동 이스케이프
}
```

### URL 기반 XSS

```typescript
// ❌ 사용자 입력을 href에 직접 사용
function UserLink({ url }: { url: string }) {
  return <a href={url}>Link</a>; // javascript:alert('xss') 가능
}

// ✅ 프로토콜 화이트리스트 검증
function UserLink({ url }: { url: string }) {
  const isAllowed = /^https?:\/\//i.test(url);
  return isAllowed ? <a href={url}>Link</a> : <span>Invalid URL</span>;
}
```

## 3. CSRF (Cross-Site Request Forgery)

```typescript
// ❌ 상태 변경 API에 CSRF 보호 없음
app.post('/transfer', async (req, res) => {
  const { toAccount, amount } = req.body;
  await transferService.execute(req.user.id, toAccount, amount);
  // 공격자 사이트에서 폼 자동 제출로 호출 가능
});

// ✅ CSRF 토큰 검증 (NestJS)
import { CsrfGuard } from './guards/csrf.guard';

@UseGuards(CsrfGuard)
@Post('transfer')
async transfer(@Body() dto: TransferDto, @Req() req: Request) {
  return this.transferService.execute(req.user.id, dto.toAccount, dto.amount);
}

// ✅ SameSite 쿠키 설정
app.use(session({
  cookie: {
    sameSite: 'strict', // 또는 'lax'
    httpOnly: true,
    secure: true,
  },
}));
```

## 4. 인증/인가 우회

### 인증 우회

```typescript
// ❌ JWT 검증 없이 페이로드 사용
function getUserFromToken(token: string): JwtPayload {
  const decoded = jwt.decode(token); // decode는 서명 검증 안 함!
  return decoded as JwtPayload;
}

// ✅ 서명 검증 포함
function getUserFromToken(token: string): JwtPayload {
  const decoded = jwt.verify(token, process.env.JWT_SECRET); // 서명 검증
  return decoded as JwtPayload;
}
```

### 인가 누락

```typescript
// ❌ 인가 검사 없이 리소스 접근
@Get(':id')
async getOrder(@Param('id') id: string) {
  return this.orderRepo.findOneOrFail({ where: { id } });
  // 누구나 다른 사용자의 주문을 조회할 수 있음 (IDOR)
}

// ✅ 소유권 검증
@Get(':id')
async getOrder(@Param('id') id: string, @CurrentUser() user: User) {
  const order = await this.orderRepo.findOneOrFail({ where: { id } });
  if (order.userId !== user.id && user.role !== 'admin') {
    throw new ForbiddenException('Access denied');
  }
  return order;
}
```

### 권한 상승 방지

```typescript
// ❌ 사용자가 자신의 role을 변경할 수 있음
@Patch('profile')
async updateProfile(@Body() dto: UpdateProfileDto) {
  // dto에 { role: 'admin' } 포함 가능
  return this.userRepo.update(userId, dto);
}

// ✅ 허용 필드만 명시적으로 추출
@Patch('profile')
async updateProfile(@Body() dto: UpdateProfileDto, @CurrentUser() user: User) {
  const { name, email, avatar } = dto; // role 같은 민감 필드 제외
  return this.userRepo.update(user.id, { name, email, avatar });
}
```

## 5. 시크릿 노출

```typescript
// ❌ 코드에 시크릿 하드코딩
const API_KEY = 'sk-1234567890abcdef';
const DB_PASSWORD = 'super-secret-password';

// ❌ 에러 응답에 내부 정보 노출
catch (error) {
  res.status(500).json({
    message: error.message,
    stack: error.stack,        // 스택 트레이스 노출
    query: error.query,        // SQL 쿼리 노출
  });
}

// ❌ 로그에 민감 정보 출력
logger.info(`User login: ${email}, password: ${password}`);

// ✅ 환경 변수 사용
const API_KEY = process.env.API_KEY;

// ✅ 에러 응답 정규화
catch (error) {
  logger.error('Internal error', { error, requestId: req.id }); // 서버 로그에만
  res.status(500).json({
    message: 'Internal server error',
    requestId: req.id,          // 추적용 ID만 제공
  });
}
```

### 시크릿 탐지 체크리스트

- [ ] API 키, 비밀번호, 토큰이 코드에 하드코딩되지 않았는가?
- [ ] `.env` 파일이 `.gitignore`에 포함되어 있는가?
- [ ] 에러 응답에 스택 트레이스, 쿼리, 내부 경로가 노출되지 않는가?
- [ ] 로그에 비밀번호, 토큰, 카드번호 등이 출력되지 않는가?
- [ ] JWT 시크릿이 충분히 긴가? (최소 256비트)

## 6. OWASP Top 10 리뷰 매핑

### A01: Broken Access Control

```typescript
// 리뷰 포인트
// - 모든 API 엔드포인트에 인증 가드가 적용되어 있는가?
// - IDOR(Insecure Direct Object Reference) 취약점이 없는가?
// - CORS 설정이 적절한가?
// - 디렉토리 트래버설 가능성이 없는가?

// ❌ 파일 경로에 사용자 입력 직접 사용
const filePath = path.join('/uploads', req.params.filename);
// ../../../etc/passwd 접근 가능

// ✅ 경로 정규화 후 검증
const filePath = path.resolve('/uploads', req.params.filename);
if (!filePath.startsWith('/uploads/')) {
  throw new ForbiddenException('Invalid file path');
}
```

### A03: Injection

```typescript
// SQL Injection 외에도 검사해야 할 Injection 유형
// - NoSQL Injection: MongoDB 쿼리 객체에 $gt, $ne 등 연산자 주입
// - Command Injection: child_process.exec에 사용자 입력

// ❌ Command Injection
import { exec } from 'child_process';
exec(`convert ${inputFile} ${outputFile}`); // inputFile에 "; rm -rf /" 가능

// ✅ execFile 사용 (셸 해석 없음)
import { execFile } from 'child_process';
execFile('convert', [inputFile, outputFile]);
```

### A07: Identification and Authentication Failures

```typescript
// ❌ 비밀번호 평문 저장
await userRepo.save({ email, password: dto.password });

// ✅ bcrypt로 해싱
import * as bcrypt from 'bcrypt';

const hashedPassword = await bcrypt.hash(dto.password, 12); // salt rounds 12 이상
await userRepo.save({ email, password: hashedPassword });

// ✅ 비밀번호 비교
const isMatch = await bcrypt.compare(inputPassword, user.password);
```

## 7. 보안 리뷰 종합 체크리스트

- [ ] 모든 사용자 입력이 검증/살균(sanitize)되는가?
- [ ] SQL 쿼리에 파라미터 바인딩을 사용하는가?
- [ ] XSS 방지를 위한 출력 이스케이프가 적용되는가?
- [ ] 인증이 필요한 모든 엔드포인트에 가드가 적용되는가?
- [ ] 리소스 접근 시 소유권/권한 검증이 있는가?
- [ ] 시크릿이 코드나 로그에 노출되지 않는가?
- [ ] 비밀번호가 해싱되어 저장되는가?
- [ ] CORS, CSP 등 보안 헤더가 설정되어 있는가?
- [ ] 파일 업로드 시 타입/크기 제한이 있는가?
- [ ] Rate limiting이 적용되어 있는가?
