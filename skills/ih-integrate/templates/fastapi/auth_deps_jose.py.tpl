# app/auth.py — SDK 없이 python-jose + JWKS 직접 호출 버전
# 설치: pip install httpx 'python-jose[cryptography]'
# SECURITY: never log or return token raw values. 검증 실패 시 내부 예외 사유를 클라이언트에 노출하지 않고
# 일반화된 메시지로만 응답한다(상세는 서버 로그에만, 토큰 제외).
import functools
import logging
import os

import httpx
from fastapi import Header, HTTPException
from jose import jwt, JWTError

logger = logging.getLogger(__name__)

HUB_URL = os.getenv("${ENV_PREFIX}URL", "${HUB_URL}")
REALM = os.getenv("${ENV_PREFIX}REALM", "${REALM}")
CLIENT_ID = os.getenv("${ENV_PREFIX}CLIENT_ID", "${CLIENT_ID}")

ISSUER = f"{HUB_URL}/realms/{REALM}"
JWKS_URL = f"{HUB_URL}/api/v1/auth/jwks/{REALM}"


@functools.lru_cache(maxsize=1)
def _jwks():
    # TODO: 프로덕션은 TTL 캐시 (cachetools 등)로 교체
    return httpx.get(JWKS_URL, timeout=5.0).json()


def verify_token(authorization: str = Header(...)) -> dict:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        return jwt.decode(
            token,
            key=_jwks(),
            algorithms=["RS256"],
            audience=CLIENT_ID,
            issuer=ISSUER,
        )
    except JWTError as e:
        # SECURITY: 예외 사유(e)를 응답에 싣지 않는다. 서버 로그에만 남긴다(토큰 제외).
        logger.warning("jwt verification failed: %s", e)
        raise HTTPException(401, "invalid token")
