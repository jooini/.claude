---
name: dormant-chunks
description: local-rag (13594 청크) 중 한 번도 답변에 쓰이지 않은 휴면 청크 중 현재 작업과 관련 있는 것을 발굴. /dormant 으로 현재 컨텍스트 기반 자동 추천, /dormant "쿼리"로 명시 검색.
---

# Dormant Chunks

local-rag 검색 결과 중 `~/.claude/cache/rag-usage.jsonl`에 기록된 적 없는 청크를 우선 추천한다. `mcp-local-rag` CLI 결과에는 DB 내부 `id`가 없으므로 `filePath#chunkIndex`를 안정적인 `chunk_id`로 사용한다.

## 명령

- `/dormant`: 현재 사용자 요청과 작업 컨텍스트를 한 줄 쿼리로 요약해서 실행한다.
- `/dormant "BFF timeout"`: 따옴표 안 쿼리를 그대로 검색한다.
- `/dormant stats`: 사용 로그 기준 사용된 청크 수, DB 청크 수, 추정 휴면 청크 수를 본다.

## 실행

```bash
python3 ~/.claude/scripts/dormant-chunks.py --query "$QUERY"
python3 ~/.claude/scripts/dormant-chunks.py stats
```

검색은 `~/Workspace/mcp-local-rag/dist/index.js query`를 우선 사용한다. Python LanceDB 직접 검색은 `lancedb`, `pyarrow`, `sentence-transformers`가 설치되어 있고 CLI가 실패할 때만 fallback으로 사용한다.

## 출력 규칙

상위 3개만 보여준다. 각 항목은 다음 필드를 포함한다.

- 출처 파일: `file_path` 또는 `source`
- 발췌: 공백 정규화 후 200자
- `dormant_score`: `relevance * (1 - usage_count/10) * recency_factor`
- 왜 지금 관련 있는지: 쿼리 핵심어 겹침 또는 의미 검색 상위 결과 근거

## 사용 로그

현재 자동 로깅은 비활성이다. mcp-local-rag query 결과를 사용한 뒤 다음처럼 수동 기록한다.

```bash
RESULT=$(node ~/Workspace/mcp-local-rag/dist/index.js \
    --db-path ~/Workspace/lancedb \
    --cache-dir ~/.claude/cache/rag-models \
    --model-name Xenova/multilingual-e5-small \
    query --limit 5 "BFF timeout")
printf '%s' "$RESULT" | python3 ~/.claude/scripts/rag-usage-logger.py
printf '%s\n' "$RESULT"
```

로그가 없으면 모든 검색 결과가 휴면으로 간주된다. 이 경우 "한 번도 답변에 안 쓰임" 판정은 다음 로깅 이후부터 의미가 있다.

## Hook Point

외부 프로젝트 `~/Workspace/mcp-local-rag`는 직접 수정하지 않는다. 자동화를 원하면 `src/server/index.ts`의 `handleQueryDocuments()`에서 `results` 배열 생성 직후, 또는 `src/cli/query.ts`의 JSON stdout 직전에 `rag-usage-logger.py`로 결과 JSON을 전달하는 패치를 별도 검토한다.
