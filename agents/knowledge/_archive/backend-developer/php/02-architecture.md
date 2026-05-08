# Architecture

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. 아키텍처 비교

```
CodeIgniter 3 (MVC):
  Controller → Model → Database
       ↓
     View (또는 JSON output)

CodeIgniter 4 (MVC + Service Layer 권장):
  Controller → Service → Model/Repository → Database
       ↓              ↓
  Response        Validation, Business Logic
```

---

## 2. 디렉토리 구조

### CodeIgniter 4

```
app/
├── Config/
│   ├── App.php
│   ├── Database.php
│   ├── Routes.php
│   ├── Filters.php
│   └── Services.php          # 서비스 등록
├── Controllers/
│   ├── BaseController.php
│   └── Api/
│       └── V1/
│           ├── UserController.php
│           └── AuthController.php
├── Models/
│   ├── UserModel.php          # CI4 Model (Active Record)
│   └── OrderModel.php
├── Services/                   # 비즈니스 로직 레이어
│   ├── UserService.php
│   ├── AuthService.php
│   └── OrderService.php
├── DTOs/                       # 요청/응답 DTO
│   ├── CreateUserRequest.php
│   └── UserResponse.php
├── Entities/                   # CI4 Entity 클래스
│   ├── User.php
│   └── Order.php
├── Filters/                    # HTTP 필터 (미들웨어)
│   ├── AuthFilter.php
│   ├── CorsFilter.php
│   └── RateLimitFilter.php
├── Libraries/                  # 커스텀 라이브러리
├── Helpers/                    # 헬퍼 함수
├── Database/
│   ├── Migrations/
│   └── Seeds/
└── Views/
```

### CodeIgniter 3

```
application/
├── config/
│   ├── autoload.php
│   ├── config.php
│   ├── database.php
│   ├── routes.php
│   └── hooks.php
├── controllers/
│   └── api/
│       └── v1/
│           ├── UserController.php
│           └── AuthController.php
├── models/
│   ├── User_model.php
│   └── Order_model.php
├── libraries/                  # 비즈니스 로직 (Service 역할)
│   ├── UserService.php
│   └── AuthService.php
├── helpers/
├── hooks/                      # pre/post 처리
├── views/
└── third_party/
```

---

## 3. Service Layer 패턴

### CodeIgniter 4

```php
// app/Config/Services.php
namespace Config;

use App\Services\UserService;
use App\Services\AuthService;
use CodeIgniter\Config\BaseService;

class Services extends BaseService
{
    public static function userService(bool $getShared = true): UserService
    {
        if ($getShared) {
            return static::getSharedInstance('userService');
        }
        return new UserService(
            model('UserModel'),
            service('authService'),
        );
    }

    public static function authService(bool $getShared = true): AuthService
    {
        if ($getShared) {
            return static::getSharedInstance('authService');
        }
        return new AuthService();
    }
}

// app/Services/UserService.php
namespace App\Services;

use App\Models\UserModel;
use App\Entities\User;

class UserService
{
    public function __construct(
        private UserModel $userModel,
        private AuthService $authService,
    ) {}

    public function createUser(array $data): User
    {
        $user = new User([
            'email' => $data['email'],
            'name' => $data['name'],
            'password' => password_hash($data['password'], PASSWORD_ARGON2ID),
        ]);

        $this->userModel->save($user);
        $user->id = $this->userModel->getInsertID();

        return $user;
    }

    public function getUser(int $id): ?User
    {
        return $this->userModel->find($id);
    }
}
```

### CodeIgniter 3

```php
// application/libraries/UserService.php
class UserService
{
    private $CI;

    public function __construct()
    {
        $this->CI =& get_instance();
        $this->CI->load->model('User_model');
    }

    public function create_user(array $data): array
    {
        $data['password'] = password_hash($data['password'], PASSWORD_ARGON2ID);
        $id = $this->CI->User_model->insert_user($data);
        return $this->CI->User_model->get_by_id($id);
    }

    public function get_user(int $id): ?array
    {
        return $this->CI->User_model->get_by_id($id);
    }
}

// Controller에서 사용
$this->load->library('UserService');
$user = $this->userservice->create_user($input);
```

---

## 4. Entity 클래스 (CI4)

```php
// app/Entities/User.php
namespace App\Entities;

use CodeIgniter\Entity\Entity;

class User extends Entity
{
    protected $casts = [
        'id' => 'integer',
        'is_active' => 'boolean',
        'metadata' => 'json-array',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    protected $dates = ['created_at', 'updated_at', 'deleted_at'];

    // password 자동 해시
    public function setPassword(string $password): self
    {
        $this->attributes['password'] = password_hash($password, PASSWORD_ARGON2ID);
        return $this;
    }

    // JSON 직렬화 시 password 제외
    public function toArray(bool $onlyChanged = false, bool $cast = true, bool $recursive = false): array
    {
        $data = parent::toArray($onlyChanged, $cast, $recursive);
        unset($data['password']);
        return $data;
    }
}
```

---

## 5. HTTP 필터 (미들웨어)

### CodeIgniter 4

```php
// app/Filters/AuthFilter.php
namespace App\Filters;

use CodeIgniter\Filters\FilterInterface;
use CodeIgniter\HTTP\RequestInterface;
use CodeIgniter\HTTP\ResponseInterface;

class AuthFilter implements FilterInterface
{
    public function before(RequestInterface $request, $arguments = null)
    {
        $token = $request->getHeaderLine('Authorization');
        if (!$token || !str_starts_with($token, 'Bearer ')) {
            return service('response')
                ->setStatusCode(401)
                ->setJSON(['status' => 401, 'title' => 'Unauthorized']);
        }

        $decoded = service('authService')->verifyToken(str_replace('Bearer ', '', $token));
        if (!$decoded) {
            return service('response')
                ->setStatusCode(401)
                ->setJSON(['status' => 401, 'title' => 'Invalid Token']);
        }

        $request->user = $decoded;
    }

    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null)
    {
        // 응답 후처리
    }
}

// app/Config/Filters.php
public array $aliases = [
    'auth' => \App\Filters\AuthFilter::class,
    'cors' => \App\Filters\CorsFilter::class,
    'ratelimit' => \App\Filters\RateLimitFilter::class,
];

public array $globals = [
    'before' => ['cors'],
];
```

### CodeIgniter 3 (Hooks)

```php
// application/config/hooks.php
$hook['post_controller_constructor'][] = [
    'class'    => 'AuthHook',
    'function' => 'verify_token',
    'filename' => 'AuthHook.php',
    'filepath' => 'hooks',
];

// application/hooks/AuthHook.php
class AuthHook
{
    public function verify_token()
    {
        $CI =& get_instance();
        $excluded = ['auth/login', 'auth/register', 'health'];

        if (in_array($CI->uri->uri_string(), $excluded)) {
            return;
        }

        $token = $CI->input->get_request_header('Authorization');
        if (!$token) {
            $CI->output
                ->set_status_header(401)
                ->set_content_type('application/json')
                ->set_output(json_encode(['status' => 401, 'title' => 'Unauthorized']))
                ->_display();
            exit;
        }
    }
}
```

---

## 6. 환경 설정

### CodeIgniter 4

```env
# .env
CI_ENVIRONMENT = production

database.default.hostname = localhost
database.default.database = myapp
database.default.username = dbuser
database.default.password = secret
database.default.DBDriver = MySQLi
database.default.port = 3306

app.baseURL = 'https://api.example.com'
```

### CodeIgniter 3

```php
// application/config/database.php
$active_group = 'default';
$db['default'] = [
    'hostname' => getenv('DB_HOST') ?: 'localhost',
    'username' => getenv('DB_USER') ?: 'root',
    'password' => getenv('DB_PASS') ?: '',
    'database' => getenv('DB_NAME') ?: 'myapp',
    'dbdriver' => 'mysqli',
];
```

---

## 7. 의존성 관리 (Composer)

```json
{
    "require": {
        "php": "^8.1",
        "codeigniter4/framework": "^4.4",
        "firebase/php-jwt": "^6.0",
        "predis/predis": "^2.0",
        "monolog/monolog": "^3.0"
    },
    "require-dev": {
        "phpunit/phpunit": "^10.0",
        "phpstan/phpstan": "^1.10",
        "squizlabs/php_codesniffer": "^3.7"
    }
}
```
