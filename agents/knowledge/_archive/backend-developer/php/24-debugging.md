# Debugging

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. Xdebug

```ini
; php.ini
[xdebug]
zend_extension=xdebug
xdebug.mode=debug,develop,profile
xdebug.start_with_request=trigger     ; XDEBUG_TRIGGER 쿠키/쿼리 시 시작
xdebug.client_host=host.docker.internal ; Docker 환경
xdebug.client_port=9003
xdebug.idekey=PHPSTORM
xdebug.log=/var/log/xdebug.log
```

### IDE 설정 (PhpStorm)

```
1. Settings → PHP → Debug → Xdebug port: 9003
2. Settings → PHP → Servers → 서버 설정 + Path mappings
3. Run → Start Listening for PHP Debug Connections
4. 브레이크포인트 설정 후 요청 발송
```

### 조건부 브레이크포인트

```
PhpStorm 브레이크포인트 우클릭 → Condition:
  $userId === 'specific-user-id'
  $amount > 10000
  count($items) > 5
```

### VS Code (Xdebug)

```json
// .vscode/launch.json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Listen for Xdebug",
            "type": "php",
            "request": "launch",
            "port": 9003,
            "pathMappings": {
                "/var/www/html": "${workspaceFolder}"
            }
        }
    ]
}
```

---

## 2. 로그 디버깅

### CodeIgniter 4

```php
// 기본 로거
log_message('debug', '변수 확인: {data}', ['data' => json_encode($variable)]);
log_message('error', '에러: {error}', ['error' => $e->getMessage()]);

// 임시 디버그 (커밋 전 제거)
log_message('debug', '>>> DEBUG: value=' . print_r($suspiciousValue, true));

// 런타임 로그 레벨 변경
// app/Config/Logger.php
public $threshold = 4;  // 1=error, 2=warn, 3=info, 4=debug

// 환경별 (.env)
logger.threshold = 4
```

### CodeIgniter 3

```php
log_message('debug', '변수 확인: ' . print_r($variable, true));
log_message('error', '에러: ' . $e->getMessage());
```

---

## 3. 디버그 도구

### var_dump / print_r

```php
// 개발 환경에서만 사용
if (ENVIRONMENT !== 'production') {
    header('Content-Type: text/plain');
    var_dump($variable);
    exit;
}

// 로그로 출력 (안전)
error_log(print_r($variable, true));

// CI4 Debug Toolbar
// .env: CI_ENVIRONMENT = development
// app/Config/Toolbar.php에서 활성화
```

### CI4 Debug Toolbar

```php
// 자동 활성화 (development 환경)
// 기능:
// - 타임라인 (요청 처리 시간)
// - 데이터베이스 쿼리 로그
// - 뷰 렌더링 정보
// - 라우트 정보
// - 이벤트 로그
// - 파일 로드 목록
```

---

## 4. 프로파일링

### Xdebug Profiler

```ini
; php.ini
xdebug.mode=profile
xdebug.output_dir=/tmp/xdebug_profiles
xdebug.profiler_output_name=cachegrind.out.%R.%t
```

```
프로파일 분석:
1. cachegrind.out.* 파일 생성됨
2. KCachegrind (Linux) / QCachegrind (Mac) / Webgrind로 분석
3. 함수별 실행 시간, 호출 횟수 확인
4. 병목 지점 식별
```

### Blackfire.io (프로덕션 안전)

```bash
# 설치
curl -sSL https://packages.blackfire.io/gpg.key | sudo apt-key add -
# ... 설치 과정

# 프로파일링
blackfire curl http://localhost:8080/api/v1/users

# PHP SDK
\BlackfireProbe::enable();
// 프로파일링 대상 코드
\BlackfireProbe::disable();
```

---

## 5. 메모리 디버깅

```php
// 메모리 사용량 추적
function trackMemory(string $label): void
{
    $usage = memory_get_usage(true) / 1024 / 1024;
    $peak = memory_get_peak_usage(true) / 1024 / 1024;
    error_log(sprintf("[Memory] %s: %.2fMB (peak: %.2fMB)", $label, $usage, $peak));
}

trackMemory('before query');
$results = $db->table('large_table')->findAll();
trackMemory('after query');

// 대용량 데이터 → 청크 처리
$db->table('users')
    ->orderBy('id')
    ->chunk(1000, function (array $users) {
        foreach ($users as $user) {
            processUser($user);
        }
        gc_collect_cycles(); // 메모리 해제
    });

// Generator로 메모리 절약
function fetchAllUsers(): \Generator
{
    $offset = 0;
    $limit = 100;
    $db = \Config\Database::connect();

    while (true) {
        $users = $db->table('users')
            ->limit($limit, $offset)
            ->get()
            ->getResultArray();

        if (empty($users)) break;

        foreach ($users as $user) {
            yield $user;
        }

        $offset += $limit;
    }
}
```

---

## 6. 느린 쿼리 감지

```php
// CI4 이벤트
Events::on('DBQuery', function (\CodeIgniter\Database\Query $query) {
    $duration = $query->getDuration();

    // 100ms 이상 쿼리 로깅
    if ($duration > 0.1) {
        log_message('warning', 'Slow query ({duration}ms): {query}', [
            'duration' => round($duration * 1000),
            'query' => $query->getQuery(),
        ]);
    }
});

// MySQL 슬로우 쿼리 로그
// my.cnf
[mysqld]
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 1
log_queries_not_using_indexes = 1
```

---

## 7. 에러 재현

```bash
# PHPUnit 특정 테스트만
vendor/bin/phpunit --filter testCreateUser_이메일_중복

# Xdebug 디버그 모드로 테스트
XDEBUG_MODE=debug vendor/bin/phpunit --filter testSpecific

# CI4 테스트
php spark test --filter testSpecific

# cURL로 API 재현
curl -v -X POST http://localhost:8080/api/v1/users \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"email":"test@test.com","name":"Test","password":"Test1234!"}'
```

---

## 8. PHP-FPM 디버깅

```bash
# PHP-FPM 상태 확인
# /etc/php/8.3/fpm/pool.d/www.conf
pm.status_path = /fpm-status

# 접속
curl http://localhost/fpm-status?full
# 결과: 프로세스별 상태, 요청 처리 시간, 메모리 사용량

# PHP-FPM 슬로우 로그
request_slowlog_timeout = 5s
slowlog = /var/log/php-fpm/slow.log
# → 5초 이상 걸리는 요청의 스택 트레이스 기록

# 에러 로그
php_admin_value[error_log] = /var/log/php-fpm/error.log
php_admin_flag[log_errors] = on
```
