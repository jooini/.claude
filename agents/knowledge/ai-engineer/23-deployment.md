# AI System Deployment

> 참조 링크: https://docs.vllm.ai/, https://docs.aws.amazon.com/sagemaker/

---

## 1. 배포 아키텍처

### API 기반 (관리형)

```
사용자 → API Gateway → 애플리케이션 서버 → LLM API (OpenAI/Anthropic)
                                        → 벡터 DB (Pinecone/pgvector)
```

- **장점**: 인프라 관리 없음, 스케일링 자동
- **단점**: API 비용, 지연시간 제어 불가, 데이터 외부 전송

### 셀프호스팅

```
사용자 → API Gateway → 애플리케이션 서버 → 자체 LLM (vLLM/Ollama)
                                        → 자체 벡터 DB (pgvector/Qdrant)
```

- **장점**: 데이터 통제, 비용 예측 가능, 커스터마이징
- **단점**: GPU 인프라 관리, 운영 복잡도

## 2. 모델 서빙

### vLLM (고성능 추론 서버)

```bash
# 설치
pip install vllm

# 서버 시작
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-3-8B-Instruct \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.9 \
  --max-model-len 8192

# OpenAI 호환 API로 접근
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "meta-llama/Llama-3-8B-Instruct", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Ollama (간편한 로컬 실행)

```bash
# 모델 다운로드 + 실행
ollama pull llama3
ollama serve

# API 호출
curl http://localhost:11434/api/chat -d '{
  "model": "llama3",
  "messages": [{"role": "user", "content": "Hello"}]
}'
```

```typescript
// TypeScript에서 사용 (OpenAI SDK 호환)
import OpenAI from 'openai';

const ollama = new OpenAI({
  baseURL: 'http://localhost:11434/v1',
  apiKey: 'ollama', // 아무 값
});

const response = await ollama.chat.completions.create({
  model: 'llama3',
  messages: [{ role: 'user', content: 'Hello' }],
});
```

## 3. GPU 인프라

### 클라우드 GPU 옵션

| 서비스 | GPU | 비용 (시간당) | 적합 |
|--------|-----|-------------|------|
| AWS SageMaker | A10G, A100 | $1.5 ~ $30+ | 관리형 ML |
| AWS EC2 | A10G, A100 | $1 ~ $25 | 유연한 인프라 |
| GCP Vertex AI | T4, A100 | $1 ~ $25 | 관리형 ML |
| RunPod | A100, H100 | $0.7 ~ $4 | 저비용 GPU |
| Modal | A100, H100 | 사용량 기반 | 서버리스 GPU |

### GPU 메모리 요구사항

| 모델 크기 | FP16 | INT8 (양자화) | INT4 (QLoRA) |
|----------|------|-------------|-------------|
| 7B | 14GB | 7GB | 4GB |
| 13B | 26GB | 13GB | 7GB |
| 70B | 140GB | 70GB | 35GB |

## 4. 컨테이너화

### Dockerfile (추론 서버)

```dockerfile
FROM nvidia/cuda:12.1-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y python3 python3-pip
RUN pip3 install vllm

# 모델 다운로드 (빌드 시)
RUN python3 -c "from transformers import AutoModelForCausalLM; AutoModelForCausalLM.from_pretrained('meta-llama/Llama-3-8B-Instruct')"

EXPOSE 8000

CMD ["python3", "-m", "vllm.entrypoints.openai.api_server", \
     "--model", "meta-llama/Llama-3-8B-Instruct", \
     "--host", "0.0.0.0", "--port", "8000"]
```

### Docker Compose (전체 스택)

```yaml
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - LLM_BASE_URL=http://llm:8000/v1
      - VECTOR_DB_URL=postgresql://user:pass@postgres:5432/vectors
    depends_on:
      - llm
      - postgres

  llm:
    image: vllm/vllm-openai:latest
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    command: >
      --model meta-llama/Llama-3-8B-Instruct
      --gpu-memory-utilization 0.9

  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: vectors
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

## 5. 스케일링 전략

### 수평 스케일링

```yaml
# Kubernetes HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rag-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rag-api
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

### 로드 밸런싱

```
LB → App Server 1 → LLM API (rate limit 고려)
   → App Server 2 → LLM API
   → App Server 3 → LLM API

벡터 DB는 공유 (read replica 가능)
```

## 6. 환경 분리

| 환경 | LLM | 벡터 DB | 데이터 |
|------|-----|---------|--------|
| 개발 | Ollama (로컬) 또는 저비용 API | pgvector (로컬) | 샘플 |
| 스테이징 | 프로덕션과 동일 모델 | 프로덕션 복제본 | 익명화 |
| 프로덕션 | API 또는 vLLM | 프로덕션 DB | 실제 |

## 7. 헬스 체크

```typescript
// 전체 파이프라인 헬스 체크
app.get('/health', async (req, res) => {
  const checks = await Promise.allSettled([
    checkLLM(),        // LLM API 응답 확인
    checkVectorDB(),   // 벡터 DB 연결 확인
    checkEmbedding(),  // 임베딩 API 확인
  ]);

  const status = checks.every(c => c.status === 'fulfilled') ? 200 : 503;
  res.status(status).json({
    status: status === 200 ? 'healthy' : 'unhealthy',
    checks: {
      llm: checks[0].status,
      vectorDB: checks[1].status,
      embedding: checks[2].status,
    },
  });
});
```
