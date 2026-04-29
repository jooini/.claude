# CodeIgniter ORM / Query Builder

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. CI4 Model CRUD

```php
$userModel = model('UserModel');

// CREATE
$user = new User(['email' => 'test@test.com', 'name' => 'Test']);
$userModel->save($user);
$id = $userModel->getInsertID();

// READ
$user = $userModel->find($id);                         // by PK
$users = $userModel->findAll();                        // 전체
$users = $userModel->where('role', 'admin')->findAll(); // 조건
$user = $userModel->where('email', $email)->first();   // 단일

// UPDATE
$userModel->update($id, ['name' => 'New Name']);
// 또는 Entity로
$user->name = 'New Name';
$userModel->save($user);

// DELETE
$userModel->delete($id);           // soft delete (설정 시)
$userModel->delete($id, true);     // hard delete
```

---

## 2. CI3 Active Record CRUD

```php
// CREATE
$this->db->insert('users', ['email' => 'test@test.com', 'name' => 'Test']);
$id = $this->db->insert_id();

// READ
$user = $this->db->get_where('users', ['id' => $id])->row_array();
$users = $this->db->get('users')->result_array();
$users = $this->db->where('role', 'admin')->get('users')->result_array();

// UPDATE
$this->db->where('id', $id)->update('users', ['name' => 'New Name']);

// DELETE
$this->db->where('id', $id)->delete('users');
```

---

## 3. 복합 쿼리

### WHERE 조건

```php
// CI4
$builder = $db->table('users');

// 기본
$builder->where('status', 'active');
$builder->where('age >=', 18);
$builder->where('email !=', null);

// OR
$builder->orWhere('role', 'admin');

// WHERE IN
$builder->whereIn('id', [1, 2, 3]);
$builder->whereNotIn('status', ['banned', 'suspended']);

// LIKE
$builder->like('name', $keyword);               // %keyword%
$builder->like('name', $keyword, 'after');       // keyword%
$builder->like('name', $keyword, 'before');      // %keyword

// BETWEEN (raw)
$builder->where('created_at >=', $start);
$builder->where('created_at <=', $end);

// NULL
$builder->where('deleted_at IS NULL');
$builder->where('deleted_at IS NOT NULL');

// 그룹 조건
$builder->groupStart()
    ->where('role', 'admin')
    ->orWhere('role', 'manager')
->groupEnd()
->where('is_active', true);
// → WHERE (role = 'admin' OR role = 'manager') AND is_active = 1

// CI3
$this->db->where('status', 'active');
$this->db->or_where('role', 'admin');
$this->db->where_in('id', [1, 2, 3]);
$this->db->like('name', $keyword);
```

### JOIN

```php
// CI4
$orders = $db->table('orders o')
    ->select('o.id, o.total, u.name, u.email')
    ->join('users u', 'u.id = o.user_id')
    ->join('order_items oi', 'oi.order_id = o.id', 'left')
    ->where('o.status', 'completed')
    ->groupBy('o.id')
    ->having('COUNT(oi.id) >', 0)
    ->orderBy('o.created_at', 'DESC')
    ->get()
    ->getResultArray();

// CI3
$this->db->select('o.id, o.total, u.name, u.email')
    ->from('orders o')
    ->join('users u', 'u.id = o.user_id')
    ->join('order_items oi', 'oi.order_id = o.id', 'left')
    ->where('o.status', 'completed')
    ->group_by('o.id')
    ->having('COUNT(oi.id) >', 0)
    ->order_by('o.created_at', 'DESC')
    ->get()
    ->result_array();
```

### 집계

```php
// CI4
$count = $builder->where('is_active', true)->countAllResults();
$avg = $db->table('orders')->selectAvg('total')->get()->getRow()->total;
$sum = $db->table('orders')->selectSum('total')->where('user_id', $userId)->get()->getRow()->total;

// CI3
$count = $this->db->where('is_active', 1)->count_all_results('users');
```

---

## 4. Raw SQL

```php
// CI4
$db = \Config\Database::connect();

// 파라미터 바인딩 (필수 — SQL Injection 방지)
$users = $db->query(
    "SELECT * FROM users WHERE role = ? AND created_at > ?",
    ['admin', '2024-01-01']
)->getResultArray();

// Named 바인딩
$users = $db->query(
    "SELECT * FROM users WHERE role = :role: AND email LIKE :email:",
    ['role' => 'admin', 'email' => '%@example.com']
)->getResultArray();

// CI3
$users = $this->db->query(
    "SELECT * FROM users WHERE role = ? AND created_at > ?",
    ['admin', '2024-01-01']
)->result_array();
```

---

## 5. Soft Delete

### CodeIgniter 4

```php
class UserModel extends Model
{
    protected $useSoftDeletes = true;
    protected $deletedField = 'deleted_at';

    // 삭제된 항목 포함 조회
    public function findAllIncludingDeleted(): array
    {
        return $this->withDeleted()->findAll();
    }

    // 삭제된 항목만 조회
    public function findOnlyDeleted(): array
    {
        return $this->onlyDeleted()->findAll();
    }

    // 복원
    public function restore(int $id): bool
    {
        return $this->update($id, ['deleted_at' => null]);
    }
}

// 사용
$userModel->delete($id);              // soft delete
$userModel->delete($id, true);        // hard delete (purge)
```

---

## 6. Eager Loading (N+1 방지)

```php
// CI4에는 내장 Eager Loading이 없음 — 수동 구현

class UserModel extends Model
{
    public function findWithOrders(int $userId): ?array
    {
        $user = $this->find($userId);
        if (!$user) return null;

        $user->orders = model('OrderModel')
            ->where('user_id', $userId)
            ->orderBy('created_at', 'DESC')
            ->findAll();

        return $user;
    }

    // 배치 로딩 (N+1 방지)
    public function loadOrdersForUsers(array $users): array
    {
        $userIds = array_column($users, 'id');
        if (empty($userIds)) return $users;

        $orders = model('OrderModel')
            ->whereIn('user_id', $userIds)
            ->findAll();

        // user_id별 그룹핑
        $orderMap = [];
        foreach ($orders as $order) {
            $orderMap[$order->user_id][] = $order;
        }

        // 유저에 할당
        foreach ($users as &$user) {
            $user->orders = $orderMap[$user->id] ?? [];
        }

        return $users;
    }
}
```

---

## 7. 쿼리 캐싱

```php
// CI4 — 결과 캐싱
$cache = \Config\Services::cache();

$users = $cache->get('active_users');
if ($users === null) {
    $users = model('UserModel')->where('is_active', true)->findAll();
    $cache->save('active_users', $users, 300); // 5분
}

// CI3 — 쿼리 캐싱
$this->db->cache_on();
$result = $this->db->get('users')->result_array();
$this->db->cache_off();
$this->db->cache_delete('users');  // 캐시 무효화
```

---

## 8. 페이지네이션

```php
// CI4 — 내장 Pager
class UserModel extends Model
{
    public function paginateActive(int $perPage = 20): array
    {
        return [
            'data' => $this->where('is_active', true)
                ->orderBy('created_at', 'DESC')
                ->paginate($perPage),
            'pager' => $this->pager,
        ];
    }
}

// Controller에서
$result = $this->userModel->paginateActive(20);
return $this->response->setJSON([
    'data' => $result['data'],
    'pagination' => [
        'total' => $result['pager']->getTotal(),
        'perPage' => $result['pager']->getPerPage(),
        'currentPage' => $result['pager']->getCurrentPage(),
        'pageCount' => $result['pager']->getPageCount(),
    ],
]);
```
