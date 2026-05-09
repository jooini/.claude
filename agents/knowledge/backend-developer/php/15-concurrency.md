# Concurrency

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. PHP 동시성 특성

```
PHP는 기본적으로 Shared Nothing 아키텍처:
- 각 요청이 독립된 프로세스 (PHP-FPM Worker)
- 프로세스 간 메모리 공유 없음
- 인메모리 락/뮤텍스는 의미 없음 → DB 또는 Redis 락 필요

동시성 문제가 발생하는 곳:
- 데이터베이스 (여러 Worker가 같은 row 수정)
- 파일 시스템 (여러 프로세스가 같은 파일 접근)
- 외부 리소스 (API rate limit, 재고 차감)
```

---

## 2. 데이터베이스 락

### 비관적 락 (SELECT FOR UPDATE)

```php
// CI4
$db = \Config\Database::connect();

$db->transStart();

// SELECT FOR UPDATE — 다른 트랜잭션이 이 row를 수정 못함
$account = $db->query(
    "SELECT * FROM accounts WHERE id = ? FOR UPDATE",
    [$accountId]
)->getRowArray();

if ($account['balance'] < $amount) {
    $db->transRollback();
    throw new InsufficientBalanceException();
}

$db->table('accounts')
    ->where('id', $accountId)
    ->update(['balance' => $account['balance'] - $amount]);

$db->transComplete();

// CI3
$this->db->trans_start();

$account = $this->db->query(
    "SELECT * FROM accounts WHERE id = ? FOR UPDATE",
    [$accountId]
)->row_array();

if ($account['balance'] < $amount) {
    $this->db->trans_rollback();
    throw new Exception('Insufficient balance');
}

$this->db->where('id', $accountId)
    ->update('accounts', ['balance' => $account['balance'] - $amount]);

$this->db->trans_complete();
```

### 낙관적 락 (Version 컬럼)

```php
// 버전 기반 낙관적 락
function updateStock(int $productId, int $delta): void
{
    $db = \Config\Database::connect();
    $maxRetries = 3;

    for ($attempt = 0; $attempt < $maxRetries; $attempt++) {
        $product = $db->table('products')
            ->where('id', $productId)
            ->get()
            ->getRowArray();

        if (!$product) {
            throw new NotFoundException("Product {$productId} not found");
        }

        $newStock = $product['stock'] + $delta;
        if ($newStock < 0) {
            throw new InsufficientStockException();
        }

        // version이 일치할 때만 업데이트
        $affected = $db->table('products')
            ->where('id', $productId)
            ->where('version', $product['version'])
            ->update([
                'stock' => $newStock,
                'version' => $product['version'] + 1,
            ]);

        if ($db->affectedRows() > 0) {
            return; // 성공
        }

        // version 불일치 → 재시도
        usleep(100000 * ($attempt + 1)); // 100ms, 200ms, 300ms
    }

    throw new ConflictException('Concurrent modification detected. Please retry.');
}
```

---

## 3. Redis 분산 락

```php
// Predis 사용
use Predis\Client as RedisClient;

class DistributedLock
{
    private RedisClient $redis;

    public function __construct(RedisClient $redis)
    {
        $this->redis = $redis;
    }

    public function acquire(string $key, int $ttlSeconds = 10): ?string
    {
        $token = bin2hex(random_bytes(16));
        $lockKey = "lock:{$key}";

        // SET NX EX (atomic)
        $result = $this->redis->set($lockKey, $token, 'EX', $ttlSeconds, 'NX');

        return $result ? $token : null;
    }

    public function release(string $key, string $token): bool
    {
        $lockKey = "lock:{$key}";

        // Lua 스크립트로 atomic하게 확인+삭제
        $script = <<<'LUA'
            if redis.call("get", KEYS[1]) == ARGV[1] then
                return redis.call("del", KEYS[1])
            else
                return 0
            end
        LUA;

        return (bool) $this->redis->eval($script, 1, $lockKey, $token);
    }

    /**
     * 락 획득 후 콜백 실행
     */
    public function executeWithLock(string $key, callable $callback, int $ttl = 10, int $waitMs = 5000): mixed
    {
        $startTime = microtime(true) * 1000;

        while ((microtime(true) * 1000) - $startTime < $waitMs) {
            $token = $this->acquire($key, $ttl);
            if ($token) {
                try {
                    return $callback();
                } finally {
                    $this->release($key, $token);
                }
            }
            usleep(50000); // 50ms 대기
        }

        throw new \RuntimeException("Failed to acquire lock: {$key}");
    }
}

// 사용
$lock = new DistributedLock($redis);

$result = $lock->executeWithLock("refresh:{$userId}", function () use ($userId) {
    $newToken = $this->fetchNewToken($userId);
    $this->saveToken($userId, $newToken);
    return $newToken;
});
```

---

## 4. 파일 락

```php
// flock — 파일 기반 프로세스 간 동기화
function writeWithLock(string $path, string $data): void
{
    $fp = fopen($path, 'c+');
    if (!$fp) {
        throw new \RuntimeException("Cannot open file: {$path}");
    }

    if (flock($fp, LOCK_EX)) {  // 배타적 락
        ftruncate($fp, 0);
        fwrite($fp, $data);
        fflush($fp);
        flock($fp, LOCK_UN);    // 락 해제
    } else {
        throw new \RuntimeException("Cannot acquire lock: {$path}");
    }

    fclose($fp);
}

// 비차단 시도
if (flock($fp, LOCK_EX | LOCK_NB)) {
    // 락 획득 성공
} else {
    // 다른 프로세스가 사용 중
}
```

---

## 5. 큐 기반 비동기 처리

### 데이터베이스 큐

```php
// 큐 테이블
// jobs: id, type, payload, status, attempts, max_attempts, scheduled_at, created_at

class JobQueue
{
    private $db;

    public function dispatch(string $type, array $payload, ?string $scheduledAt = null): int
    {
        $this->db->table('jobs')->insert([
            'type' => $type,
            'payload' => json_encode($payload),
            'status' => 'pending',
            'attempts' => 0,
            'max_attempts' => 3,
            'scheduled_at' => $scheduledAt ?? date('Y-m-d H:i:s'),
            'created_at' => date('Y-m-d H:i:s'),
        ]);

        return $this->db->insertID();
    }

    public function processNext(): bool
    {
        $this->db->transStart();

        // FOR UPDATE SKIP LOCKED — 다른 Worker가 처리 중인 job 건너뜀
        $job = $this->db->query(
            "SELECT * FROM jobs WHERE status = 'pending' AND scheduled_at <= NOW() ORDER BY created_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED"
        )->getRowArray();

        if (!$job) {
            $this->db->transRollback();
            return false;
        }

        $this->db->table('jobs')->update($job['id'], [
            'status' => 'processing',
            'attempts' => $job['attempts'] + 1,
        ]);

        $this->db->transComplete();

        try {
            $this->execute($job);
            $this->db->table('jobs')->update($job['id'], ['status' => 'completed']);
        } catch (\Throwable $e) {
            $newStatus = ($job['attempts'] + 1 >= $job['max_attempts']) ? 'failed' : 'pending';
            $this->db->table('jobs')->update($job['id'], [
                'status' => $newStatus,
                'error' => $e->getMessage(),
            ]);
        }

        return true;
    }
}
```

### Redis 큐

```php
class RedisQueue
{
    private RedisClient $redis;

    public function push(string $queue, array $job): void
    {
        $this->redis->lpush("queue:{$queue}", json_encode([
            'id' => bin2hex(random_bytes(8)),
            'type' => $job['type'],
            'payload' => $job['payload'],
            'created_at' => date('Y-m-d H:i:s'),
        ]));
    }

    public function pop(string $queue, int $timeoutSeconds = 30): ?array
    {
        $result = $this->redis->brpop(["queue:{$queue}"], $timeoutSeconds);
        if (!$result) return null;

        return json_decode($result[1], true);
    }
}

// Worker (supervisor로 관리)
while (true) {
    $job = $queue->pop('email');
    if ($job) {
        processJob($job);
    }
}
```

---

## 6. 멀티프로세스 (pcntl)

```php
// CLI 전용 — 웹 요청에서는 사용 불가

// 병렬 처리
$pids = [];
$items = array_chunk($largeDataset, 100);

foreach ($items as $chunk) {
    $pid = pcntl_fork();

    if ($pid === -1) {
        throw new \RuntimeException('Fork failed');
    }

    if ($pid === 0) {
        // 자식 프로세스
        processChunk($chunk);
        exit(0);
    }

    $pids[] = $pid;
}

// 모든 자식 프로세스 대기
foreach ($pids as $pid) {
    pcntl_waitpid($pid, $status);
}
```

---

## 7. 동시성 안티패턴

```php
// ❌ 인메모리 변수로 동시성 제어 시도
// PHP는 Shared Nothing — 프로세스 간 변수 공유 안 됨
$counter = 0;  // 각 Worker마다 별도 인스턴스
$counter++;    // 다른 Worker에 영향 없음

// ❌ 파일로 카운터 관리 (경합 조건)
$count = (int) file_get_contents('counter.txt');
file_put_contents('counter.txt', $count + 1);  // Race condition!

// ✅ Redis INCR (atomic)
$newCount = $redis->incr('counter');

// ✅ DB UPDATE (atomic)
$db->query("UPDATE counters SET value = value + 1 WHERE name = ?", ['page_views']);

// ❌ sleep()으로 동시성 해결 시도
sleep(1);  // 무의미 — 타이밍에 의존하면 안 됨

// ✅ 락 사용
$lock->executeWithLock('resource_key', function () { ... });
```
