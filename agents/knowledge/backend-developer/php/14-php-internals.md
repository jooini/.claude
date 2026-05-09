# PHP Internals

> PHP 버전 — PHP 8.1+ / CodeIgniter 3 & 4

---

## 1. PHP 실행 모델

```
┌──────────────────────────────────────┐
│         PHP Execution Model          │
│                                      │
│  Request → PHP-FPM Worker → Process  │
│                                      │
│  1. 요청 수신                         │
│  2. 스크립트 파싱 (OPcache 히트 시 생략) │
│  3. 바이트코드 실행 (Zend Engine)      │
│  4. 응답 반환                         │
│  5. 메모리 해제 (Shared Nothing)       │
│                                      │
│  특징:                                │
│  - 요청마다 독립된 프로세스/메모리       │
│  - 글로벌 상태 없음 (Shared Nothing)    │
│  - 요청 종료 시 모든 메모리 자동 해제    │
│  - 메모리 누수 걱정 적음                │
└──────────────────────────────────────┘

PHP-FPM (FastCGI Process Manager):
  Master Process → Worker Process 1 (요청 처리)
                 → Worker Process 2
                 → Worker Process N

  각 Worker는 한 번에 하나의 요청만 처리 (동기/블로킹)
```

---

## 2. OPcache & JIT

```
소스코드 (.php)
    ↓ 파싱
AST (Abstract Syntax Tree)
    ↓ 컴파일
Opcodes (바이트코드)
    ↓ OPcache에 캐싱
    ↓ JIT 컴파일 (PHP 8.0+)
Machine Code (네이티브)

OPcache:
  - 바이트코드를 공유 메모리에 캐싱
  - 파싱/컴파일 단계 생략 → 2-3배 성능 향상
  - 프로덕션 필수

JIT (Just-In-Time):
  - 바이트코드 → 네이티브 코드 변환
  - CPU 집중 작업에서 효과적
  - I/O 바운드(웹 앱)에서는 효과 제한적
```

---

## 3. Zend Engine 메모리 관리

```
┌─────────────────────────────┐
│      Zend Memory Manager    │
│                             │
│  zval (Zend Value):         │
│    - 모든 PHP 변수의 내부 표현 │
│    - type + value + refcount │
│                             │
│  Reference Counting:        │
│    $a = "hello";  // refcount=1 │
│    $b = $a;       // refcount=2 (CoW) │
│    $b = "world";  // $a refcount=1, $b 새로 할당 │
│                             │
│  Copy-on-Write (CoW):       │
│    - 값 복사 시 실제 복사 지연  │
│    - 수정 시에만 실제 복사      │
│    - 배열도 CoW 적용           │
│                             │
│  Cycle Collector:           │
│    - 순환 참조 감지/해제       │
│    - gc_collect_cycles()     │
└─────────────────────────────┘
```

```php
// 메모리 사용량 확인
echo memory_get_usage(true);        // 할당된 메모리
echo memory_get_peak_usage(true);   // 최대 사용 메모리

// 메모리 제한
ini_set('memory_limit', '256M');

// 대용량 데이터 처리 — Generator 사용
function readLargeFile(string $path): \Generator
{
    $handle = fopen($path, 'r');
    while (($line = fgets($handle)) !== false) {
        yield trim($line);  // 한 줄씩 메모리에 로드
    }
    fclose($handle);
}

foreach (readLargeFile('/path/to/large.csv') as $line) {
    // 한 줄씩 처리 — 메모리 효율적
}
```

---

## 4. PHP 8.x 주요 기능

### PHP 8.0

```php
// Named Arguments
$user = createUser(name: 'Test', email: 'test@test.com');

// Match Expression
$status = match ($code) {
    200 => 'OK',
    404 => 'Not Found',
    500 => 'Server Error',
    default => 'Unknown',
};

// Nullsafe Operator
$country = $user?->getAddress()?->getCountry()?->getName();

// Union Types
function processInput(string|int $input): string|int { ... }

// Constructor Property Promotion
class User {
    public function __construct(
        public readonly int $id,
        public string $name,
        public string $email,
    ) {}
}
```

### PHP 8.1

```php
// Enums
enum UserRole: string
{
    case Admin = 'admin';
    case User = 'user';
    case Manager = 'manager';

    public function label(): string
    {
        return match ($this) {
            self::Admin => '관리자',
            self::User => '일반 사용자',
            self::Manager => '매니저',
        };
    }
}

// Fibers (비동기 프리미티브)
$fiber = new Fiber(function (): void {
    $value = Fiber::suspend('fiber started');
    echo "Resumed with: $value";
});

$result = $fiber->start();    // 'fiber started'
$fiber->resume('hello');       // 'Resumed with: hello'

// Readonly Properties
class Config {
    public function __construct(
        public readonly string $dbHost,
        public readonly int $dbPort,
    ) {}
}

// Intersection Types
function process(Countable&Iterator $collection): void { ... }

// First-class Callable Syntax
$fn = strlen(...);
$result = array_map(strlen(...), ['a', 'bb', 'ccc']);
```

### PHP 8.2

```php
// Readonly Classes
readonly class UserDTO
{
    public function __construct(
        public int $id,
        public string $email,
        public string $name,
    ) {}
}

// Disjunctive Normal Form Types
function process((Countable&Iterator)|null $input): void { ... }

// Constants in Traits
trait HasVersion {
    const VERSION = '1.0';
}
```

### PHP 8.3

```php
// Typed Class Constants
class Config {
    const string DB_HOST = 'localhost';
    const int DB_PORT = 3306;
}

// #[\Override] Attribute
class ChildService extends BaseService {
    #[\Override]
    public function process(): void { ... }  // 부모에 없으면 컴파일 에러
}

// json_validate()
if (json_validate($input)) {
    $data = json_decode($input, true);
}

// Dynamic class constant fetch
$name = 'DB_HOST';
$value = Config::{$name};  // Config::DB_HOST
```

---

## 5. 타입 시스템

```php
// Strict Types (파일 상단에 선언)
declare(strict_types=1);

// 매개변수/반환 타입
function createUser(string $email, string $name, ?string $phone = null): User { ... }

// 반환 타입: never (PHP 8.1+)
function throwError(string $message): never
{
    throw new \RuntimeException($message);
}

// 반환 타입: void
function logAction(string $action): void
{
    // 반환값 없음
}

// 타입 확인
if ($value instanceof User) { ... }
if (is_string($value)) { ... }
if (is_int($value)) { ... }

// PHPStan으로 정적 분석
// phpstan.neon
// level: 8 (최고 수준)
```

---

## 6. Autoloading (PSR-4)

```json
// composer.json
{
    "autoload": {
        "psr-4": {
            "App\\": "app/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "Tests\\": "tests/"
        }
    }
}
```

```php
// CI4는 PSR-4 자동 지원
// app/Config/Autoload.php
public $psr4 = [
    APP_NAMESPACE => APPPATH,
];

// CI3는 spl_autoload_register 또는 Composer autoload
require_once APPPATH . 'third_party/vendor/autoload.php';
```

---

## 7. 에러 처리 내부

```php
// PHP 에러 레벨
E_ERROR            // 치명적 (실행 중단)
E_WARNING          // 경고 (실행 계속)
E_NOTICE           // 알림 (사소한 문제)
E_DEPRECATED       // 폐기 예정 기능 사용

// 프로덕션 설정
ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', '/var/log/php/error.log');
error_reporting(E_ALL);

// 커스텀 에러 핸들러
set_error_handler(function (int $severity, string $message, string $file, int $line): bool {
    throw new \ErrorException($message, 0, $severity, $file, $line);
});

// 셧다운 함수 (fatal error 캐치)
register_shutdown_function(function (): void {
    $error = error_get_last();
    if ($error && in_array($error['type'], [E_ERROR, E_CORE_ERROR, E_COMPILE_ERROR])) {
        // 로깅, 알림 등
    }
});
```
