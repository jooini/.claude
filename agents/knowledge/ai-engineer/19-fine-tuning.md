# Fine-tuning

> 참조 링크: https://platform.openai.com/docs/guides/fine-tuning, https://huggingface.co/docs/peft

---

## 1. 파인튜닝 vs 프롬프트 엔지니어링

| | 프롬프트 엔지니어링 | RAG | 파인튜닝 |
|---|----------------|-----|---------|
| 비용 | 낮음 | 중간 | 높음 (학습) |
| 지식 업데이트 | 즉시 | 즉시 (인덱스) | 재학습 필요 |
| 커스텀 스타일 | 제한적 | 제한적 | ✅ 강력 |
| 도메인 특화 | 제한적 | ✅ (외부 지식) | ✅ (내재화) |
| 적합한 경우 | 일반 작업 | 지식 기반 Q&A | 스타일/형식 통일 |

### 파인튜닝이 필요한 경우

- 특정 출력 형식을 일관되게 유지해야 할 때
- 도메인 전문 용어/스타일이 중요할 때
- 프롬프트로는 달성 불가능한 행동 패턴이 필요할 때
- 비용 절감: 긴 시스템 프롬프트를 모델에 내재화하여 토큰 절약

## 2. 데이터 준비

### OpenAI Fine-tuning 데이터 형식

```jsonl
{"messages": [{"role": "system", "content": "You are a medical assistant."}, {"role": "user", "content": "두통이 있어요."}, {"role": "assistant", "content": "두통의 양상을 자세히 말씀해주세요. 어느 부위에서 느껴지나요? 욱신거리는 통증인가요, 아니면 조이는 느낌인가요?"}]}
{"messages": [{"role": "system", "content": "You are a medical assistant."}, {"role": "user", "content": "배가 아파요."}, {"role": "assistant", "content": "복부 통증의 위치와 양상을 알려주세요. 오른쪽인가요 왼쪽인가요? 식사 전후로 차이가 있나요?"}]}
```

### 데이터 품질 체크리스트

- [ ] 최소 50~100개 이상의 예시 (권장 300+)
- [ ] 다양한 입력 패턴 포함
- [ ] 일관된 출력 스타일
- [ ] 엣지 케이스 포함
- [ ] PII/민감 정보 제거
- [ ] 중복 제거
- [ ] 레이블 품질 검증 (사람이 리뷰)

### 데이터 검증

```python
import json

def validate_training_data(filepath: str) -> dict:
    issues = []
    total = 0
    token_counts = []

    with open(filepath) as f:
        for i, line in enumerate(f):
            total += 1
            data = json.loads(line)
            messages = data.get('messages', [])

            # 필수 역할 확인
            roles = [m['role'] for m in messages]
            if 'assistant' not in roles:
                issues.append(f"Line {i}: missing assistant message")
            if 'user' not in roles:
                issues.append(f"Line {i}: missing user message")

            # 빈 메시지 확인
            for m in messages:
                if not m.get('content', '').strip():
                    issues.append(f"Line {i}: empty content for {m['role']}")

    return {'total': total, 'issues': issues}
```

## 3. OpenAI Fine-tuning

```typescript
import OpenAI from 'openai';

const openai = new OpenAI();

// 1. 파일 업로드
const file = await openai.files.create({
  file: fs.createReadStream('training_data.jsonl'),
  purpose: 'fine-tune',
});

// 2. 파인튜닝 작업 생성
const job = await openai.fineTuning.jobs.create({
  training_file: file.id,
  model: 'gpt-4o-mini-2024-07-18',
  hyperparameters: {
    n_epochs: 3,
    learning_rate_multiplier: 1.8,
    batch_size: 'auto',
  },
});

// 3. 진행 상태 확인
const status = await openai.fineTuning.jobs.retrieve(job.id);
console.log(status.status); // 'validating_files' → 'running' → 'succeeded'

// 4. 사용
const response = await openai.chat.completions.create({
  model: status.fine_tuned_model!, // 'ft:gpt-4o-mini-...'
  messages: [{ role: 'user', content: '두통이 있어요.' }],
});
```

## 4. LoRA / QLoRA (경량 튜닝)

전체 모델 가중치를 업데이트하지 않고, **저랭크 어댑터**만 학습한다.

### LoRA 장점

| | Full Fine-tuning | LoRA | QLoRA |
|---|-----------------|------|-------|
| GPU 메모리 | 80GB+ (7B 모델) | 16GB | 6GB |
| 학습 시간 | 수시간 | 수십분 | 수십분 |
| 저장 공간 | 모델 전체 | ~100MB | ~100MB |
| 성능 | 100% | ~95-99% | ~93-97% |

### Hugging Face PEFT

```python
from peft import LoraConfig, get_peft_model, TaskType
from transformers import AutoModelForCausalLM, AutoTokenizer, TrainingArguments
from trl import SFTTrainer

# 모델 로드
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3-8B",
    torch_dtype=torch.float16,
    device_map="auto",
)
tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-3-8B")

# LoRA 설정
lora_config = LoraConfig(
    r=16,                    # 랭크 (높을수록 표현력↑, 메모리↑)
    lora_alpha=32,           # 스케일링 팩터
    target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type=TaskType.CAUSAL_LM,
)

model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
# trainable params: 3.4M || all params: 8B || trainable%: 0.04%

# 학습
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    args=TrainingArguments(
        output_dir="./output",
        num_train_epochs=3,
        per_device_train_batch_size=4,
        learning_rate=2e-4,
        fp16=True,
        logging_steps=10,
        save_strategy="epoch",
    ),
    max_seq_length=2048,
)

trainer.train()
model.save_pretrained("./lora-adapter")
```

### QLoRA (4bit 양자화)

```python
from transformers import BitsAndBytesConfig

bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_use_double_quant=True,
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3-8B",
    quantization_config=bnb_config,
    device_map="auto",
)
# 이후 LoRA 적용 동일
```

## 5. 평가

```python
# 테스트셋으로 성능 비교
# 파인튜닝 전 vs 후

metrics = {
    'accuracy': evaluate_accuracy(test_set, finetuned_model),
    'format_compliance': evaluate_format(test_set, finetuned_model),
    'style_consistency': evaluate_style(test_set, finetuned_model),
}
```

## 6. 주의사항

- **과적합**: 데이터가 적으면 학습 데이터를 외우게 됨 → validation set으로 모니터링
- **catastrophic forgetting**: 기존 능력이 저하될 수 있음 → 다양한 데이터 포함
- **데이터 품질 > 데이터 양**: 100개의 고품질 데이터가 1000개의 저품질보다 나음
- **비용**: OpenAI 파인튜닝은 토큰당 비용 + 모델 호스팅 비용 추가
