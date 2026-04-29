# Testing

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. 테스트 도구

```
PHPUnit          — 표준 테스트 프레임워크
CI4 TestCase     — CodeIgniter 4 통합 테스트 지원
Mockery          — Mock 라이브러리
Faker            — 테스트 데이터 생성
```

---

## 2. PHPUnit 설정

```xml
<!-- phpunit.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<phpunit bootstrap="vendor/codeigniter4/framework/system/Test/bootstrap.php"
         colors="true"
         stopOnFailure="false">
    <testsuites>
        <testsuite name="Unit">
            <directory>tests/Unit</directory>
        </testsuite>
        <testsuite name="Feature">
            <directory>tests/Feature</directory>
        </testsuite>
    </testsuites>
    <php>
        <env name="CI_ENVIRONMENT" value="testing"/>
        <env name="database.tests.DBDriver" value="SQLite3"/>
        <env name="database.tests.database" value=":memory:"/>
    </php>
</phpunit>
```

---

## 3. 단위 테스트

```php
// tests/Unit/Services/UserServiceTest.php
namespace Tests\Unit\Services;

use App\Services\UserService;
use App\Models\UserModel;
use App\Entities\User;
use App\Exceptions\NotFoundException;
use App\Exceptions\ConflictException;
use CodeIgniter\Test\CIUnitTestCase;
use Mockery;

class UserServiceTest extends CIUnitTestCase
{
    private UserService $service;
    private $userModel;

    protected function setUp(): void
    {
        parent::setUp();
        $this->userModel = Mockery::mock(UserModel::class);
        $this->service = new UserService($this->userModel);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function testGetUser_존재하는_유저(): void
    {
        $user = new User(['id' => 1, 'email' => 'test@test.com', 'name' => 'Test']);

        $this->userModel
            ->shouldReceive('find')
            ->with(1)
            ->once()
            ->andReturn($user);

        $result = $this->service->getUser(1);

        $this->assertInstanceOf(User::class, $result);
        $this->assertEquals('test@test.com', $result->email);
    }

    public function testGetUser_존재하지_않는_유저(): void
    {
        $this->userModel
            ->shouldReceive('find')
            ->with(999)
            ->once()
            ->andReturn(null);

        $this->expectException(NotFoundException::class);
        $this->service->getUser(999);
    }

    public function testCreateUser_이메일_중복(): void
    {
        $existing = new User(['id' => 1, 'email' => 'dup@test.com']);

        $this->userModel
            ->shouldReceive('where->first')
            ->once()
            ->andReturn($existing);

        $this->expectException(ConflictException::class);
        $this->service->createUser(['email' => 'dup@test.com', 'name' => 'Test', 'password' => 'pass1234']);
    }
}
```

---

## 4. 통합 테스트 (CI4 Feature Test)

```php
// tests/Feature/Api/UserApiTest.php
namespace Tests\Feature\Api;

use CodeIgniter\Test\CIUnitTestCase;
use CodeIgniter\Test\FeatureTestTrait;
use CodeIgniter\Test\DatabaseTestTrait;

class UserApiTest extends CIUnitTestCase
{
    use FeatureTestTrait;
    use DatabaseTestTrait;

    protected $migrateOnce = true;
    protected $seedOnce = false;
    protected $seed = 'Tests\Support\Seeds\UserSeeder';

    // DB 그룹 (테스트용)
    protected $DBGroup = 'tests';

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        $this->token = $this->getTestToken();
    }

    public function testListUsers_정상(): void
    {
        $result = $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
        ])->get('api/v1/users?page=1&size=10');

        $result->assertStatus(200);
        $result->assertJSONFragment(['pagination' => ['page' => 1]]);

        $json = json_decode($result->getJSON(), true);
        $this->assertArrayHasKey('data', $json);
        $this->assertArrayHasKey('pagination', $json);
    }

    public function testCreateUser_정상(): void
    {
        $result = $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Content-Type' => 'application/json',
        ])->post('api/v1/users', [
            'email' => 'newuser@test.com',
            'name' => 'New User',
            'password' => 'Test1234!',
        ]);

        $result->assertStatus(201);
        $result->assertJSONFragment(['email' => 'newuser@test.com']);

        // DB 확인
        $this->seeInDatabase('users', ['email' => 'newuser@test.com']);
    }

    public function testCreateUser_이메일_중복(): void
    {
        // Seeder에서 이미 존재하는 이메일
        $result = $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Content-Type' => 'application/json',
        ])->post('api/v1/users', [
            'email' => 'admin@test.com',
            'name' => 'Duplicate',
            'password' => 'Test1234!',
        ]);

        $result->assertStatus(409);
    }

    public function testCreateUser_유효성검사_실패(): void
    {
        $result = $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Content-Type' => 'application/json',
        ])->post('api/v1/users', [
            'email' => 'invalid-email',
            'name' => '',
        ]);

        $result->assertStatus(422);
        $result->assertJSONFragment(['title' => 'Validation Failed']);
    }

    public function testListUsers_인증없이_401(): void
    {
        $result = $this->get('api/v1/users');
        $result->assertStatus(401);
    }

    private function getTestToken(): string
    {
        return service('authService')->generateTokens([
            'id' => 1,
            'email' => 'admin@test.com',
            'role' => 'admin',
        ])['access_token'];
    }
}
```

---

## 5. DB 테스트 헬퍼

```php
// CI4 DatabaseTestTrait 메서드

// 데이터 존재 확인
$this->seeInDatabase('users', ['email' => 'test@test.com']);
$this->dontSeeInDatabase('users', ['email' => 'deleted@test.com']);

// 레코드 수
$this->seeNumRecords(5, 'users', ['role' => 'admin']);

// 시드
$this->seed('UserSeeder');

// 테스트용 DB 트랜잭션 (각 테스트 후 롤백)
// CIUnitTestCase가 자동 처리
```

---

## 6. Mock / Stub

```php
// Mockery
use Mockery;

$mock = Mockery::mock(ExternalApiClient::class);
$mock->shouldReceive('fetchUser')
    ->with('user-123')
    ->once()
    ->andReturn(['id' => 'user-123', 'name' => 'Test']);

$mock->shouldReceive('fetchUser')
    ->with('invalid')
    ->once()
    ->andThrow(new \RuntimeException('API error'));

// PHPUnit Mock
$mock = $this->createMock(CacheService::class);
$mock->expects($this->once())
    ->method('get')
    ->with('key')
    ->willReturn('cached_value');

// CI4 서비스 Mock
$mockService = Mockery::mock(EmailService::class);
$mockService->shouldReceive('send')->once()->andReturn(true);
\Config\Services::injectMock('emailService', $mockService);
```

---

## 7. 테스트 데이터 (Faker)

```php
// tests/Support/Factories/UserFactory.php
use Faker\Factory;

class UserFactory
{
    private static $faker;

    public static function make(array $overrides = []): array
    {
        self::$faker ??= Factory::create('ko_KR');

        return array_merge([
            'email' => self::$faker->unique()->safeEmail(),
            'name' => self::$faker->name(),
            'password' => password_hash('Test1234!', PASSWORD_ARGON2ID),
            'role' => 'user',
            'is_active' => true,
            'created_at' => date('Y-m-d H:i:s'),
        ], $overrides);
    }

    public static function makeMany(int $count, array $overrides = []): array
    {
        return array_map(fn() => self::make($overrides), range(1, $count));
    }
}

// 사용
$userData = UserFactory::make(['role' => 'admin']);
$users = UserFactory::makeMany(10);
```

---

## 8. 테스트 실행

```bash
# 전체 테스트
vendor/bin/phpunit

# 특정 테스트 스위트
vendor/bin/phpunit --testsuite Unit
vendor/bin/phpunit --testsuite Feature

# 특정 파일/메서드
vendor/bin/phpunit tests/Unit/Services/UserServiceTest.php
vendor/bin/phpunit --filter testCreateUser_정상

# 커버리지
vendor/bin/phpunit --coverage-html coverage/

# CI4 spark 명령어
php spark test
php spark test --testsuite Unit
```
