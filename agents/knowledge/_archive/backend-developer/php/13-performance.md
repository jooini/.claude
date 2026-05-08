# Performance

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. 성능 병목 진단

```
측정 → 분석 → 최적화 → 재측정

도구:
- Xdebug Profiler: 함수별 실행 시간, 메모리
- Blackfire.io: 프로덕션 안전 프로파일러
- EXPLAIN ANALYZE: DB 쿼리 분석
- k6 / Apache Bench: 부하 테스트
- OPcache: 바이트코드 캐싱 상태 확인
```

---

## 2. 데이터베이스 최적화

### N+1 쿼리 방지

```php
// ❌ N+1 문제
$users = $userModel->findAll();
foreach ($users as $user) {
    $user->orders = $orderModel->where('user_id', $user->id)->findAll();
    // 유저 100명 → 101개 쿼리!
}

// ✅ 배치 로딩 (2개 쿼리)
$users = $userModel->findAll();
$userIds = array_column($users, 'id');

$orders = $orderModel->whereIn('user_id', $userIds)->findAll();

$orderMap = [];
foreach ($orders as $order) {
    $orderMap[$order->user_id][] = $order;
}
foreach ($users as &$user) {
    $user->orders = $orderMap[$user->id] ?? [];
}

// ✅ JOIN으로 한방 쿼리
$result = $db->table('users u')
    ->select('u.*, COUNT(o.id) as order_count, SUM(o.total) as total_spent')
    ->join('orders o', 'o.user_id = u.id', 'left')
    ->where('u.is_active', true)
    ->groupBy('u.id')
    ->get()
    ->getResultArray();
```

### 필요한 컬럼만 조회

```php
// ❌ SELECT *
$users = $userModel->findAll();

// ✅ 필요한 컬럼만
$users = $db->table('users')
    ->select('id, email, name')
    ->where('is_active', true)
    ->get()
    ->getResultArray();
```

### 인덱스 활용

```php
// 마이그레이션에서 인덱스 추가
$this->forge->addKey('email', false, true);  // UNIQUE
$this->forge->addKey(['status', 'created_at']);  // 복합 인덱스
$this->forge->addKey('role');

// Raw SQL로 인덱스
$db->query('CREATE INDEX idx_users_status_created ON users(status, created_at)');
```

---

## 3. 캐싱

### CI4 Cache

```php
$cache = \Config\Services::cache();

// 파일 캐시 (기본)
$cache->save('key', $value, 300);    // 5분
$value = $cache->get('key');
$cache->delete('key');

// Redis 캐시 설정
// app/Config/Cache.php
public string $handler = 'redis';
public array $redis = [
    'host' => '127.0.0.1',
    'password' => null,
    'port' => 6379,
    'timeout' => 0,
    'database' => 0,
];
```

### 캐싱 패턴

```php
class UserService
{
    private $cache;

    public function __construct()
    {
        $this->cache = \Config\Services::cache();
    }

    public function getUser(int $id): ?array
    {
        $cacheKey = "user:{$id}";

        $user = $this->cache->get($cacheKey);
        if ($user !== null) {
            return $user;
        }

        $user = $this->userModel->find($id);
        if ($user) {
            $this->cache->save($cacheKey, $user, 600); // 10분
        }

        return $user;
    }

    public function updateUser(int $id, array $data): void
    {
        $this->userModel->update($id, $data);
        $this->cache->delete("user:{$id}");  // 캐시 무효화
    }

    // 태그 기반 캐시 무효화 (Redis)
    public function clearUserCache(): void
    {
        // Redis SCAN으로 패턴 삭제
        $redis = \Config\Services::cache()->getCacheInfo();
        // 또는 predis 직접 사용
    }
}
```

### CI3 캐싱

```php
$this->load->driver('cache', ['adapter' => 'file', 'backup' => 'file']);

$user = $this->cache->get('user_' . $id);
if (!$user) {
    $user = $this->User_model->get_by_id($id);
    $this->cache->save('user_' . $id, $user, 300);
}
```

---

## 4. OPcache

```ini
; php.ini — 프로덕션 필수
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0          ; 프로덕션: 0 (배포 시 opcache_reset)
opcache.revalidate_freq=0
opcache.jit=1255                        ; PHP 8.0+ JIT
opcache.jit_buffer_size=100M
```

```php
// 배포 스크립트에서 OPcache 리셋
opcache_reset();

// 상태 확인
$status = opcache_get_status();
echo $status['opcache_statistics']['hits'];         // 캐시 히트 수
echo $status['opcache_statistics']['misses'];       // 캐시 미스 수
echo $status['memory_usage']['used_memory'];        // 사용 메모리
```

---

## 5. 응답 압축

```php
// CI4: app/Config/App.php
// nginx/Apache에서 처리 권장

// nginx
gzip on;
gzip_types application/json text/plain text/css application/javascript;
gzip_min_length 1024;

// PHP 레벨
// CI4
$this->response->setHeader('Content-Encoding', 'gzip');
// 또는 ob_start('ob_gzhandler');
```

---

## 6. 비동기 처리

```php
// PHP는 기본적으로 동기/블로킹 — 비동기는 큐로 처리

// 방법 1: 데이터베이스 큐
$db->table('job_queue')->insert([
    'type' => 'send_email',
    'payload' => json_encode(['to' => $email, 'subject' => $subject]),
    'status' => 'pending',
    'created_at' => date('Y-m-d H:i:s'),
]);

// 워커 (cron 또는 supervisor)
// php spark queue:work
class QueueWorker
{
    public function process(): void
    {
        $job = $db->table('job_queue')
            ->where('status', 'pending')
            ->orderBy('created_at', 'ASC')
            ->limit(1)
            ->get()
            ->getRowArray();

        if (!$job) return;

        $db->table('job_queue')->update($job['id'], ['status' => 'processing']);

        try {
            $this->execute($job);
            $db->table('job_queue')->update($job['id'], ['status' => 'completed']);
        } catch (\Throwable $e) {
            $db->table('job_queue')->update($job['id'], [
                'status' => 'failed',
                'error' => $e->getMessage(),
            ]);
        }
    }
}

// 방법 2: Redis Queue (predis)
$redis->lpush('email_queue', json_encode($jobData));
// 워커: $job = $redis->brpop('email_queue', 30);
```

---

## 7. 부하 테스트

```bash
# Apache Bench
ab -n 1000 -c 50 -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/users

# k6
cat <<'EOF' > load-test.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
    stages: [
        { duration: '1m', target: 50 },
        { duration: '3m', target: 50 },
        { duration: '1m', target: 0 },
    ],
};

export default function () {
    const res = http.get('http://localhost:8080/api/v1/users', {
        headers: { Authorization: `Bearer ${__ENV.TOKEN}` },
    });
    check(res, { 'status is 200': (r) => r.status === 200 });
}
EOF

k6 run load-test.js
```

---

## 8. PHP-FPM 튜닝

```ini
; /etc/php/8.3/fpm/pool.d/www.conf
[www]
pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500          ; 메모리 누수 방지 — 500 요청 후 워커 재시작
pm.process_idle_timeout = 10s

; 슬로우 로그
request_slowlog_timeout = 5s
slowlog = /var/log/php-fpm/slow.log
```
