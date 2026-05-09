# Networking

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/networking

---

## 1. HTTP/HTTPS 핵심

```
HTTP/1.1 — 요청당 TCP 연결 (Keep-Alive로 재사용)
HTTP/2   — 멀티플렉싱, 헤더 압축, 서버 푸시
HTTP/3   — QUIC 기반, UDP, 연결 속도 개선
```

### Keep-Alive & Connection Pool

```ts
// axios — HTTP 클라이언트에서 연결 재사용
import axios from 'axios'
import http from 'http'
import https from 'https'

const client = axios.create({
  baseURL: 'https://api.external.com',
  timeout: 5000,
  httpAgent:  new http.Agent({ keepAlive: true, maxSockets: 50 }),
  httpsAgent: new https.Agent({ keepAlive: true, maxSockets: 50 }),
})
```

---

## 2. TCP/IP 기초

```
Application Layer  — HTTP, WebSocket, gRPC
Transport Layer    — TCP (신뢰성), UDP (속도)
Network Layer      — IP, 라우팅
Link Layer         — Ethernet, Wi-Fi

TCP 3-way Handshake:
  Client → SYN      → Server
  Client ← SYN-ACK  ← Server
  Client → ACK       → Server
  (연결 수립 후 데이터 전송)

TCP 4-way Termination:
  Client → FIN → Server
  Client ← ACK ← Server
  Client ← FIN ← Server
  Client → ACK → Server
```

---

## 3. WebSocket

실시간 양방향 통신. HTTP 업그레이드로 연결 수립 후 지속 연결.

```ts
// NestJS WebSocket Gateway
import { WebSocketGateway, WebSocketServer, SubscribeMessage, MessageBody, ConnectedSocket } from '@nestjs/websockets'
import { Server, Socket } from 'socket.io'

@WebSocketGateway({
  cors: { origin: process.env.ALLOWED_ORIGINS?.split(',') },
  namespace: '/chat',
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server

  private readonly logger = new Logger(ChatGateway.name)

  async handleConnection(client: Socket) {
    const userId = client.handshake.auth.userId
    if (!userId) { client.disconnect(); return }

    await client.join(`user:${userId}`)  // 개인 룸
    this.logger.log(`Client connected: ${client.id}`)
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`Client disconnected: ${client.id}`)
  }

  @SubscribeMessage('join-room')
  async handleJoinRoom(
    @MessageBody() data: { roomId: string },
    @ConnectedSocket() client: Socket,
  ) {
    await client.join(`room:${data.roomId}`)
    client.emit('joined', { roomId: data.roomId })
  }

  @SubscribeMessage('send-message')
  async handleMessage(
    @MessageBody() data: { roomId: string; content: string },
    @ConnectedSocket() client: Socket,
  ) {
    const message = await this.chatService.saveMessage(data)
    // 룸의 모든 클라이언트에게 브로드캐스트
    this.server.to(`room:${data.roomId}`).emit('new-message', message)
  }

  // 서버에서 특정 유저에게 push
  sendToUser(userId: string, event: string, data: unknown) {
    this.server.to(`user:${userId}`).emit(event, data)
  }
}
```

### 수평 확장 시 Socket.IO Redis Adapter

```ts
import { createAdapter } from '@socket.io/redis-adapter'
import { Redis } from 'ioredis'

const pubClient = new Redis({ host: process.env.REDIS_HOST })
const subClient = pubClient.duplicate()

io.adapter(createAdapter(pubClient, subClient))
// 이제 여러 서버 인스턴스 간 이벤트 공유
```

---

## 4. gRPC

서비스 간 통신. Protocol Buffers로 직렬화. HTTP/2 기반.

```proto
// user.proto
syntax = "proto3";

service UserService {
  rpc GetUser (GetUserRequest) returns (UserResponse);
  rpc ListUsers (ListUsersRequest) returns (stream UserResponse);
}

message GetUserRequest { string id = 1; }
message UserResponse {
  string id = 1;
  string name = 2;
  string email = 3;
}
```

```ts
// NestJS gRPC 서버
@Controller()
@GrpcMethod('UserService', 'GetUser')
async getUser(data: GetUserRequest): Promise<UserResponse> {
  const user = await this.usersService.findById(data.id)
  return { id: user.id, name: user.name, email: user.email }
}

// gRPC 클라이언트
@Injectable()
export class UserGrpcClient {
  private client: UserServiceClient

  onModuleInit() {
    this.client = ClientGrpc.getService<UserServiceClient>('UserService')
  }

  getUser(id: string): Observable<UserResponse> {
    return this.client.getUser({ id })
  }
}
```

**REST vs gRPC:**
| | REST | gRPC |
|-|------|------|
| 프로토콜 | HTTP/1.1+ JSON | HTTP/2 + Protobuf |
| 속도 | 보통 | 빠름 (바이너리) |
| 스트리밍 | 제한적 | 양방향 스트리밍 |
| 타입 | OpenAPI(선택) | .proto 강제 |
| 브라우저 | 직접 지원 | grpc-web 필요 |

---

## 5. DNS

```ts
import dns from 'dns/promises'

// DNS 조회
const addresses = await dns.resolve4('api.example.com')

// DNS 캐싱 — 매 요청마다 DNS 조회 방지
// Node.js 기본적으로 DNS 캐싱 없음
// 해결: dns-cache 패키지 또는 OS 레벨 캐시 활용

// 서비스 디스커버리에서는 consul, etcd 등 활용
```

---

## 6. 네트워크 보안

```ts
// TLS 설정
import https from 'https'
import fs from 'fs'

const server = https.createServer({
  key:  fs.readFileSync('private.key'),
  cert: fs.readFileSync('certificate.crt'),
  // 최소 TLS 버전
  minVersion: 'TLSv1.2',
  // 권장 cipher suite
  ciphers: [
    'ECDHE-RSA-AES128-GCM-SHA256',
    'ECDHE-RSA-AES256-GCM-SHA384',
  ].join(':'),
}, app.callback())

// NestJS에서는 main.ts에서 설정
const httpsOptions = {
  key:  fs.readFileSync('./secrets/private-key.pem'),
  cert: fs.readFileSync('./secrets/public-certificate.pem'),
}
const app = await NestFactory.create(AppModule, { httpsOptions })
```

---

## 7. 안티패턴

- **HTTP 재사용 없이 매 요청 새 연결**: Keep-Alive + Connection Pool
- **WebSocket 수평 확장 미고려**: Redis Adapter 없이 다중 서버
- **내부 서비스 간 HTTPS 오버헤드**: 동일 VPC 내에서는 HTTP + 네트워크 레벨 보안
- **DNS 하드코딩 IP**: 환경별 DNS 사용, IP 직접 사용 금지
- **타임아웃 없는 HTTP 요청**: 외부 API 호출은 반드시 timeout 설정
