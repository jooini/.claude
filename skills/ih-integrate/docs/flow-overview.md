# Identity Hub 연동 흐름

이 스킬이 깐 코드는 다음 시나리오를 실현한다.

## 로그인

```
[사용자] 로그인 버튼 클릭
   ↓
[서비스] POST /api/auth/login
   ↓ { loginUrl }
[브라우저] window.location = loginUrl  (= HUB_URL/api/v1/auth/login?...)
   ↓ 302
[Identity Hub] state/PKCE/nonce 생성 → Redis 저장 → Keycloak Authorization URL로 302
   ↓
[Keycloak] 로그인 폼 (소셜 로그인 포함)
   ↓ 인증 성공
[Keycloak] redirect_uri = REDIRECT_URI 로 302 (code 포함)
   ↓
[서비스] /callback 페이지 또는 /api/auth/callback 라우트가 code 수신
   ↓
[서비스] POST HUB_URL/api/v1/auth/exchange  { code }
   ↓
[Identity Hub] state 검증 → Keycloak Token Endpoint 호출 (client_secret 자기가 붙임)
   ↓ { access_token, id_token?, expires_in, session_state, user_info? }
[서비스] access_token httpOnly 쿠키에 저장 → "/" 로 리다이렉트
```

핵심: **state/PKCE/nonce/refresh_token/client_secret 모두 Hub가 보관**. 서비스는 노출되지 않는다.

## 토큰 검증 (보호된 API 호출)

```
[클라이언트] Authorization: Bearer {access_token}
   ↓
[서비스 미들웨어] JWKS 캐시 (HUB_URL/api/v1/auth/jwks/{realm})로 서명 검증
   ↓
[서비스] req.user / claims 사용
```

JWKS는 SDK 사용 시 자동, 직접 구현 시 1시간 TTL 캐시 권장.

## 토큰 갱신

```
[클라이언트] 401 수신 또는 만료 임박
   ↓
[서비스] POST /api/auth/refresh  (자체 라우트)
   ↓ access_token 쿠키
[서비스] POST HUB_URL/api/v1/auth/refresh  { access_token }
   ↓ { access_token } 만 반환
[서비스] 새 access_token 쿠키로 갱신
```

`expires_in`이 응답에 없다 — `access_token`의 `exp` 클레임을 직접 파싱해 cookie maxAge 계산.

## 로그아웃

```
[사용자] 로그아웃 클릭
   ↓
[서비스] POST /api/auth/logout
   ↓
[서비스] POST HUB_URL/api/v1/auth/logout  { access_token }  (Hub 세션 종료)
   ↓
[서비스] 응답에 logoutUrl 포함 → 브라우저를 Keycloak logout URL로 이동
   ↓
[Keycloak] KC 세션 쿠키 정리 → post_logout_redirect_uri 로 302
```

Hub 호출만 하고 끝내면 KC 세션이 남아 즉시 재로그인되는 함정이 있다. 반드시 KC logout URL까지 거쳐야 함.

## M2M (서버 간 호출)

`--enable-m2m` 플래그로 설치한 매니저는:

- `POST HUB_URL/api/v1/auth/service-token { client_id, realm }` 호출
- Hub가 자기 DB의 client_secret을 꺼내 KC token endpoint에 붙여 발급
- 만료 30초 전까지 메모리 캐시 재사용

서비스는 `client_secret`을 보관/전송하지 않는다.
