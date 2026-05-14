---
name: ask-gemma
description: 로컬 Ollama 서버(윈도우 노트북 leonard.local:11434)의 gemma4 모델에 질문을 보내고 결과를 한국어로 정리한다. 오프라인/프라이빗 질의, 간단한 아이디어 발산, 민감 데이터 처리에 사용.
allowed-tools: Bash(curl *), Bash(jq *), Read, Glob, Grep
---

# Ask Gemma (Local Ollama)

윈도우 노트북의 Ollama 서버에 질문을 던지고 결과를 정리한다.

## 서버 정보

- 호스트: `leonard.local:11434` (윈도우 노트북)
- **기본 모델: `gemma4:e4b` (Gemma 3n E4B, 8.0B Q4_K_M, ~9.2GB) — 고정 사용**
- 프로토콜: Ollama REST API

**중요**: 항상 `gemma4:e4b`를 사용한다. 빠른 응답 속도가 핵심. 사용자가 명시적으로 다른 모델을 요청하지 않는 한 **절대 다른 모델로 전환하지 않는다**.

**서버 보유 모델** (실측):
- `gemma4:e4b` — 8.0B Q4_K_M, 9.2GB (기본)
- `gemma4:26b` — 25.8B Q4_K_M, 17.1GB (고품질 명시 요청 시)
- `gemma4:31b` — 31.3B Q4_K_M, 18.9GB (최고품질 명시 요청 시)
- `nomic-embed-text:latest` — 임베딩 전용

## 사용 시점

- Claude/Codex/Gemini 쓸 정도가 아닌 가벼운 질문
- 외부 API 호출 없이 로컬에서 처리해야 하는 민감 데이터
- 네트워크 단절/오프라인 대비 테스트
- 로컬 LLM 성능 비교/검증

## 실행 절차

### 0단계: 연결 확인

서버가 살아있는지 먼저 확인:

```bash
curl -s --max-time 3 http://leonard.local:11434/api/tags | jq -r '.models[].name' || echo "서버 연결 실패"
```

실패 시 사용자에게 알리고 중단. 윈도우 노트북이 켜져있는지, 방화벽, `OLLAMA_HOST=0.0.0.0:11434` 설정 확인 요청.

### 1단계: 질문 정리

사용자 요청을 간결한 한국어 프롬프트로 정리한다. 모델이 로컬 소형 모델이므로 과한 컨텍스트는 지양.

### 2단계: API 호출 (gemma4:e4b 고정)

```bash
# 기본 - 단발 질의 (응답 변수로 받고 sanitize 후 파싱)
RESP=$(curl -s --max-time 60 http://leonard.local:11434/api/generate -d '{
  "model": "gemma4:e4b",
  "prompt": "질문 내용",
  "stream": false,
  "keep_alive": "30m"
}')
printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(),strict=False).get("response",""))'

# 채팅 포맷 (시스템 프롬프트 포함)
RESP=$(curl -s --max-time 60 http://leonard.local:11434/api/chat -d '{
  "model": "gemma4:e4b",
  "messages": [
    {"role": "system", "content": "한국어로 간결하게 답변"},
    {"role": "user", "content": "질문"}
  ],
  "stream": false,
  "keep_alive": "30m"
}')
printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | jq -r '.message.content' \
  || printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\037' | jq -r '.message.content' \
  || printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(),strict=False).get("message",{}).get("content",""))'
```

**제어문자 sanitize 이유**: 모델이 `<thinking>` 토큰이나 ANSI escape(0x1B), BEL(0x07) 등을 raw로 흘리면 jq가 RFC 8259 strict 모드로 fail. 3단계 fallback — 보수적 tr(TAB/LF/CR 보존) → 공격적 tr(0x00-0x1F 전체 제거) → python json.loads(strict=False, macOS 기본 탑재). UTF-8 한글/이모지(0x80↑)는 tr 범위 밖이라 안전.

**`keep_alive: "30m"`**: 모델을 30분 동안 메모리에 유지해서 다음 질의 시 로딩 시간 제거. 첫 호출만 느리고 이후는 즉답.

### 예외: 사용자가 명시적으로 26b/31b 요청한 경우에만

사용자가 "26b로", "31b로", "고품질로", "크게 해서" 등 명시적으로 요청할 때만 사용:

```bash
# 고품질 (응답 느림 — ~14 tok/s) — sanitize fallback 적용
RESP=$(curl -s --max-time 300 http://leonard.local:11434/api/generate -d '{
  "model": "gemma4:26b",
  "prompt": "...",
  "stream": false,
  "keep_alive": "30m"
}')
printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(),strict=False).get("response",""))'

# 최고품질
RESP=$(curl -s --max-time 600 http://leonard.local:11434/api/generate -d '{
  "model": "gemma4:31b",
  "prompt": "...",
  "stream": false,
  "keep_alive": "30m"
}')
printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\010\013\014\016-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | LC_ALL=C tr -d '\000-\037' | jq -r '.response' \
  || printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(),strict=False).get("response",""))'
```

### 3단계: 결과 정리

원문 그대로 붙이지 말고 아래 형식으로 정리:

```
## Gemma (Local) 의견

**요청 목적**: [왜 로컬 Gemma에 물었는지]

**핵심 답변**: [3-5줄 한국어 요약]

**신뢰도/한계**: [로컬 소형 모델 한계, 검증 필요 지점]

**Claude 최종 판단**: [Claude 관점 권고]
```

## 규칙

- **모델은 `gemma4:e4b` 고정**. 사용자 명시 요청 없으면 26b/31b 절대 사용 금지 (속도 우선)
- 로컬 소형 모델 특성상 환각/오답 가능성 높음 → 사실 주장은 반드시 교차 검증
- 코드 생성/수정은 Gemma 결과를 참고만, 실제 수정은 Claude가 직접
- 민감 정보는 Gemma에 보내도 로컬이라 안전 (외부 유출 없음)
- 파이프라인 대상 작업이면 이 스킬 대신 정규 파이프라인 사용
- 큰 컨텍스트(>4K 토큰)는 피할 것 (로컬 리소스 부담)
- `keep_alive: "30m"` 항상 포함 — 모델 언로드/재로드 방지

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `Connection refused` | Ollama 서버 미실행 | 윈도우에서 `ollama serve` 또는 트레이 아이콘 실행 |
| `timeout` | 방화벽 차단 | 윈도우 방화벽 11434 포트 허용 |
| `model not found` | 모델 미설치 | 윈도우에서 `ollama pull gemma4:e4b` |
| `127.0.0.1 only` 바인딩 | `OLLAMA_HOST` 미설정 | 윈도우 환경변수 `OLLAMA_HOST=0.0.0.0:11434` 후 재시작 |
| 응답 느림 | 모델 미적재 / 콜드 스타트 | `keep_alive: "30m"` 설정으로 재로딩 방지 |
| `jq: parse error: Invalid string: control characters from U+0000 through U+001F` | 모델이 raw 제어문자(BEL/ESC/`<thinking>` 토큰)를 escape 없이 흘림 | 응답을 변수로 받고 위 3단계 sanitize fallback 적용 (보수적 tr → 공격적 tr → python strict=False) |
