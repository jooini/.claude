# Keycloak Client 측 체크리스트

스킬이 코드를 깔아도 Keycloak Client가 맞게 설정돼 있어야 동작한다. `--onboard`로 자동 등록한 경우 대부분 이미 채워지지만, 수동 등록이거나 동작이 이상하면 아래를 점검.

## 1. Redirect URIs

- 스킬에 전달한 `REDIRECT_URI` 값이 Keycloak Client의 **Valid Redirect URIs** 에 그대로 등록돼 있어야 한다.
- `http://localhost`는 허용되지만, 그 외 도메인은 `https://` 필수.
- 와일드카드(`*`) 사용은 보안상 비권장.

## 2. Web Origins

- SPA/브라우저에서 호출하는 경우 **Web Origins** 에 origin(`https://my-app.example.com`)을 등록.
- `+` 입력 시 Redirect URIs로부터 자동 도출.

## 3. Client 유형

| service_type | publicClient | standardFlow | directAccess | serviceAccounts |
|--------------|:-:|:-:|:-:|:-:|
| `web` | X | O | X | X |
| `mobile` | O | O | O | X |
| `backend` | X | X | O | O |

`--onboard` 자동 등록은 위 표를 따른다.

## 4. Client Secret

- `web`/`backend`는 confidential client → secret 발급됨
- `--onboard` 응답 또는 Keycloak 콘솔 Credentials 탭에서 확인
- 비밀 관리 시스템(.env, vault)에 저장. 코드/git에 커밋 금지

## 5. Protocol Mappers (선택)

- 사용자 정의 클레임(`mIdx` 등)이 토큰에 필요하면 Protocol Mapper 추가
- SDK의 `TokenClaims`는 `model_config = {"extra": "allow"}` 라 추가 클레임 자동 보존

## 6. 잘 안 되는 경우 — 가장 흔한 원인

1. **kid 불일치**: `HUB_URL`이 토큰 발급 Keycloak과 다른 Hub를 가리키는 경우. URL/realm 매칭 재확인
2. **Redirect URI 미등록**: Keycloak Client의 Valid Redirect URIs에 정확히 같은 값이 없으면 `invalid_redirect_uri`
3. **scope 불일치**: 기본 `openid profile email`. id_token 받고 싶으면 `openid` 필수
4. **token expired during exchange**: 콜백까지 시간 너무 오래 걸린 경우. Keycloak code lifespan 늘리거나 사용자 다시 로그인 시도
