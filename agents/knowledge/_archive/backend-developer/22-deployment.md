# Deployment

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/deployment

---

## 1. Docker

```dockerfile
# Dockerfile — 멀티 스테이지 빌드
# Stage 1: 빌드
FROM node:20-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production  # lockfile 기반, dev deps 제외

COPY . .
RUN npm run build

# Stage 2: 런타임 (최소 이미지)
FROM node:20-alpine AS runner
WORKDIR /app

# 보안: non-root 유저
RUN addgroup --system --gid 1001 nodejs
RUN adduser  --system --uid 1001 nestjs

COPY --from=builder --chown=nestjs:nodejs /app/dist ./dist
COPY --from=builder --chown=nestjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nestjs:nodejs /app/package.json ./

USER nestjs

EXPOSE 3000
ENV NODE_ENV=production

CMD ["node", "dist/main.js"]
```

```yaml
# docker-compose.yml (로컬 개발)
version: '3.8'
services:
  api:
    build: .
    ports: ['3000:3000']
    environment:
      DATABASE_URL: postgresql://user:pass@db:5432/mydb
      REDIS_HOST: redis
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U user -d mydb']
      interval: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

---

## 2. Kubernetes

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # 최대 초과 파드 수
      maxUnavailable: 0  # 다운타임 없는 배포
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: ghcr.io/company/api:v1.2.3
          ports:
            - containerPort: 3000
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: api-secrets
                  key: database-url
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 30
            periodSeconds: 10

---
# HPA — 자동 스케일링
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## 3. GitHub Actions CD

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build & Push Docker Image
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Deploy to Kubernetes
        uses: azure/k8s-deploy@v4
        with:
          manifests: k8s/
          images: ghcr.io/${{ github.repository }}:${{ github.sha }}
          strategy: rolling
```

---

## 4. 환경 분리

```
dev       → 개발자 로컬/개발 서버, 자동 배포 (feature 브랜치)
staging   → QA, 운영 동일 설정, 주기적 배포 (develop 브랜치)
production→ 실 사용자, 수동 승인 후 배포 (main 브랜치)
```

```yaml
# Kubernetes namespace로 환경 분리
kubectl create namespace staging
kubectl create namespace production

# 환경별 ConfigMap
kubectl create configmap api-config \
  --from-literal=LOG_LEVEL=debug \
  -n staging

kubectl create configmap api-config \
  --from-literal=LOG_LEVEL=warn \
  -n production
```

---

## 5. 배포 전략

```
Rolling Update  — 기본. 순차 교체, 다운타임 없음
Blue/Green      — 두 환경 운영, 즉시 전환/롤백
Canary          — 일부 트래픽만 새 버전으로, 점진적 확대
Feature Flags   — 코드 배포와 기능 활성화 분리
```

```ts
// Feature Flag — 코드 배포 없이 기능 ON/OFF
@Injectable()
export class FeatureFlagService {
  async isEnabled(flag: string, userId?: string): Promise<boolean> {
    const config = await this.redis.hget('feature:flags', flag)
    if (!config) return false

    const { enabled, percentage, userIds } = JSON.parse(config)
    if (!enabled) return false
    if (userIds?.includes(userId)) return true  // 특정 유저 허용
    if (percentage && userId) {
      // 사용자 ID 해시로 일관된 비율 적용
      const hash = crc32(userId) % 100
      return hash < percentage
    }
    return enabled
  }
}
```

---

## 6. 안티패턴

- **root로 컨테이너 실행**: 보안 취약 → non-root 유저
- **Secrets를 이미지에 포함**: Kubernetes Secrets 또는 Vault 사용
- **readinessProbe 없음**: 준비 안 된 파드에 트래픽 전달
- **resource limit 없음**: 한 파드가 노드 자원 독점
- **운영에 latest 태그**: 불확실한 버전 → 커밋 SHA 또는 시맨틱 버전
