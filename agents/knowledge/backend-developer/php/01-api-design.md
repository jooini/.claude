# API Design

> PHP 버전 — CodeIgniter 3 & 4

---

## 1. RESTful 라우팅

### CodeIgniter 4

```php
// app/Config/Routes.php
$routes->group('api/v1', ['namespace' => 'App\Controllers\Api\V1', 'filter' => 'auth'], function ($routes) {
    $routes->get('users', 'UserController::index');
    $routes->get('users/(:num)', 'UserController::show/$1');
    $routes->post('users', 'UserController::create');
    $routes->put('users/(:num)', 'UserController::update/$1');
    $routes->delete('users/(:num)', 'UserController::delete/$1');
});

// Resource 라우트 (위와 동일한 효과)
$routes->resource('api/v1/users', ['controller' => 'Api\V1\UserController', 'filter' => 'auth']);
```

### CodeIgniter 3

```php
// application/config/routes.php
$route['api/v1/users']['GET'] = 'api/v1/UserController/index';
$route['api/v1/users/(:num)']['GET'] = 'api/v1/UserController/show/$1';
$route['api/v1/users']['POST'] = 'api/v1/UserController/create';
$route['api/v1/users/(:num)']['PUT'] = 'api/v1/UserController/update/$1';
$route['api/v1/users/(:num)']['DELETE'] = 'api/v1/UserController/delete/$1';
```

---

## 2. 컨트롤러 패턴

### CodeIgniter 4

```php
<?php

namespace App\Controllers\Api\V1;

use App\Controllers\BaseController;
use CodeIgniter\HTTP\ResponseInterface;
use App\Services\UserService;

class UserController extends BaseController
{
    private UserService $userService;

    public function __construct()
    {
        $this->userService = service('userService');
    }

    // GET /api/v1/users?page=1&size=20
    public function index(): ResponseInterface
    {
        $page = (int) $this->request->getGet('page', FILTER_SANITIZE_NUMBER_INT) ?: 1;
        $size = min((int) $this->request->getGet('size', FILTER_SANITIZE_NUMBER_INT) ?: 20, 100);

        $result = $this->userService->listUsers($page, $size);

        return $this->response->setJSON([
            'data' => $result['items'],
            'pagination' => [
                'page' => $page,
                'size' => $size,
                'total' => $result['total'],
                'totalPages' => ceil($result['total'] / $size),
            ],
        ]);
    }

    // GET /api/v1/users/:id
    public function show(int $id): ResponseInterface
    {
        $user = $this->userService->getUser($id);
        if (!$user) {
            return $this->response->setStatusCode(404)->setJSON([
                'type' => 'https://api.example.com/errors/not-found',
                'title' => 'User Not Found',
                'status' => 404,
                'detail' => "User with ID {$id} not found.",
            ]);
        }

        return $this->response->setJSON(['data' => $user]);
    }

    // POST /api/v1/users
    public function create(): ResponseInterface
    {
        $rules = [
            'email' => 'required|valid_email|is_unique[users.email]',
            'name'  => 'required|min_length[2]|max_length[50]',
            'password' => 'required|min_length[8]',
        ];

        if (!$this->validate($rules)) {
            return $this->response->setStatusCode(422)->setJSON([
                'type' => 'https://api.example.com/errors/validation',
                'title' => 'Validation Failed',
                'status' => 422,
                'errors' => $this->validator->getErrors(),
            ]);
        }

        $user = $this->userService->createUser($this->request->getJSON(true));

        return $this->response->setStatusCode(201)->setJSON(['data' => $user]);
    }
}
```

### CodeIgniter 3

```php
<?php
defined('BASEPATH') OR exit('No direct script access allowed');

class UserController extends CI_Controller
{
    public function __construct()
    {
        parent::__construct();
        $this->load->model('User_model');
        $this->load->library('form_validation');
    }

    // GET /api/v1/users
    public function index()
    {
        $page = max(1, (int) $this->input->get('page'));
        $size = min((int) $this->input->get('size') ?: 20, 100);

        $result = $this->User_model->get_paginated($page, $size);

        $this->output
            ->set_content_type('application/json')
            ->set_output(json_encode([
                'data' => $result['items'],
                'pagination' => [
                    'page' => $page,
                    'size' => $size,
                    'total' => $result['total'],
                ],
            ]));
    }

    // POST /api/v1/users
    public function create()
    {
        $input = json_decode($this->input->raw_input_stream, true);

        $this->form_validation->set_data($input);
        $this->form_validation->set_rules('email', 'Email', 'required|valid_email|is_unique[users.email]');
        $this->form_validation->set_rules('name', 'Name', 'required|min_length[2]|max_length[50]');
        $this->form_validation->set_rules('password', 'Password', 'required|min_length[8]');

        if (!$this->form_validation->run()) {
            $this->output
                ->set_status_header(422)
                ->set_content_type('application/json')
                ->set_output(json_encode([
                    'status' => 422,
                    'errors' => $this->form_validation->error_array(),
                ]));
            return;
        }

        $user = $this->User_model->create_user($input);

        $this->output
            ->set_status_header(201)
            ->set_content_type('application/json')
            ->set_output(json_encode(['data' => $user]));
    }
}
```

---

## 3. 요청/응답 DTO

### CodeIgniter 4 (PHP 8.1+)

```php
// app/DTOs/CreateUserRequest.php
readonly class CreateUserRequest
{
    public function __construct(
        public string $email,
        public string $name,
        public string $password,
        public ?string $phone = null,
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            email: $data['email'] ?? '',
            name: $data['name'] ?? '',
            password: $data['password'] ?? '',
            phone: $data['phone'] ?? null,
        );
    }
}

// app/DTOs/UserResponse.php
readonly class UserResponse
{
    public function __construct(
        public int $id,
        public string $email,
        public string $name,
        public string $createdAt,
    ) {}

    public static function fromEntity(array $user): self
    {
        return new self(
            id: (int) $user['id'],
            email: $user['email'],
            name: $user['name'],
            createdAt: $user['created_at'],
        );
    }
}
```

---

## 4. 페이지네이션

### CodeIgniter 4

```php
// 커서 기반 페이지네이션
public function listUsers(int $page, int $size): array
{
    $builder = $this->db->table('users');
    $total = $builder->countAllResults(false);
    $items = $builder->orderBy('id', 'DESC')
        ->limit($size, ($page - 1) * $size)
        ->get()
        ->getResultArray();

    return ['items' => $items, 'total' => $total];
}
```

### CodeIgniter 3

```php
public function get_paginated($page, $size)
{
    $offset = ($page - 1) * $size;
    $total = $this->db->count_all('users');
    $items = $this->db->order_by('id', 'DESC')
        ->limit($size, $offset)
        ->get('users')
        ->result_array();

    return ['items' => $items, 'total' => $total];
}
```

---

## 5. API 버전 관리

```php
// CI4: 네임스페이스로 분리
// app/Controllers/Api/V1/UserController.php
// app/Controllers/Api/V2/UserController.php

$routes->group('api/v1', ['namespace' => 'App\Controllers\Api\V1'], function ($routes) { ... });
$routes->group('api/v2', ['namespace' => 'App\Controllers\Api\V2'], function ($routes) { ... });

// CI3: 디렉토리로 분리
// application/controllers/api/v1/UserController.php
// application/controllers/api/v2/UserController.php
```

---

## 6. Content Negotiation

```php
// CI4
public function index(): ResponseInterface
{
    $data = $this->userService->listUsers();

    $negotiate = $this->request->negotiate('media', ['application/json', 'application/xml']);

    if ($negotiate === 'application/xml') {
        return $this->response
            ->setContentType('application/xml')
            ->setBody($this->arrayToXml($data));
    }

    return $this->response->setJSON($data);
}
```
