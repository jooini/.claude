# /jwt-debug - JWT 토큰 디버깅

JWT 토큰을 파싱하고, JWKS kid 매칭을 검증하고, 클레임을 분석한다.
2026-02-06 "kid invalid" 401 에러 같은 문제를 빠르게 진단한다.

## 사용법

- `/jwt-debug eyJhbGci...` - JWT 토큰 직접 입력
- `/jwt-debug dev` - dev 서버에서 테스트 토큰 발급 후 분석

## 인자

$ARGUMENTS

## 수행 작업

### 케이스 1: JWT 토큰이 직접 전달된 경우

#### 1단계: 토큰 디코딩 (서명 검증 없이)

Base64 디코딩으로 Header와 Payload 파싱:

**Header 분석:**
- `alg`: 알고리즘 (RS256 등)
- `kid`: Key ID (JWKS 매칭에 사용)
- `typ`: JWT

**Payload 분석:**
- `sub`: Keycloak 사용자 UUID
- `preferred_username`: 로그인 ID
- `email`: 이메일
- `mIdx`: T_Member 링크 키 (커스텀 클레임)
- `session_state`: 세션 ID
- `exp`: 만료 시간 (현재 시간과 비교)
- `iss`: 발급자 URL (어떤 Keycloak 인스턴스인지)
- `azp`: 클라이언트 ID

#### 2단계: JWKS kid 매칭 검증

토큰의 `iss` (issuer) URL에서 JWKS 엔드포인트 도출:
```
{iss}/protocol/openid-connect/certs
```

JWKS에서 `kid`가 일치하는 키 찾기:
- 일치하면: "JWKS kid 매칭 성공"
- 불일치하면: "kid 불일치 - 다른 Keycloak 인스턴스에서 발급된 토큰"

#### 3단계: 환경 일관성 체크

토큰의 `iss`와 로컬 설정의 Keycloak URL 비교:
- `define.js`의 `identityHubUrl`
- `.env`의 `IDENTITY_HUB_URL`
- 불일치 시 경고

### 케이스 2: `dev` 인자인 경우

dev2-backend에서 테스트 토큰 발급:
```bash
ssh dev2-backend 'docker exec dev-maxai-identity-hub curl -s http://localhost:8000/api/v1/auth/jwks/weaversbrain'
```

JWKS 정보 출력:
- 사용 가능한 kid 목록
- 알고리즘
- 키 타입

### 4단계: Gemma 로컬 설명 생성 (권장, 옵션)

JWT payload는 민감 정보(sub/email/session_state)를 포함하므로 외부 LLM 전송 부적합.
로컬 Gemma에 넘겨 한국어 해석 생성. 서버 접근 불가 시 이 단계 스킵.

```bash
OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"

if curl -s --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    # PAYLOAD_JSON: 앞 단계에서 파싱한 payload 전체 (JSON 문자열)
    export PAYLOAD_JSON

    REQ=$(python3 <<'PYEOF'
import json, os
p = os.environ["PAYLOAD_JSON"]
prompt = f"""다음 JWT payload를 한국어로 해석해줘.

규칙:
- 각 주요 클레임이 무엇을 의미하는지 3~5줄로 요약
- exp가 있으면 현재 시각과 비교하여 유효/만료 명시
- 토큰의 용도 추정 (access / refresh / service / admin 등)
- 이상 징후(만료 임박, 비정상 scope, 누락 클레임)가 있으면 경고
- 장식/이모지/인사 금지

payload:
{p}
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "한국어로 간결하게. 최대 6줄."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m"
}))
PYEOF
)

    EXPLANATION=$(curl -s --max-time 15 "http://${OLLAMA_HOST}/api/chat" \
        -H "Content-Type: application/json" \
        -d "$REQ" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('message', {}).get('content', ''))
except Exception:
    pass
")
fi
```

결과는 아래 출력 형식의 `[Gemma 해석]` 섹션에 포함한다.

### 출력 형식

```
=== JWT 디버그 ===

[Header]
  alg: RS256
  kid: qi9FN84D5a3x...
  typ: JWT

[Payload]
  sub: abc-def-123
  preferred_username: sm_leonard
  mIdx: 1179409
  email: user@example.com
  session_state: xyz-789
  iss: https://dev-sso.speakingmaxapp.com/realms/weaversbrain
  azp: maxai-app
  exp: 2026-02-11T15:30:00 (만료까지 4분 32초)

[JWKS 검증]
  Issuer JWKS URL: https://dev-sso.speakingmaxapp.com/realms/weaversbrain/protocol/openid-connect/certs
  kid 매칭: ✅ 일치

[환경 일관성]
  토큰 issuer: dev-sso.speakingmaxapp.com ✅
  define.js LOCAL: local-identity.weaversbrain.com ⚠️ 불일치!
  .env IDENTITY_HUB_URL: dev-sso.speakingmaxapp.com ✅

[Gemma 해석 — 로컬 Ollama]
  이 토큰은 Keycloak에서 발급한 access token으로 보임.
  `sub`는 사용자 UUID, `mIdx`는 T_Member 테이블과 연결되는 커스텀 키.
  `exp`가 현재 시각 기준 4분 32초 남음 — 만료 임박.
  `session_state` 존재로 브라우저 세션 기반 로그인 플로우 추정.
```
