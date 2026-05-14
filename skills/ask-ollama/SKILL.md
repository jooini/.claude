---
name: ask-ollama
description: 로컬 Ollama 서버(leonard.local:11434)에 질문하고 결과를 한국어로 정리. 기본 호출은 qwen-cli(권장), 미설치 환경은 curl fallback. 키워드 기반 모델 자동 라우팅 — 코딩→qwen2.5-coder:14b, 한국어/일반→qwen3.5:9b, 빠른 단순 질의→gemma4:e4b, 깊은 추론→gemma4:26b. 사용자가 모델 명시하면 그것 우선.
allowed-tools: Bash(qwen-cli *), Bash(~/.local/bin/qwen-cli *), Bash(curl *), Bash(jq *), Read, Glob, Grep
---

# Ask Ollama (Local Multi-Model)

윈도우 노트북 Ollama 서버에 질문 후 결과 정리. 모델 자동 선택 또는 명시 호출.

## 서버 정보

- **호스트**: `leonard.local:11434` (mDNS) — 윈도우 노트북, RTX 4090 Laptop 16GB VRAM
- **프로토콜**: Ollama REST API
- **`OLLAMA_HOST=0.0.0.0:11434`** 설정 완료, 방화벽 11434 허용

## 보유 모델 (실측)

| 모델 | 파라미터 | 크기 | 강점 | 권장 용도 |
|---|---|---|---|---|
| `qwen3.5:9b` ⭐ | 9.7B | 6.1GB | 한국어/CJK, RAG, Agent | **만능 균형형 (기본)** |
| `qwen2.5-coder:14b` ⭐ | 14.8B | 8.4GB | HumanEval 89+ | **코딩 특화** |
| `gemma4:e4b` | 8.0B | 8.9GB | 빠른 응답 | 단순 질의 |
| `gemma4:26b` | 25.8B | 16.8GB | 추론 깊이 | 느려도 정확도 우선 |
| `gemma4:31b` | 31.3B | 18.5GB | 최고 품질 | VRAM 부족 (오프로드) |

## 모델 자동 라우팅

사용자가 명시 안 하면 키워드로 자동 선택:

| 입력 신호 | 선택 모델 |
|---|---|
| "코드", "구현", "디버그", "리팩터", "함수", "SQL", "버그", "Python", "TypeScript", "Kotlin", "정규식" | `qwen2.5-coder:14b` |
| "한국어", "번역", "요약", "문서", "RAG", "Agent", "tool use", "JSON 출력" 또는 일반 질의 (기본값) | `qwen3.5:9b` |
| "빠르게", "간단히", "간단한 질문", "가볍게" | `gemma4:e4b` |
| "깊이", "정확하게", "고품질" 또는 한국어 작가급 글쓰기 | `gemma4:26b` |
| 사용자가 "X로 물어봐", "qwen으로", "gemma 26b로" 등 명시 | **사용자 지정 우선** |

## 사용 시점

- Claude/Codex/Gemini 쓸 정도가 아닌 가벼운 질문
- 외부 API 차단된 민감 데이터 처리
- 오프라인/프라이빗 질의
- 로컬 LLM 세컨드 오피니언
- 코드 자동완성 보조 (qwen2.5-coder)

## 실행 절차

### 0단계: 연결 + 도구 확인

```bash
# qwen-cli 우선 (권장)
[ -x ~/.local/bin/qwen-cli ] && echo "qwen-cli 사용 가능" || echo "qwen-cli 없음 — curl fallback"

# 서버 헬스체크 (qwen-cli 또는 curl 둘 중 하나)
~/.local/bin/qwen-cli -p "ping" --num-ctx 1024 2>/dev/null \
  || curl -s --max-time 3 http://leonard.local:11434/api/tags | jq -r '.models[].name' \
  || echo "서버 연결 실패"
```

실패 시: 윈도우 노트북 켜졌는지, `ollama serve` 실행 중인지, 11434 방화벽 허용인지 확인 요청.

### 1단계: 모델 선택

사용자 발화 분석:
- 명시된 모델 있으면 그대로
- 없으면 위 라우팅 표 적용
- 애매하면 기본값 `qwen3.5:9b`

### 2단계: 호출 (qwen-cli 권장)

**기본 — qwen-cli 단발 호출** (`num_ctx`/`keep_alive`/페르소나 자동 적용):

```bash
# 짧은 질의 — 인자로 직접
~/.local/bin/qwen-cli -p "deprecated 뜻" -m qwen3.5:9b --num-ctx 4096

# 긴 입력/멀티라인 — stdin pipe
echo "긴 질문 또는 코드 본문..." | ~/.local/bin/qwen-cli -p - --profile coder

# 페르소나 명시 (frontmatter의 model 자동 적용)
echo "$DIFF" | ~/.local/bin/qwen-cli -p - --profile commit
echo "$ERROR_LOG" | ~/.local/bin/qwen-cli -p - --profile debugger
```

**페르소나 매핑** (자주 쓰는 것):

| 페르소나 | 모델 (frontmatter) | 용도 |
|---|---|---|
| `commit` | qwen3.5:9b | 한글 커밋 메시지 초안 |
| `coder` | qwen2.5-coder:14b | 코드 페어 |
| `reviewer` | qwen2.5-coder:14b | 코드 리뷰 |
| `debugger` | qwen2.5-coder:14b | 에러/버그 진단 |
| `korean` | qwen3.5:9b | 번역/현지화 |
| `writer` | qwen3.5:9b | 기술 문서 편집 |
| `sql` | qwen2.5-coder:14b | SQL/데이터 |
| `architect` | qwen2.5-coder:14b | 깊이 분석 |
| `brainstorm` | qwen3.5:9b | 캐묻기 위주 |

**Fallback — curl 직접 호출** (qwen-cli 미설치 시만):

```bash
# 단발 질의 — 응답을 변수로 받고 sanitize 후 파싱 (제어문자 방어)
RESP=$(curl -s --max-time 120 http://leonard.local:11434/api/generate -d '{
  "model": "qwen3.5:9b",
  "prompt": "질문",
  "stream": false,
  "keep_alive": "30m",
  "options": {"num_ctx": 8192}
}')
printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(), strict=False).get("response",""))'

# 채팅 (시스템 프롬프트 포함)
RESP=$(curl -s --max-time 120 http://leonard.local:11434/api/chat -d '{
  "model": "qwen2.5-coder:14b",
  "messages": [
    {"role": "system", "content": "한국어로 간결하게. 코드는 fenced block."},
    {"role": "user", "content": "질문"}
  ],
  "stream": false,
  "keep_alive": "30m",
  "options": {"num_ctx": 8192}
}')
printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | jq -r '.message.content' \
  || printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\037' | jq -r '.message.content' \
  || printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(), strict=False).get("message",{}).get("content",""))'
```

**제어문자 sanitize 이유**: qwen3.5가 `thinking` 필드나 ANSI escape (0x1B), BEL (0x07) 등 raw 제어문자를 응답에 흘리면 jq가 RFC 8259 strict 모드로 `Invalid string: control characters from U+0000 through U+001F must be escaped` 에러. 3단계 fallback:
1. **보수적 tr** — 0x09(TAB)/0x0A(LF)/0x0D(CR) 보존하면서 나머지 제어문자만 제거. UTF-8 한글/이모지(0x80↑)는 영향 없음.
2. **공격적 tr** — 0x00-0x1F 전부 제거 (string 안에 raw TAB/LF가 들어있는 비정상 케이스).
3. **python json.loads(strict=False)** — macOS 기본 탑재라 의존성 0. 위 두 단계도 실패한 깨진 JSON 최후 보루.

**`num_ctx` 가이드** (RTX 4090 Laptop 16GB 기준):

| 모델 | num_ctx | VRAM 점유 | 속도 |
|---|---|---|---|
| qwen3.5:9b | 8192 (기본) | 8.2GB | 70 tok/s ✅ |
| qwen3.5:9b | 16384 | ~10GB | ~50 tok/s |
| qwen3.5:9b | 32768 | ~14GB | ~25 tok/s |
| qwen3.5:9b | 기본(256K) | 12GB+ | 10 tok/s 🔴 (오프로드) |
| qwen2.5-coder:14b | 8192 | ~10GB | 추정 50~60 tok/s |
| qwen2.5-coder:14b | 32768 | ~15GB | 추정 25~35 tok/s |
| gemma4:e4b | 8192 | ~9GB | 30~50 tok/s |
| gemma4:26b | 8192 | 16GB+ | 14 tok/s (오프로드 불가피) |

긴 문서 처리 필요할 때만 `num_ctx` 키우기. 단순 질의는 8K 충분.

`keep_alive: "30m"` 항상 포함 — 모델 언로드 방지로 다음 호출 즉답.

### 3단계: 결과 정리

원문 그대로 붙이지 말고 형식화:

```
## Ollama (Local · {모델명}) 의견

**선택 사유**: [왜 이 모델을 골랐는지 한 줄]

**핵심 답변**: [3-5줄 한국어 요약]

**신뢰도/한계**: [로컬 모델 한계, 검증 필요 지점]

**Claude 최종 판단**: [Claude 관점 권고]
```

## 규칙

- 사용자 발화에 모델 지정 있으면 무조건 그것 사용
- 라우팅 애매하면 `qwen3.5:9b` (만능 기본)
- 코딩 키워드면 `qwen2.5-coder:14b` (예외 없음)
- 로컬 소형 모델 환각 가능성 → 사실 주장은 교차 검증
- 코드 수정은 결과 참고만, 실제 수정은 Claude가 직접
- 민감 정보 OK (외부 유출 없음)
- 큰 컨텍스트(>16K 토큰)는 피할 것 — 16K 초과 시 `num_ctx` 명시적으로 지정 (속도 50% 이상 감소 감수)
- 파이프라인 대상이면 이 스킬 대신 정규 파이프라인 사용

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `qwen-cli: command not found` | PATH 미등록 또는 미설치 | `~/.local/bin/qwen-cli` 절대경로 사용. 빌드: `cd ~/Workspace/gemma-cli && cargo build --release && cp target/release/qwen-cli ~/.local/bin/` |
| qwen-cli 응답 늦음 (콜드 5초+) | 모델 첫 로드 | `--keep-alive 30m`로 다음 호출 빠르게. 또는 백그라운드에서 미리 ping |
| `Connection refused` | 윈도우 Ollama 미실행 | `ollama serve` 또는 트레이 |
| `timeout` | 방화벽/콜드 스타트 | 방화벽 11434 허용, `keep_alive: "30m"` |
| `model not found` | 모델 미설치 | `curl -X POST http://leonard.local:11434/api/pull -d '{"name":"모델명"}'` |
| 응답 느림 | 모델 미적재 | `keep_alive: "30m"` 추가, 같은 모델 재호출 시 즉답 |
| VRAM 부족 (31b) | 16GB 한계 | 26b 또는 더 작은 모델로 |
| 속도 갑자기 느림 (10 tok/s 이하) | KV 캐시가 VRAM 초과 → 부분 오프로드 | `options.num_ctx: 8192` 추가, 환경변수 `OLLAMA_MAX_LOADED_MODELS=1` |
| `ollama ps`에서 GPU 100% 미만 | 동시 모델 적재 또는 큰 num_ctx | 위와 동일 |
| `jq: parse error: Invalid string: control characters from U+0000 through U+001F` | 모델이 raw 제어문자(BEL 0x07, ESC 0x1B 등) 또는 `<thinking>` 토큰을 escape 없이 흘림. 30KB 응답이라도 1바이트만 끼면 전체 fail | 위 fallback 체인(보수적 tr → 공격적 tr → python json.loads(strict=False)) 적용. **응답을 변수로 받고 파싱은 sanitize 후** 하는 패턴 고정 |
| 응답 받았는데 빈 문자열만 출력 | sanitize 후에도 jq는 성공했지만 `.response` 필드 자체가 비어있고 `.thinking`에만 내용 있음 (qwen 일부 모델) | `jq -r '.response // .thinking // .message.content'` 로 fallback 키 체크 |

## ask-gemma와의 관계

`ask-gemma` 스킬은 호환성 유지용. Gemma 계열 명시 호출(`gemma4:e4b`, `gemma4:26b`, `gemma4:31b`) 시에만 의미. 일반적으로 `ask-ollama` 사용 권장.
