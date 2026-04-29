# Multimodal Processing

> 참조 링크: https://docs.anthropic.com/en/docs/build-with-claude/vision, https://platform.openai.com/docs/guides/vision

---

## 1. 멀티모달 입력 유형

| 유형 | Claude | GPT-4o | 용도 |
|------|--------|--------|------|
| 이미지 | ✅ | ✅ | OCR, 분석, 설명 |
| PDF | ✅ | ✅ (이미지 변환) | 문서 분석 |
| 오디오 | ❌ | ✅ (GPT-4o-audio) | 음성 인식 |
| 비디오 | ❌ | ❌ (프레임 추출) | 프레임 단위 분석 |

## 2. 이미지 입력

### Anthropic (Claude)

```typescript
import Anthropic from '@anthropic-ai/sdk';
import fs from 'fs';

const client = new Anthropic();

// Base64 인코딩
const imageData = fs.readFileSync('image.png').toString('base64');

const response = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  messages: [{
    role: 'user',
    content: [
      {
        type: 'image',
        source: {
          type: 'base64',
          media_type: 'image/png',
          data: imageData,
        },
      },
      {
        type: 'text',
        text: '이 이미지에서 텍스트를 추출해주세요.',
      },
    ],
  }],
});

// URL 기반
const response2 = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  messages: [{
    role: 'user',
    content: [
      {
        type: 'image',
        source: {
          type: 'url',
          url: 'https://example.com/image.png',
        },
      },
      { type: 'text', text: '이 이미지를 설명해주세요.' },
    ],
  }],
});
```

### OpenAI (GPT-4o)

```typescript
const response = await openai.chat.completions.create({
  model: 'gpt-4o',
  messages: [{
    role: 'user',
    content: [
      {
        type: 'image_url',
        image_url: {
          url: `data:image/png;base64,${imageData}`,
          detail: 'high', // 'low' | 'high' | 'auto'
        },
      },
      { type: 'text', text: '이 이미지에서 텍스트를 추출해주세요.' },
    ],
  }],
});
```

## 3. PDF 처리

### Claude PDF 입력

```typescript
const pdfData = fs.readFileSync('document.pdf').toString('base64');

const response = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 4096,
  messages: [{
    role: 'user',
    content: [
      {
        type: 'document',
        source: {
          type: 'base64',
          media_type: 'application/pdf',
          data: pdfData,
        },
      },
      { type: 'text', text: '이 문서를 요약해주세요.' },
    ],
  }],
});
```

### PDF → 이미지 변환 (범용)

```python
# pdf2image
from pdf2image import convert_from_path

images = convert_from_path('document.pdf', dpi=150)
for i, img in enumerate(images):
    img.save(f'page_{i+1}.png')
```

## 4. 멀티모달 임베딩

이미지와 텍스트를 같은 벡터 공간에 임베딩하여 크로스모달 검색을 가능하게 한다.

### CLIP 기반

```python
from transformers import CLIPModel, CLIPProcessor

model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")

# 이미지 임베딩
image = Image.open("photo.jpg")
inputs = processor(images=image, return_tensors="pt")
image_embedding = model.get_image_features(**inputs).detach().numpy()[0]

# 텍스트 임베딩
inputs = processor(text="a photo of a cat", return_tensors="pt")
text_embedding = model.get_text_features(**inputs).detach().numpy()[0]

# 코사인 유사도로 이미지-텍스트 매칭
similarity = np.dot(image_embedding, text_embedding) / (
    np.linalg.norm(image_embedding) * np.linalg.norm(text_embedding)
)
```

### Voyage Multimodal

```typescript
const response = await fetch('https://api.voyageai.com/v1/multimodalembeddings', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${VOYAGE_API_KEY}`,
  },
  body: JSON.stringify({
    model: 'voyage-multimodal-3',
    inputs: [
      { content: [{ type: 'text', text: 'a cat sitting on a desk' }] },
      { content: [{ type: 'image_base64', image_base64: imageData }] },
    ],
    input_type: 'document',
  }),
});
```

## 5. OCR 파이프라인

### LLM 기반 OCR

```typescript
async function ocrWithLLM(imagePath: string): Promise<string> {
  const imageData = fs.readFileSync(imagePath).toString('base64');

  const response = await client.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 4096,
    messages: [{
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: imageData } },
        { type: 'text', text: '이 이미지의 모든 텍스트를 정확하게 추출하세요. 원본 레이아웃을 최대한 보존하세요.' },
      ],
    }],
  });

  return response.content[0].text;
}
```

### 전통적 OCR (Tesseract)

```python
import pytesseract
from PIL import Image

text = pytesseract.image_to_string(Image.open('image.png'), lang='kor+eng')
```

## 6. 이미지 분석 패턴

```typescript
// 구조화된 이미지 분석
const response = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 2048,
  messages: [{
    role: 'user',
    content: [
      { type: 'image', source: { type: 'base64', media_type: 'image/png', data: screenshotData } },
      { type: 'text', text: `이 UI 스크린샷을 분석하세요. JSON으로 응답:
{
  "components": [컴포넌트 목록],
  "layout": "레이아웃 설명",
  "issues": [발견된 UX 이슈],
  "accessibility": [접근성 문제]
}` },
    ],
  }],
});
```

## 7. 비용 고려

| 입력 유형 | Claude 비용 | GPT-4o 비용 |
|----------|-----------|-----------|
| 이미지 (low-res) | ~300 토큰 | 85 토큰 |
| 이미지 (high-res) | ~1600 토큰 | 최대 1105 토큰 |
| PDF (10페이지) | ~1500 토큰/페이지 | 이미지 변환 비용 |

이미지가 많은 경우 `detail: 'low'` 옵션으로 비용을 크게 줄일 수 있다.
