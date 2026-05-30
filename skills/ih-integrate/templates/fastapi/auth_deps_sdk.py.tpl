# app/auth.py — identity-hub-python-sdk 사용 버전
# 설치: pip install identity-hub-sdk[fastapi]
# 환경변수: SDK 기본 키는 IDENTITY_HUB_URL, IDENTITY_HUB_REALM 이지만, 여기서는
#   ih-integrate의 ${ENV_PREFIX} 규칙으로 결정된 키를 명시 주입해 접두가 달라도 정합되게 한다.
# SECURITY: never log or return token raw values. SDK가 JWT 검증/에러 일반화를 담당한다.
import os

from identity_hub import IdentityHubConfig
from identity_hub.middleware.fastapi import (
    configure,
    get_current_user,
    get_optional_user,
    require_roles,
)
from identity_hub.models import TokenClaims

# 앱 시작 시 한 번만 호출 (예: main.py에서 import auth 후 사용).
# ${ENV_PREFIX}가 IDENTITY_HUB_ 이면 SDK 기본 키와 동일해지고, 다른 접두여도 올바로 읽는다.
configure(IdentityHubConfig(
    url=os.getenv("${ENV_PREFIX}URL", "${HUB_URL}"),
    realm=os.getenv("${ENV_PREFIX}REALM", "${REALM}"),
))

__all__ = [
    "TokenClaims",
    "get_current_user",
    "get_optional_user",
    "require_roles",
]
