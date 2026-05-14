# app/auth.py — identity-hub-python-sdk 사용 버전
# 설치: pip install identity-hub-sdk[fastapi]
# 환경변수: IDENTITY_HUB_URL, IDENTITY_HUB_REALM
from identity_hub import IdentityHubConfig
from identity_hub.middleware.fastapi import (
    configure,
    get_current_user,
    get_optional_user,
    require_roles,
)
from identity_hub.models import TokenClaims

# 앱 시작 시 한 번만 호출 (예: main.py에서 import auth 후 사용)
configure(IdentityHubConfig())

__all__ = [
    "TokenClaims",
    "get_current_user",
    "get_optional_user",
    "require_roles",
]
