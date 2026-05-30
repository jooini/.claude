# src/main/resources/application.yml — 기존 파일이 있으면 머지
# Authorization Code 플로우는 WebClient로 Hub BFF 호출.
# Spring Security는 Resource Server로 JWT 검증만 담당.
# SECURITY: client_secret은 이 파일에 두지 않는다. 환경변수/외부 시크릿으로만 주입한다.
# 환경변수 접두는 ih-integrate의 ${ENV_PREFIX} 규칙을 따른다(미지정 시 접두 없음).
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${${ENV_PREFIX}URL}/realms/${${ENV_PREFIX}REALM}
          jwk-set-uri: ${${ENV_PREFIX}URL}/api/v1/auth/jwks/${${ENV_PREFIX}REALM}

hub:
  url: ${${ENV_PREFIX}URL}
  realm: ${${ENV_PREFIX}REALM}
  client-id: ${${ENV_PREFIX}CLIENT_ID}
  redirect-uri: ${${ENV_PREFIX}REDIRECT_URI}
  post-logout-redirect-uri: ${${ENV_PREFIX}POST_LOGOUT_REDIRECT_URI}
