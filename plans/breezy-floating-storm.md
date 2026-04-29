# Post Logout Redirect URIs - Keycloak 클라이언트 UI 추가

## Context
Keycloak 클라이언트 관리 UI(`/keycloak-clients`)에 post_logout_redirect_uris 등록/수정 기능 추가.
이 필드는 Keycloak의 `attributes["post.logout.redirect.uris"]`에 `##` 구분자로 저장됨.

## 변경 파일

### Backend (identity-hub) - 이미 완료
- `app/api/v1/endpoints/clients.py` — create/update/get에서 post_logout_redirect_uris ↔ attributes 변환
- `app/schemas/client.py` — 이미 post_logout_redirect_uris 필드 존재

### Frontend (identity-hub-frontend)
- `src/lib/types/keycloak-client.ts` — KeycloakClientUpdate에 post_logout_redirect_uris 추가 (완료)
- `src/lib/types/keycloak-client.ts` — KeycloakClientResponse에 post_logout_redirect_uris 추가
- `src/components/keycloak-clients/kc-client-detail-dialog.tsx` — view/edit 모드에 Post Logout Redirect URIs 추가

## 검증
- 프론트엔드 빌드 확인
- Keycloak 클라이언트 상세 다이얼로그에서 post_logout_redirect_uris 표시/편집 확인
