# 트러블슈팅

## token_exchange_failed

**원인 후보:**

1. Keycloak Client의 Redirect URI에 `REDIRECT_URI`가 등록되지 않음
2. `HUB_URL`이 토큰 발급 Keycloak과 다른 인스턴스에 연결돼 있음
3. `CLIENT_ID` / `REALM` 조합이 Keycloak Client와 불일치
4. Hub와 Keycloak 사이 네트워크 단절

**확인:**

```bash
# Hub가 살아 있는지
curl -sS "${HUB_URL}/api/v1/auth/jwks/${REALM}" | head -c 200

# Hub 디버그 로그 확인 (Hub 운영자에게)
```

## client_not_configured

Identity Hub의 DB(`client_configurations`)에 해당 client_id 등록이 없을 때 발생.

**해결:**

- `--onboard` 플래그로 다시 실행 (admin 토큰 필요)
- 또는 Identity Hub Frontend 대시보드에서 수동 등록
- 또는 직접 `POST /api/v1/onboard` 호출

## No matching key found for kid: ...

JWT 서명 검증 실패. 토큰을 발급한 Keycloak과 JWKS를 가져오는 Hub가 다른 Keycloak에 연결됨.

**해결:** `HUB_URL`을 토큰 발급 환경과 일치시킴.
- dev 토큰 → `dev-sso.speakingmaxapp.com`
- local 토큰 → 로컬 Hub

## 콜백에서 code가 fragment(#)로 옴

Hub가 `response_mode=fragment`로 응답하는 경우 서버 라우트가 hash를 읽지 못한다.

**해결:** 스킬이 깐 코드는 `response_mode=query`를 명시한다. 만약 그래도 fragment로 온다면:
- Next.js: `callback/page.tsx` (client component)에서 `window.location.hash` 파싱
- 또는 Hub login 호출 시 `response_mode=query` 다시 확인

## refresh 401 / 무한 루프

`access_token`이 너무 오래 전 발급돼 Hub Redis 세션이 만료된 경우. Hub `/auth/refresh`는 access_token에서 session_state를 추출해 세션을 찾는데, 세션이 GC되면 갱신 불가.

**해결:** 사용자가 다시 로그인. 클라이언트 측에 "세션 만료, 다시 로그인" UX 처리.

## CORS

서비스가 다른 도메인에서 Hub `/api/v1/auth/*`를 호출하면 CORS 발생 가능. 일반적으로:

- **로그인 시작**: 서버에서 loginUrl만 받아 브라우저 `window.location` 이동 → CORS 무관
- **exchange/refresh**: 서비스 백엔드(같은 origin)에서만 호출 → CORS 무관
- **service-token (M2M)**: 백엔드↔백엔드 → CORS 무관

브라우저에서 직접 Hub `/auth/exchange` 부르면 안 된다. 반드시 자체 서버 라우트 경유.

## 디버그 모드

각 스택에서 토큰 클레임 확인:

```bash
# 쿠키에 저장된 access_token 가져와서
echo "eyJhbGc..." | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

또는 `/jwt-debug` 스킬 사용.
