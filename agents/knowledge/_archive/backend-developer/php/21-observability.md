# Observability

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. Observability 3 기둥

```
Logs    — 무슨 일이 일어났는가 (이벤트)
Metrics — 얼마나 자주/빠르게 (수치)
Traces  — 어떻게 흘렀는가 (요청 경로)
```

---

## 2. 구조화 로깅 (Monolog)

### CodeIgniter 4

```php
// composer require monolog/monolog

// app/Config/Logger.php — 커스텀 핸들러 등록
// 또는 별도 서비스로

// app/Libraries/StructuredLogger.php
namespace App\Libraries;

use Monolog\Logger;
use Monolog\Handler\StreamHandler;
use Monolog\Handler\RotatingFileHandler;
use Monolog\Formatter\JsonFormatter;
use Monolog\Processor\IntrospectionProcessor;
use Monolog\Processor\WebProcessor;

class StructuredLogger
{
    private Logger $logger;
    private static array $context = [];

    public function __construct(string $channel = 'app')
    {
        $this->logger = new Logger($channel);

        if (ENVIRONMENT === 'production') {
            // JSON 형식 (ELK, CloudWatch 등)
            $handler = new StreamHandler('php://stdout', Logger::INFO);
            $handler->setFormatter(new JsonFormatter());
        } else {
            // 로컬: 파일 로테이션
            $handler = new RotatingFileHandler(WRITEPATH . 'logs/app.log', 30, Logger::DEBUG);
        }

        $this->logger->pushHandler($handler);
        $this->logger->pushProcessor(new WebProcessor());
    }

    // 글로벌 컨텍스트 (requestId, userId 등)
    public static function setContext(string $key, mixed $value): void
    {
        self::$context[$key] = $value;
    }

    public function info(string $message, array $context = []): void
    {
        $this->logger->info($message, array_merge(self::$context, $context));
    }

    public function error(string $message, array $context = []): void
    {
        $this->logger->error($message, array_merge(self::$context, $context));
    }

    public function warning(string $message, array $context = []): void
    {
        $this->logger->warning($message, array_merge(self::$context, $context));
    }

    public function debug(string $message, array $context = []): void
    {
        $this->logger->debug($message, array_merge(self::$context, $context));
    }
}
```

### RequestId 주입

```php
// CI4 Filter
class RequestIdFilter implements FilterInterface
{
    public function before(RequestInterface $request, $arguments = null)
    {
        $requestId = $request->getHeaderLine('X-Request-ID') ?: bin2hex(random_bytes(8));
        StructuredLogger::setContext('requestId', $requestId);

        service('response')->setHeader('X-Request-ID', $requestId);
    }

    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null) {}
}

// CI3 Hook
class RequestIdHook
{
    public function inject()
    {
        $CI =& get_instance();
        $requestId = $CI->input->get_request_header('X-Request-ID') ?: bin2hex(random_bytes(8));
        $CI->requestId = $requestId;
        $CI->output->set_header("X-Request-ID: {$requestId}");
    }
}
```

### CI3 기본 로깅

```php
// application/config/config.php
$config['log_threshold'] = 4;  // 0=off, 1=error, 2=warn, 3=info, 4=debug
$config['log_path'] = APPPATH . 'logs/';
$config['log_date_format'] = 'Y-m-d H:i:s';

// 사용
log_message('error', '결제 실패: userId={userId}, error={error}', [
    'userId' => $userId,
    'error' => $e->getMessage(),
]);
log_message('info', '사용자 생성: userId={userId}', ['userId' => $userId]);
```

---

## 3. 메트릭 (Prometheus)

```php
// composer require promphp/prometheus_client_php

use Prometheus\CollectorRegistry;
use Prometheus\Storage\Redis as RedisStorage;
use Prometheus\RenderTextFormat;

class MetricsService
{
    private CollectorRegistry $registry;

    public function __construct()
    {
        $this->registry = new CollectorRegistry(
            new RedisStorage(['host' => '127.0.0.1'])
        );
    }

    // HTTP 요청 메트릭
    public function recordRequest(string $method, string $path, int $status, float $duration): void
    {
        // Counter
        $counter = $this->registry->getOrRegisterCounter(
            'app', 'http_requests_total', 'Total HTTP requests',
            ['method', 'path', 'status']
        );
        $counter->inc([$method, $path, (string) $status]);

        // Histogram (응답 시간)
        $histogram = $this->registry->getOrRegisterHistogram(
            'app', 'http_request_duration_seconds', 'HTTP request duration',
            ['method', 'path'],
            [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
        );
        $histogram->observe($duration, [$method, $path]);
    }

    // 커스텀 비즈니스 메트릭
    public function recordOrderCreated(string $type): void
    {
        $counter = $this->registry->getOrRegisterCounter(
            'app', 'orders_created_total', 'Total orders created',
            ['type']
        );
        $counter->inc([$type]);
    }

    // Prometheus 스크래핑 엔드포인트
    public function renderMetrics(): string
    {
        $renderer = new RenderTextFormat();
        return $renderer->render($this->registry->getMetricFamilySamples());
    }
}

// 엔드포인트
// GET /metrics
class MetricsController extends BaseController
{
    public function index(): ResponseInterface
    {
        $metrics = service('metricsService');
        return $this->response
            ->setContentType('text/plain; version=0.0.4')
            ->setBody($metrics->renderMetrics());
    }
}
```

### 메트릭 수집 Filter

```php
class MetricsFilter implements FilterInterface
{
    public function before(RequestInterface $request, $arguments = null)
    {
        $request->startTime = microtime(true);
    }

    public function after(RequestInterface $request, ResponseInterface $response, $arguments = null)
    {
        $duration = microtime(true) - ($request->startTime ?? microtime(true));
        $method = $request->getMethod();
        $path = $request->getPath();
        $status = $response->getStatusCode();

        service('metricsService')->recordRequest($method, $path, $status, $duration);
    }
}
```

---

## 4. 헬스체크

```php
// CI4
class HealthController extends BaseController
{
    public function index(): ResponseInterface
    {
        $checks = [];
        $healthy = true;

        // DB 체크
        try {
            $db = \Config\Database::connect();
            $db->query('SELECT 1');
            $checks['database'] = ['status' => 'up'];
        } catch (\Throwable $e) {
            $checks['database'] = ['status' => 'down', 'error' => $e->getMessage()];
            $healthy = false;
        }

        // Redis 체크
        try {
            $cache = \Config\Services::cache();
            $cache->save('health_check', 'ok', 5);
            $checks['redis'] = ['status' => 'up'];
        } catch (\Throwable $e) {
            $checks['redis'] = ['status' => 'down', 'error' => $e->getMessage()];
            $healthy = false;
        }

        // Disk 체크
        $freeSpace = disk_free_space(WRITEPATH);
        $checks['disk'] = [
            'status' => $freeSpace > 100 * 1024 * 1024 ? 'up' : 'warning',
            'free_mb' => round($freeSpace / 1024 / 1024),
        ];

        $status = $healthy ? 200 : 503;
        return $this->response->setStatusCode($status)->setJSON([
            'status' => $healthy ? 'healthy' : 'unhealthy',
            'checks' => $checks,
            'timestamp' => date('c'),
        ]);
    }

    // Kubernetes liveness
    public function liveness(): ResponseInterface
    {
        return $this->response->setJSON(['status' => 'ok']);
    }

    // Kubernetes readiness
    public function readiness(): ResponseInterface
    {
        try {
            \Config\Database::connect()->query('SELECT 1');
            return $this->response->setJSON(['status' => 'ready']);
        } catch (\Throwable $e) {
            return $this->response->setStatusCode(503)->setJSON(['status' => 'not ready']);
        }
    }
}
```

---

## 5. 감사 로그

```php
// CI4 Model 이벤트 활용
class AuditableModel extends Model
{
    protected $afterInsert = ['logAudit'];
    protected $afterUpdate = ['logAudit'];
    protected $afterDelete = ['logAudit'];

    protected function logAudit(array $data): array
    {
        $db = \Config\Database::connect();
        $db->table('audit_logs')->insert([
            'table_name' => $this->table,
            'record_id' => $data['id'][0] ?? $data['id'] ?? null,
            'action' => $data['method'] ?? 'unknown',
            'changes' => json_encode($data['data'] ?? []),
            'user_id' => session('user_id'),
            'ip_address' => service('request')->getIPAddress(),
            'created_at' => date('Y-m-d H:i:s'),
        ]);

        return $data;
    }
}
```

---

## 6. 슬로우 쿼리 로깅

```php
// CI4 이벤트 사용
// app/Config/Events.php
Events::on('DBQuery', function (\CodeIgniter\Database\Query $query) {
    $elapsed = $query->getDuration();
    if ($elapsed > 1.0) { // 1초 이상
        $logger = service('logger');
        $logger->warning('Slow query detected', [
            'query' => $query->getQuery(),
            'duration_ms' => round($elapsed * 1000),
        ]);
    }
});
```
