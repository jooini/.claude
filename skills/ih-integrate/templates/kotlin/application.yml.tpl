# src/main/resources/application.yml — 기존 파일이 있으면 머지
# Authorization Code 플로우는 WebClient로 Hub BFF 호출.
# Spring Security는 Resource Server로 JWT 검증만 담당.
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${HUB_URL}/realms/${REALM}
          jwk-set-uri: ${HUB_URL}/api/v1/auth/jwks/${REALM}

hub:
  url: ${HUB_URL}
  realm: ${REALM}
  client-id: ${CLIENT_ID}
  redirect-uri: ${REDIRECT_URI}
  post-logout-redirect-uri: ${POST_LOGOUT_REDIRECT_URI}
