# Security

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. 인증 (JWT)

### CodeIgniter 4

```php
// composer require firebase/php-jwt

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

class AuthService
{
    private string $secret;
    private int $accessTtl = 3600;       // 1시간
    private int $refreshTtl = 604800;    // 7일

    public function __construct()
    {
        $this->secret = getenv('JWT_SECRET') ?: throw new \RuntimeException('JWT_SECRET not set');
    }

    public function generateTokens(array $user): array
    {
        $now = time();

        $accessPayload = [
            'sub' => $user['id'],
            'email' => $user['email'],
            'role' => $user['role'],
            'iat' => $now,
            'exp' => $now + $this->accessTtl,
            'type' => 'access',
        ];

        $refreshPayload = [
            'sub' => $user['id'],
            'iat' => $now,
            'exp' => $now + $this->refreshTtl,
            'type' => 'refresh',
        ];

        return [
            'access_token' => JWT::encode($accessPayload, $this->secret, 'HS256'),
            'refresh_token' => JWT::encode($refreshPayload, $this->secret, 'HS256'),
            'expires_in' => $this->accessTtl,
        ];
    }

    public function verifyToken(string $token, string $type = 'access'): ?object
    {
        try {
            $decoded = JWT::decode($token, new Key($this->secret, 'HS256'));
            if ($decoded->type !== $type) {
                return null;
            }
            return $decoded;
        } catch (\Exception $e) {
            return null;
        }
    }
}
```

### CodeIgniter 3

```php
// application/libraries/JwtAuth.php
class JwtAuth
{
    private $CI;
    private $secret;

    public function __construct()
    {
        $this->CI =& get_instance();
        $this->secret = getenv('JWT_SECRET');
    }

    public function generate_token(array $user): string
    {
        $payload = [
            'sub' => $user['id'],
            'email' => $user['email'],
            'role' => $user['role'],
            'iat' => time(),
            'exp' => time() + 3600,
        ];

        return \Firebase\JWT\JWT::encode($payload, $this->secret, 'HS256');
    }

    public function verify_token(string $token): ?object
    {
        try {
            return \Firebase\JWT\JWT::decode($token, new \Firebase\JWT\Key($this->secret, 'HS256'));
        } catch (\Exception $e) {
            return null;
        }
    }
}
```

---

## 2. 비밀번호 해싱

```php
// ✅ password_hash (PHP 내장 — Argon2id 권장)
$hash = password_hash($password, PASSWORD_ARGON2ID);

// 검증
if (password_verify($inputPassword, $storedHash)) {
    // 로그인 성공
}

// Rehash 필요 여부 확인 (알고리즘 업그레이드 시)
if (password_needs_rehash($storedHash, PASSWORD_ARGON2ID)) {
    $newHash = password_hash($inputPassword, PASSWORD_ARGON2ID);
    $userModel->update($userId, ['password' => $newHash]);
}

// ❌ 절대 사용 금지
md5($password);
sha1($password);
sha256($password);
```

---

## 3. CSRF 보호

### CodeIgniter 4

```php
// app/Config/Filters.php
public array $globals = [
    'before' => [
        'csrf' => ['except' => ['api/*']],  // API는 JWT로 보호
    ],
];

// app/Config/Security.php
public string $csrfProtection = 'session';  // 'cookie' or 'session'
public bool $csrfRegenerate = true;
public string $csrfTokenName = 'csrf_token';
public string $csrfHeaderName = 'X-CSRF-TOKEN';
```

### CodeIgniter 3

```php
// application/config/config.php
$config['csrf_protection'] = TRUE;
$config['csrf_token_name'] = 'csrf_token';
$config['csrf_expire'] = 7200;
$config['csrf_regenerate'] = TRUE;
$config['csrf_exclude_uris'] = ['api/.*'];
```

---

## 4. XSS 방지

```php
// CI4
$clean = esc($userInput);                    // HTML 이스케이프
$clean = esc($userInput, 'js');              // JS 이스케이프
$clean = esc($userInput, 'url');             // URL 이스케이프

// 요청에서 필터링
$name = $this->request->getVar('name', FILTER_SANITIZE_SPECIAL_CHARS);

// CI3
$clean = $this->security->xss_clean($input);
$clean = html_escape($input);

// ❌ 직접 출력 금지
echo $userInput;         // XSS 취약
echo esc($userInput);    // ✅ 안전
```

---

## 5. SQL Injection 방지

```php
// ✅ 파라미터 바인딩 (항상 사용)
// CI4
$db->query("SELECT * FROM users WHERE email = ?", [$email]);
$builder->where('email', $email);  // Query Builder도 자동 이스케이프

// CI3
$this->db->query("SELECT * FROM users WHERE email = ?", [$email]);
$this->db->where('email', $email);

// ❌ 절대 금지 — 문자열 연결
$db->query("SELECT * FROM users WHERE email = '$email'");  // SQL Injection!
```

---

## 6. CORS

### CodeIgniter 4

```php
// app/Filters/CorsFilter.php
class CorsFilter implements FilterInterface
{
    private array $allowedOrigins = [
        'https://app.example.com',
        'https://admin.example.com',
    ];

    public function before(RequestInterface $request, $arguments = null)
    {
        $origin = $request->getHeaderLine('Origin');

        if (!in_array($origin, $this->allowedOrigins)) {
            if ($request->getMethod() === 'options') {
                return service('response')->setStatusCode(204);
            }
            return;
        }

        $response = service('response');
        $response->setHeader('Access-Control-Allow-Origin', $origin);
        $response->setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
        $response->setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
        $response->setHeader('Access-Control-Max-Age', '86400');

        if ($request->getMethod() === 'options') {
            return $response->setStatusCode(204);
        }
    }

    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null) {}
}
```

---

## 7. Rate Limiting

### CodeIgniter 4

```php
// app/Filters/RateLimitFilter.php
class RateLimitFilter implements FilterInterface
{
    public function before(RequestInterface $request, $arguments = null)
    {
        $cache = \Config\Services::cache();
        $ip = $request->getIPAddress();
        $key = "ratelimit:{$ip}";

        $current = (int) $cache->get($key);

        if ($current >= 100) {  // 분당 100회
            return service('response')
                ->setStatusCode(429)
                ->setHeader('Retry-After', '60')
                ->setJSON([
                    'status' => 429,
                    'title' => 'Too Many Requests',
                    'detail' => 'Rate limit exceeded. Try again in 60 seconds.',
                ]);
        }

        if ($current === 0) {
            $cache->save($key, 1, 60);  // 60초 TTL
        } else {
            $cache->save($key, $current + 1, 60);
        }
    }

    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null) {}
}
```

---

## 8. Input Validation

### CodeIgniter 4

```php
// Controller에서
$rules = [
    'email'    => 'required|valid_email|max_length[255]',
    'name'     => 'required|min_length[2]|max_length[50]|alpha_numeric_space',
    'password' => 'required|min_length[8]|regex_match[/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/]',
    'age'      => 'permit_empty|integer|greater_than[0]|less_than[200]',
    'role'     => 'required|in_list[user,admin,manager]',
    'phone'    => 'permit_empty|regex_match[/^01[0-9]-?\d{3,4}-?\d{4}$/]',
];

$messages = [
    'password' => [
        'regex_match' => '비밀번호는 대소문자와 숫자를 포함해야 합니다.',
    ],
];

if (!$this->validate($rules, $messages)) {
    return $this->response->setStatusCode(422)->setJSON([
        'status' => 422,
        'errors' => $this->validator->getErrors(),
    ]);
}

// 검증 통과된 데이터만 사용
$validData = $this->validator->getValidated();
```

### CodeIgniter 3

```php
$this->form_validation->set_rules('email', 'Email', 'required|valid_email|max_length[255]');
$this->form_validation->set_rules('name', 'Name', 'required|min_length[2]|max_length[50]');
$this->form_validation->set_rules('password', 'Password', 'required|min_length[8]');

if ($this->form_validation->run() === FALSE) {
    $errors = $this->form_validation->error_array();
}
```

---

## 9. 보안 헤더

```php
// CI4 Filter
class SecurityHeadersFilter implements FilterInterface
{
    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null)
    {
        $response->setHeader('X-Content-Type-Options', 'nosniff');
        $response->setHeader('X-Frame-Options', 'DENY');
        $response->setHeader('X-XSS-Protection', '1; mode=block');
        $response->setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
        $response->setHeader('Content-Security-Policy', "default-src 'self'");
        $response->setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');

        return $response;
    }
}
```
