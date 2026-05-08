# Microservices

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/microservices

---

## 1. 마이크로서비스 vs 모노리스

```
모노리스 → 마이크로서비스 전환 시점:
  ✅ 팀 규모 20명 이상
  ✅ 도메인 경계가 명확
  ✅ 서비스별 독립 배포 필요
  ✅ 스케일링 요구가 서비스마다 다름

아직 모노리스가 나은 경우:
  - 스타트업 초기 (속도가 중요)
  - 도메인 경계 불명확
  - 소규모 팀
```

---

## 2. NestJS 마이크로서비스

```ts
// 서비스 서버 — TCP 트랜스포트
const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
  transport: Transport.TCP,
  options: { host: '0.0.0.0', port: 3001 },
})
await app.listen()

// 메시지 핸들러
@Controller()
export class UsersController {
  @MessagePattern('find_user')
  findOne(@Payload() data: { id: string }) {
    return this.usersService.findById(data.id)
  }

  @EventPattern('user_created')  // 응답 없는 이벤트
  async handleUserCreated(@Payload() data: UserCreatedEvent) {
    await this.notificationService.sendWelcome(data.email)
  }
}

// 클라이언트 — 다른 서비스에서 호출
@Module({
  imports: [
    ClientsModule.register([{
      name: 'USER_SERVICE',
      transport: Transport.TCP,
      options: { host: 'user-service', port: 3001 },
    }]),
  ],
})

@Injectable()
export class OrdersService {
  constructor(@Inject('USER_SERVICE') private userClient: ClientProxy) {}

  async createOrder(dto: CreateOrderDto) {
    // 요청-응답
    const user = await firstValueFrom(
      this.userClient.send('find_user', { id: dto.userId })
    )

    // 이벤트 발행 (응답 불필요)
    this.userClient.emit('order_created', { orderId: newOrder.id, userId: dto.userId })

    return newOrder
  }
}
```

---

## 3. API Gateway 패턴

```
클라이언트 → API Gateway → 사용자 서비스
                        → 주문 서비스
                        → 결제 서비스

역할:
- 라우팅
- 인증/인가 (단일 진입점)
- 레이트 리밋
- 로드밸런싱
- 서킷 브레이커
- 요청 집계 (BFF)
```

```ts
// NestJS API Gateway
@Controller()
export class GatewayController {
  constructor(
    @Inject('USER_SERVICE') private userService: ClientProxy,
    @Inject('ORDER_SERVICE') private orderService: ClientProxy,
  ) {}

  @Get('users/:id/dashboard')
  @UseGuards(JwtAuthGuard)
  async getDashboard(@Param('id') userId: string) {
    // 여러 서비스 데이터 집계 (BFF 패턴)
    const [user, orders, points] = await Promise.all([
      firstValueFrom(this.userService.send('find_user', { id: userId })),
      firstValueFrom(this.orderService.send('find_orders', { userId })),
      firstValueFrom(this.userService.send('find_points', { userId })),
    ])

    return { user, orders, points }
  }
}
```

---

## 4. 서비스 디스커버리

```ts
// 환경 변수 기반 (단순)
const USER_SERVICE_URL = process.env.USER_SERVICE_URL  // k8s Service DNS

// Consul 기반 (동적)
import Consul from 'consul'

const consul = new Consul({ host: 'consul' })

// 서비스 등록
await consul.agent.service.register({
  name: 'order-service',
  address: os.hostname(),
  port: 3000,
  check: {
    http: `http://${os.hostname()}:3000/health`,
    interval: '10s',
  },
})

// 서비스 조회
const services = await consul.health.service({ service: 'user-service', passing: true })
const { Address, Port } = services[0].Service
```

---

## 5. 서비스 간 인증

```ts
// 서비스 간 통신에 API Key 또는 mTLS

// API Key 방식
@Injectable()
export class InternalAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest()
    const apiKey = request.headers['x-internal-api-key']
    return apiKey === process.env.INTERNAL_API_KEY
  }
}

// JWT 서비스 토큰 방식
@Injectable()
export class ServiceTokenInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler) {
    const token = this.authService.generateServiceToken('order-service')
    // 헤더에 서비스 토큰 추가
    return next.handle()
  }
}
```

---

## 6. 배포 전략

```yaml
# Kubernetes Service
apiVersion: v1
kind: Service
metadata:
  name: user-service
spec:
  selector:
    app: user-service
  ports:
    - port: 80
      targetPort: 3000
  type: ClusterIP  # 내부 서비스

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    spec:
      containers:
        - name: user-service
          image: user-service:latest
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: 500m, memory: 512Mi }
          readinessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 10
```

---

## 7. 안티패턴

- **데이터 공유**: 서비스 간 DB 공유 → 독립 DB, API 통신
- **동기 호출 체인 남발**: A→B→C→D 체인 — 이벤트 기반으로
- **너무 작은 서비스**: 1~2개 함수짜리 서비스 → 모노리스로
- **분산 모노리스**: 배포는 마이크로서비스, 결합도는 모노리스
- **API Gateway 없는 직접 노출**: 내부 서비스를 클라이언트에 직접 노출
