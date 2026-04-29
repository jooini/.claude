# 추천 시스템

> 참조 링크: https://developers.google.com/machine-learning/recommendation, https://arxiv.org/abs/2209.01860

---

## 1. 추천 시스템 유형

| 유형 | 원리 | 장점 | 단점 |
|------|------|------|------|
| **콘텐츠 기반 (CBF)** | 아이템 특성 유사도 | 콜드 스타트(아이템) 대응 | 다양성 부족 |
| **협업 필터링 (CF)** | 사용자 행동 패턴 유사도 | 예상 못한 아이템 추천 | 콜드 스타트(사용자) |
| **하이브리드** | CBF + CF 결합 | 양쪽 장점 | 복잡도 증가 |
| **지식 기반** | 명시적 규칙/제약 | 설명 가능 | 규칙 수동 관리 |

## 2. 콘텐츠 기반 필터링

아이템의 속성(특성)과 사용자 선호 프로필을 매칭한다.

### 아이템 임베딩 기반 추천

```typescript
interface Item {
  id: string;
  title: string;
  description: string;
  tags: string[];
  embedding?: number[];
}

class ContentBasedRecommender {
  private openai: OpenAI;

  // 아이템 임베딩 생성
  async embedItems(items: Item[]): Promise<Item[]> {
    const texts = items.map(item =>
      `${item.title}. ${item.description}. 태그: ${item.tags.join(', ')}`
    );

    const response = await this.openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: texts,
    });

    return items.map((item, i) => ({
      ...item,
      embedding: response.data[i].embedding,
    }));
  }

  // 사용자가 좋아한 아이템들의 평균 임베딩으로 추천
  async recommend(likedItems: Item[], allItems: Item[], topK: number = 10): Promise<Item[]> {
    // 사용자 프로필 = 좋아한 아이템들의 평균 임베딩
    const userProfile = this.averageEmbedding(likedItems.map(i => i.embedding!));

    // 모든 아이템과의 유사도 계산
    const scored = allItems
      .filter(item => !likedItems.some(liked => liked.id === item.id)) // 이미 본 것 제외
      .map(item => ({
        item,
        score: this.cosineSimilarity(userProfile, item.embedding!),
      }))
      .sort((a, b) => b.score - a.score);

    return scored.slice(0, topK).map(s => s.item);
  }

  private averageEmbedding(embeddings: number[][]): number[] {
    const dim = embeddings[0].length;
    const avg = new Array(dim).fill(0);
    for (const emb of embeddings) {
      for (let i = 0; i < dim; i++) avg[i] += emb[i];
    }
    return avg.map(v => v / embeddings.length);
  }

  private cosineSimilarity(a: number[], b: number[]): number {
    let dot = 0, normA = 0, normB = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
  }
}
```

### TF-IDF 기반 추천

```typescript
class TFIDFRecommender {
  private vocabulary: Map<string, number> = new Map();
  private idf: Map<string, number> = new Map();

  // 문서 집합으로 IDF 계산
  fit(documents: string[]): void {
    const docCount = documents.length;
    const docFreq = new Map<string, number>();

    for (const doc of documents) {
      const uniqueTerms = new Set(this.tokenize(doc));
      for (const term of uniqueTerms) {
        docFreq.set(term, (docFreq.get(term) ?? 0) + 1);
      }
    }

    for (const [term, freq] of docFreq) {
      this.idf.set(term, Math.log(docCount / (freq + 1)) + 1);
    }
  }

  // TF-IDF 벡터 생성
  transform(text: string): Map<string, number> {
    const terms = this.tokenize(text);
    const tf = new Map<string, number>();
    for (const term of terms) {
      tf.set(term, (tf.get(term) ?? 0) + 1 / terms.length);
    }

    const tfidf = new Map<string, number>();
    for (const [term, tfVal] of tf) {
      tfidf.set(term, tfVal * (this.idf.get(term) ?? 0));
    }
    return tfidf;
  }

  private tokenize(text: string): string[] {
    return text.toLowerCase().split(/\s+/).filter(t => t.length > 1);
  }
}
```

## 3. 협업 필터링

### User-Based CF

비슷한 취향의 사용자가 좋아한 아이템을 추천한다.

```typescript
interface UserRating {
  userId: string;
  itemId: string;
  rating: number; // 1~5
}

class UserBasedCF {
  private userRatings: Map<string, Map<string, number>> = new Map(); // userId → { itemId: rating }

  loadRatings(ratings: UserRating[]): void {
    for (const r of ratings) {
      if (!this.userRatings.has(r.userId)) this.userRatings.set(r.userId, new Map());
      this.userRatings.get(r.userId)!.set(r.itemId, r.rating);
    }
  }

  // 사용자 간 유사도 (피어슨 상관계수)
  userSimilarity(userA: string, userB: string): number {
    const ratingsA = this.userRatings.get(userA)!;
    const ratingsB = this.userRatings.get(userB)!;

    // 공통 아이템
    const common = [...ratingsA.keys()].filter(item => ratingsB.has(item));
    if (common.length === 0) return 0;

    const avgA = [...ratingsA.values()].reduce((a, b) => a + b, 0) / ratingsA.size;
    const avgB = [...ratingsB.values()].reduce((a, b) => a + b, 0) / ratingsB.size;

    let num = 0, denA = 0, denB = 0;
    for (const item of common) {
      const diffA = ratingsA.get(item)! - avgA;
      const diffB = ratingsB.get(item)! - avgB;
      num += diffA * diffB;
      denA += diffA * diffA;
      denB += diffB * diffB;
    }

    return denA === 0 || denB === 0 ? 0 : num / (Math.sqrt(denA) * Math.sqrt(denB));
  }

  // 추천: 유사 사용자들의 가중 평균으로 예측 평점 계산
  recommend(userId: string, topK: number = 10): { itemId: string; predictedRating: number }[] {
    const targetRatings = this.userRatings.get(userId)!;
    const similarities: { userId: string; sim: number }[] = [];

    for (const otherId of this.userRatings.keys()) {
      if (otherId === userId) continue;
      similarities.push({ userId: otherId, sim: this.userSimilarity(userId, otherId) });
    }

    const topSimilar = similarities.sort((a, b) => b.sim - a.sim).slice(0, 20); // 상위 20명

    // 타겟 사용자가 평가하지 않은 아이템에 대한 예측 평점
    const predictions = new Map<string, { weightedSum: number; simSum: number }>();
    for (const { userId: simUser, sim } of topSimilar) {
      if (sim <= 0) continue;
      for (const [itemId, rating] of this.userRatings.get(simUser)!) {
        if (targetRatings.has(itemId)) continue; // 이미 평가한 아이템 스킵
        if (!predictions.has(itemId)) predictions.set(itemId, { weightedSum: 0, simSum: 0 });
        const p = predictions.get(itemId)!;
        p.weightedSum += sim * rating;
        p.simSum += Math.abs(sim);
      }
    }

    return [...predictions.entries()]
      .map(([itemId, p]) => ({ itemId, predictedRating: p.weightedSum / p.simSum }))
      .sort((a, b) => b.predictedRating - a.predictedRating)
      .slice(0, topK);
  }
}
```

### Item-Based CF

아이템 간 유사도를 기반으로 추천한다. User-Based보다 안정적이고 확장성이 좋다.

```typescript
class ItemBasedCF {
  private itemSimilarityCache: Map<string, Map<string, number>> = new Map();

  // 아이템 유사도 사전 계산 (코사인 유사도)
  precomputeSimilarities(ratings: Map<string, Map<string, number>>): void {
    const itemUsers = new Map<string, Map<string, number>>(); // itemId → { userId: rating }

    // 전치: user→item → item→user
    for (const [userId, items] of ratings) {
      for (const [itemId, rating] of items) {
        if (!itemUsers.has(itemId)) itemUsers.set(itemId, new Map());
        itemUsers.get(itemId)!.set(userId, rating);
      }
    }

    const itemIds = [...itemUsers.keys()];
    for (let i = 0; i < itemIds.length; i++) {
      for (let j = i + 1; j < itemIds.length; j++) {
        const sim = this.cosineSimFromRatings(itemUsers.get(itemIds[i])!, itemUsers.get(itemIds[j])!);
        if (sim > 0.1) { // 임계값 이상만 캐시
          if (!this.itemSimilarityCache.has(itemIds[i])) this.itemSimilarityCache.set(itemIds[i], new Map());
          if (!this.itemSimilarityCache.has(itemIds[j])) this.itemSimilarityCache.set(itemIds[j], new Map());
          this.itemSimilarityCache.get(itemIds[i])!.set(itemIds[j], sim);
          this.itemSimilarityCache.get(itemIds[j])!.set(itemIds[i], sim);
        }
      }
    }
  }
}
```

## 4. 하이브리드 추천

```typescript
class HybridRecommender {
  private contentBased: ContentBasedRecommender;
  private collaborativeFiltering: UserBasedCF;

  async recommend(userId: string, topK: number = 10): Promise<RecommendedItem[]> {
    // 두 추천 결과를 병렬로 실행
    const [cbfResults, cfResults] = await Promise.all([
      this.contentBased.recommendForUser(userId, topK * 2),
      this.collaborativeFiltering.recommend(userId, topK * 2),
    ]);

    // 가중 결합 (CBF 0.4, CF 0.6)
    const scoreMap = new Map<string, number>();
    for (const r of cbfResults) {
      scoreMap.set(r.itemId, (scoreMap.get(r.itemId) ?? 0) + 0.4 * r.score);
    }
    for (const r of cfResults) {
      scoreMap.set(r.itemId, (scoreMap.get(r.itemId) ?? 0) + 0.6 * r.predictedRating / 5);
    }

    return [...scoreMap.entries()]
      .sort(([, a], [, b]) => b - a)
      .slice(0, topK)
      .map(([itemId, score]) => ({ itemId, score }));
  }
}
```

## 5. LLM 기반 추천

```typescript
async function llmRecommend(
  userProfile: string,
  candidates: Item[],
  openai: OpenAI,
): Promise<string[]> {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `사용자 프로필을 분석하고 후보 아이템 중 가장 적합한 5개를 추천하세요.
추천 이유를 간단히 설명하세요.
JSON 형식: [{ "itemId": "string", "reason": "string" }]`,
      },
      {
        role: 'user',
        content: `사용자 프로필:\n${userProfile}\n\n후보 아이템:\n${candidates.map(c => `- ${c.id}: ${c.title} (${c.tags.join(', ')})`).join('\n')}`,
      },
    ],
    response_format: { type: 'json_object' },
  });

  return JSON.parse(response.choices[0].message.content ?? '[]');
}
```

## 6. 콜드 스타트 대응

| 유형 | 전략 |
|------|------|
| **신규 사용자** | 인기 아이템, 카테고리 선택, 인구통계 기반 |
| **신규 아이템** | 콘텐츠 기반, 메타데이터 유사도, 전문가 큐레이션 |
| **완전 신규 시스템** | 규칙 기반, 인기순, A/B 테스트로 데이터 수집 |

## 7. 평가 지표

| 지표 | 설명 | 적합한 경우 |
|------|------|-----------|
| Precision@K | 추천 K개 중 관련 비율 | 정확성 중시 |
| Recall@K | 전체 관련 중 추천된 비율 | 커버리지 중시 |
| NDCG@K | 순위 가중 관련성 | 순위 품질 |
| MAP | 평균 정밀도 평균 | 종합 평가 |
| Hit Rate | 추천에 1개 이상 관련 있는 비율 | 간단한 평가 |
| Diversity | 추천 아이템 간 다양성 | 필터 버블 방지 |
| Novelty | 추천 아이템의 새로움 | 탐색 유도 |
