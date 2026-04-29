# /check-server - 서버 상태 확인

서버에 SSH 접속하여 Docker 컨테이너 상태, 로그, 헬스체크를 수행한다.

## 사용법

- `/check-server` - 기본 서버(dev2-backend) 전체 상태 확인
- `/check-server dev2-backend` - 특정 서버 지정
- `/check-server dev2-backend nginx` - 특정 서버의 특정 컨테이너 로그 확인

## 인자

$ARGUMENTS

## 수행 작업

### 1단계: 서버 접속 및 컨테이너 상태 확인

인자가 없으면 기본 서버는 `dev2-backend` (192.168.1.217)

```bash
ssh {서버} "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

결과를 테이블로 정리:
- 컨테이너 이름
- 상태 (Up/Exited/Restarting)
- 포트 매핑
- Unhealthy 컨테이너가 있으면 강조 표시

### 2단계: 문제 컨테이너 자동 진단

상태가 비정상인 컨테이너가 있으면:
```bash
ssh {서버} "docker logs --tail 30 {컨테이너명}"
```

### 3단계: 특정 컨테이너 지정 시

두 번째 인자로 컨테이너명이 지정되면 해당 컨테이너의:
- 최근 로그 50줄
- 리소스 사용량 (`docker stats --no-stream`)
- 네트워크 연결 상태

### 서버 목록 (SSH config 기준)

| 별칭 | 용도 |
|------|------|
| `dev2-backend` | B2C 개발서버 (192.168.1.217) |

### 주요 컨테이너

| 컨테이너 | 서비스 |
|----------|--------|
| `maxai-b2c-backend` | PHP 백엔드 |
| `maxai-b2c-frontend` | Vue 프론트엔드 |
| `maxai-nginx` | Nginx 리버스 프록시 |
| `dev-maxai-identity-hub` | Identity Hub |
| `dev-maxai-identity-keycloak` | Keycloak |
| `maxai-redis` | Redis |
| `maxai-postgres` | PostgreSQL |
| `maxai-b2c-engine` | B2C 엔진 |

### 출력 형식

상태를 한눈에 볼 수 있게 테이블로 정리하고, 문제가 있으면 원인과 해결 방법을 제시한다.
