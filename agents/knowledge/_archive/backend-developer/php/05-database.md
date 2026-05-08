# Database

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. 데이터베이스 드라이버

```
CodeIgniter 4:
  - MySQLi (기본), Postgres, SQLite3, SQLSRV
  - Query Builder (Active Record 후속)
  - Entity 클래스, Model 클래스

CodeIgniter 3:
  - MySQL/MySQLi, Postgres, SQLite
  - Active Record 패턴
  - 수동 모델 클래스
```

---

## 2. Model 정의

### CodeIgniter 4

```php
// app/Models/UserModel.php
namespace App\Models;

use CodeIgniter\Model;
use App\Entities\User;

class UserModel extends Model
{
    protected $table = 'users';
    protected $primaryKey = 'id';
    protected $returnType = User::class;  // Entity 반환
    protected $useSoftDeletes = true;
    protected $useTimestamps = true;
    protected $createdField = 'created_at';
    protected $updatedField = 'updated_at';
    protected $deletedField = 'deleted_at';

    protected $allowedFields = [
        'email', 'name', 'password', 'phone',
        'is_active', 'role', 'metadata',
    ];

    // 유효성 검사 규칙
    protected $validationRules = [
        'email' => 'required|valid_email|is_unique[users.email,id,{id}]',
        'name'  => 'required|min_length[2]|max_length[50]',
    ];

    protected $validationMessages = [
        'email' => [
            'is_unique' => '이미 등록된 이메일입니다.',
        ],
    ];

    // 콜백
    protected $beforeInsert = ['hashPassword'];
    protected $beforeUpdate = ['hashPassword'];

    protected function hashPassword(array $data): array
    {
        if (isset($data['data']['password'])) {
            $data['data']['password'] = password_hash($data['data']['password'], PASSWORD_ARGON2ID);
        }
        return $data;
    }

    // 커스텀 쿼리
    public function findActiveByRole(string $role): array
    {
        return $this->where('is_active', true)
            ->where('role', $role)
            ->orderBy('created_at', 'DESC')
            ->findAll();
    }
}
```

### CodeIgniter 3

```php
// application/models/User_model.php
class User_model extends CI_Model
{
    protected $table = 'users';

    public function get_by_id(int $id): ?array
    {
        return $this->db->get_where($this->table, ['id' => $id])->row_array();
    }

    public function insert_user(array $data): int
    {
        $this->db->insert($this->table, $data);
        return $this->db->insert_id();
    }

    public function update_user(int $id, array $data): bool
    {
        return $this->db->where('id', $id)->update($this->table, $data);
    }

    public function delete_user(int $id): bool
    {
        return $this->db->where('id', $id)
            ->update($this->table, ['deleted_at' => date('Y-m-d H:i:s')]);
    }

    public function find_active_by_role(string $role): array
    {
        return $this->db->where('is_active', 1)
            ->where('role', $role)
            ->where('deleted_at IS NULL')
            ->order_by('created_at', 'DESC')
            ->get($this->table)
            ->result_array();
    }
}
```

---

## 3. Query Builder

### CodeIgniter 4

```php
$db = \Config\Database::connect();
$builder = $db->table('users');

// SELECT
$users = $builder->select('id, email, name')
    ->where('is_active', true)
    ->whereIn('role', ['admin', 'manager'])
    ->like('name', $search)
    ->orderBy('created_at', 'DESC')
    ->limit(20, 0)
    ->get()
    ->getResultArray();

// JOIN
$orders = $db->table('orders o')
    ->select('o.*, u.name as user_name, u.email')
    ->join('users u', 'u.id = o.user_id')
    ->where('o.status', 'completed')
    ->where('o.created_at >=', $startDate)
    ->get()
    ->getResultArray();

// Subquery
$subQuery = $db->table('orders')
    ->select('user_id, COUNT(*) as order_count')
    ->groupBy('user_id');

$users = $db->table('users u')
    ->select('u.*, sub.order_count')
    ->join("({$subQuery->getCompiledSelect()}) sub", 'sub.user_id = u.id', 'left')
    ->get()
    ->getResultArray();

// INSERT BATCH
$db->table('logs')->insertBatch([
    ['action' => 'login', 'user_id' => 1, 'created_at' => date('Y-m-d H:i:s')],
    ['action' => 'login', 'user_id' => 2, 'created_at' => date('Y-m-d H:i:s')],
]);

// UPSERT (CI4.3+)
$db->table('user_settings')->upsertBatch($data);
```

### CodeIgniter 3

```php
// SELECT
$users = $this->db->select('id, email, name')
    ->where('is_active', 1)
    ->where_in('role', ['admin', 'manager'])
    ->like('name', $search)
    ->order_by('created_at', 'DESC')
    ->limit(20, 0)
    ->get('users')
    ->result_array();

// JOIN
$orders = $this->db->select('o.*, u.name as user_name')
    ->from('orders o')
    ->join('users u', 'u.id = o.user_id')
    ->where('o.status', 'completed')
    ->get()
    ->result_array();

// INSERT BATCH
$this->db->insert_batch('logs', $data);
```

---

## 4. 트랜잭션

### CodeIgniter 4

```php
$db = \Config\Database::connect();

// 자동 트랜잭션 (예외 시 자동 롤백)
$db->transStart();

$userModel->save($user);
$orderModel->save($order);
$db->table('audit_logs')->insert($logData);

$db->transComplete();

if ($db->transStatus() === false) {
    // 트랜잭션 실패 처리
    throw new \RuntimeException('Transaction failed');
}

// 수동 트랜잭션
$db->transBegin();
try {
    $userModel->save($user);
    $orderModel->save($order);
    $db->transCommit();
} catch (\Throwable $e) {
    $db->transRollback();
    throw $e;
}

// 중첩 트랜잭션 (Savepoint)
$db->transStart();
    $db->table('users')->update($id, $userData);

    $db->transStart(); // SAVEPOINT
        $db->table('orders')->insert($orderData);
    $db->transComplete();

$db->transComplete();
```

### CodeIgniter 3

```php
$this->db->trans_start();

$this->User_model->insert_user($data);
$this->Order_model->insert_order($orderData);

$this->db->trans_complete();

if ($this->db->trans_status() === FALSE) {
    // 실패 처리
}
```

---

## 5. 마이그레이션

### CodeIgniter 4

```php
// app/Database/Migrations/2024_01_15_000001_CreateUsersTable.php
namespace App\Database\Migrations;

use CodeIgniter\Database\Migration;

class CreateUsersTable extends Migration
{
    public function up()
    {
        $this->forge->addField([
            'id' => [
                'type' => 'INT',
                'constraint' => 11,
                'unsigned' => true,
                'auto_increment' => true,
            ],
            'email' => [
                'type' => 'VARCHAR',
                'constraint' => 255,
            ],
            'name' => [
                'type' => 'VARCHAR',
                'constraint' => 100,
            ],
            'password' => [
                'type' => 'VARCHAR',
                'constraint' => 255,
            ],
            'is_active' => [
                'type' => 'BOOLEAN',
                'default' => true,
            ],
            'role' => [
                'type' => 'ENUM',
                'constraint' => ['user', 'admin', 'manager'],
                'default' => 'user',
            ],
            'created_at' => ['type' => 'DATETIME', 'null' => true],
            'updated_at' => ['type' => 'DATETIME', 'null' => true],
            'deleted_at' => ['type' => 'DATETIME', 'null' => true],
        ]);

        $this->forge->addPrimaryKey('id');
        $this->forge->addUniqueKey('email');
        $this->forge->addKey('role');
        $this->forge->addKey('created_at');

        $this->forge->createTable('users');
    }

    public function down()
    {
        $this->forge->dropTable('users');
    }
}
```

```bash
# CI4 마이그레이션 명령어
php spark migrate
php spark migrate:rollback
php spark migrate:status
php spark make:migration CreateOrdersTable
```

### CodeIgniter 3

```php
// application/migrations/001_create_users.php
class Migration_Create_users extends CI_Migration
{
    public function up()
    {
        $this->dbforge->add_field([
            'id' => ['type' => 'INT', 'constraint' => 11, 'unsigned' => TRUE, 'auto_increment' => TRUE],
            'email' => ['type' => 'VARCHAR', 'constraint' => 255],
            'name' => ['type' => 'VARCHAR', 'constraint' => 100],
            'password' => ['type' => 'VARCHAR', 'constraint' => 255],
        ]);
        $this->dbforge->add_key('id', TRUE);
        $this->dbforge->create_table('users');
    }

    public function down()
    {
        $this->dbforge->drop_table('users');
    }
}
```

---

## 6. 시드 (Seed)

### CodeIgniter 4

```php
// app/Database/Seeds/UserSeeder.php
namespace App\Database\Seeds;

use CodeIgniter\Database\Seeder;

class UserSeeder extends Seeder
{
    public function run()
    {
        $data = [
            [
                'email' => 'admin@example.com',
                'name' => 'Admin',
                'password' => password_hash('admin1234', PASSWORD_ARGON2ID),
                'role' => 'admin',
                'is_active' => true,
                'created_at' => date('Y-m-d H:i:s'),
            ],
        ];

        $this->db->table('users')->insertBatch($data);
    }
}
```

```bash
php spark db:seed UserSeeder
```

---

## 7. Connection Pool / 다중 DB

```php
// CI4: app/Config/Database.php
public array $default = [
    'DSN'      => '',
    'hostname' => 'localhost',
    'username' => 'root',
    'password' => '',
    'database' => 'myapp',
    'DBDriver' => 'MySQLi',
    'port'     => 3306,
];

public array $readonly = [
    'DSN'      => '',
    'hostname' => 'replica.db.example.com',
    'username' => 'readonly',
    'password' => 'secret',
    'database' => 'myapp',
    'DBDriver' => 'MySQLi',
    'port'     => 3306,
];

// 사용
$readDb = \Config\Database::connect('readonly');
$result = $readDb->table('users')->get()->getResultArray();
```
