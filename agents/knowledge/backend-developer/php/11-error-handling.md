# Error Handling

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. 예외 계층 구조

```php
// app/Exceptions/AppException.php (Base)
namespace App\Exceptions;

abstract class AppException extends \RuntimeException
{
    protected int $statusCode = 500;
    protected string $errorType = 'internal-error';

    public function __construct(
        string $message = '',
        int $code = 0,
        ?\Throwable $previous = null,
    ) {
        parent::__construct($message, $code, $previous);
    }

    public function getStatusCode(): int
    {
        return $this->statusCode;
    }

    public function getErrorType(): string
    {
        return $this->errorType;
    }

    public function toArray(): array
    {
        return [
            'type' => "https://api.example.com/errors/{$this->errorType}",
            'title' => $this->getTitle(),
            'status' => $this->statusCode,
            'detail' => $this->getMessage(),
        ];
    }

    abstract protected function getTitle(): string;
}

// 404
class NotFoundException extends AppException
{
    protected int $statusCode = 404;
    protected string $errorType = 'not-found';
    protected function getTitle(): string { return 'Resource Not Found'; }
}

// 400
class BadRequestException extends AppException
{
    protected int $statusCode = 400;
    protected string $errorType = 'bad-request';
    protected function getTitle(): string { return 'Bad Request'; }
}

// 401
class UnauthorizedException extends AppException
{
    protected int $statusCode = 401;
    protected string $errorType = 'unauthorized';
    protected function getTitle(): string { return 'Unauthorized'; }
}

// 403
class ForbiddenException extends AppException
{
    protected int $statusCode = 403;
    protected string $errorType = 'forbidden';
    protected function getTitle(): string { return 'Forbidden'; }
}

// 409
class ConflictException extends AppException
{
    protected int $statusCode = 409;
    protected string $errorType = 'conflict';
    protected function getTitle(): string { return 'Conflict'; }
}

// 422
class ValidationException extends AppException
{
    protected int $statusCode = 422;
    protected string $errorType = 'validation-error';
    private array $errors;

    public function __construct(array $errors, string $message = 'Validation failed')
    {
        parent::__construct($message);
        $this->errors = $errors;
    }

    protected function getTitle(): string { return 'Validation Failed'; }

    public function toArray(): array
    {
        return array_merge(parent::toArray(), ['errors' => $this->errors]);
    }
}

// 503
class ServiceUnavailableException extends AppException
{
    protected int $statusCode = 503;
    protected string $errorType = 'service-unavailable';
    protected function getTitle(): string { return 'Service Unavailable'; }
}
```

---

## 2. 글로벌 예외 핸들러

### CodeIgniter 4

```php
// app/Config/Exceptions.php — 커스텀 핸들러 등록
// CI4.4+: 커스텀 Exception Handler
namespace App\Exceptions;

use CodeIgniter\Debug\BaseExceptionHandler;
use CodeIgniter\HTTP\RequestInterface;
use CodeIgniter\HTTP\ResponseInterface;
use Psr\Log\LoggerInterface;

class ApiExceptionHandler extends BaseExceptionHandler
{
    public function handle(
        \Throwable $exception,
        RequestInterface $request,
        ResponseInterface $response,
        int $statusCode,
        int $exitCode,
    ): void {
        $logger = service('logger');

        // AppException 계열
        if ($exception instanceof AppException) {
            $body = $exception->toArray();
            $statusCode = $exception->getStatusCode();

            if ($statusCode >= 500) {
                $logger->error($exception->getMessage(), [
                    'exception' => get_class($exception),
                    'trace' => $exception->getTraceAsString(),
                ]);
            } else {
                $logger->warning($exception->getMessage(), [
                    'exception' => get_class($exception),
                ]);
            }
        }
        // CI4 PageNotFoundException
        elseif ($exception instanceof \CodeIgniter\Exceptions\PageNotFoundException) {
            $statusCode = 404;
            $body = [
                'type' => 'https://api.example.com/errors/not-found',
                'title' => 'Not Found',
                'status' => 404,
                'detail' => $exception->getMessage(),
            ];
        }
        // 기타 예상치 못한 에러
        else {
            $statusCode = 500;
            $body = [
                'type' => 'https://api.example.com/errors/internal-error',
                'title' => 'Internal Server Error',
                'status' => 500,
                'detail' => ENVIRONMENT === 'production'
                    ? 'An unexpected error occurred.'
                    : $exception->getMessage(),
            ];

            $logger->critical($exception->getMessage(), [
                'exception' => get_class($exception),
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => $exception->getTraceAsString(),
            ]);
        }

        $response->setStatusCode($statusCode)
            ->setContentType('application/problem+json')
            ->setJSON($body)
            ->send();
    }
}
```

### CodeIgniter 3

```php
// application/core/MY_Controller.php
class MY_Controller extends CI_Controller
{
    public function __construct()
    {
        parent::__construct();
        set_exception_handler([$this, 'handle_exception']);
    }

    public function handle_exception(\Throwable $e)
    {
        if ($e instanceof AppException) {
            $status = $e->getStatusCode();
            $body = $e->toArray();
        } else {
            $status = 500;
            $body = [
                'status' => 500,
                'title' => 'Internal Server Error',
                'detail' => ENVIRONMENT === 'production'
                    ? 'An unexpected error occurred.'
                    : $e->getMessage(),
            ];
            log_message('error', $e->getMessage() . "\n" . $e->getTraceAsString());
        }

        $this->output
            ->set_status_header($status)
            ->set_content_type('application/json')
            ->set_output(json_encode($body))
            ->_display();
        exit;
    }
}
```

---

## 3. RFC 9457 Problem Details

```php
// 표준 에러 응답 형식
{
    "type": "https://api.example.com/errors/validation-error",
    "title": "Validation Failed",
    "status": 422,
    "detail": "The request body contains invalid fields.",
    "errors": {
        "email": "이미 등록된 이메일입니다.",
        "password": "비밀번호는 최소 8자 이상이어야 합니다."
    }
}

// 500 에러 (프로덕션)
{
    "type": "https://api.example.com/errors/internal-error",
    "title": "Internal Server Error",
    "status": 500,
    "detail": "An unexpected error occurred."
}

// 500 에러 (개발)
{
    "type": "https://api.example.com/errors/internal-error",
    "title": "Internal Server Error",
    "status": 500,
    "detail": "SQLSTATE[23000]: Integrity constraint violation: 1062 Duplicate entry 'test@test.com'",
    "trace": "..."
}
```

---

## 4. 서비스 레이어에서의 예외 사용

```php
class UserService
{
    public function getUser(int $id): User
    {
        $user = $this->userModel->find($id);
        if (!$user) {
            throw new NotFoundException("User with ID {$id} not found.");
        }
        return $user;
    }

    public function createUser(array $data): User
    {
        // 중복 체크
        $existing = $this->userModel->where('email', $data['email'])->first();
        if ($existing) {
            throw new ConflictException("Email {$data['email']} is already registered.");
        }

        // 외부 서비스 호출 실패
        try {
            $this->emailService->sendWelcome($data['email']);
        } catch (\Exception $e) {
            throw new ServiceUnavailableException(
                'Email service is temporarily unavailable.',
                previous: $e,
            );
        }

        return $this->userModel->save(new User($data));
    }
}
```

---

## 5. 로깅과 에러 트래킹

```php
// CI4 로거
$logger = service('logger');

// 레벨별
$logger->emergency('시스템 다운');
$logger->alert('즉시 조치 필요');
$logger->critical('치명적 에러', ['exception' => $e->getMessage()]);
$logger->error('에러 발생', ['userId' => $userId, 'action' => 'create']);
$logger->warning('경고', ['remaining_rate_limit' => $remaining]);
$logger->info('정보', ['event' => 'user_created', 'userId' => $userId]);
$logger->debug('디버그', ['query' => $sql, 'params' => $params]);

// CI3
log_message('error', 'Error: ' . $e->getMessage());
log_message('info', 'User created: ' . $userId);
log_message('debug', 'Query: ' . $sql);
```
