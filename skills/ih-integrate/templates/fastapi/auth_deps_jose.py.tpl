# app/auth.py — SDK 없이 python-jose + JWKS 직접 호출 버전
# 설치: pip install httpx 'python-jose[cryptography]'
import functools
import os

import httpx
from fastapi import Header, HTTPException
from jose import jwt, JWTError

HUB_URL = os.getenv("HUB_URL", "${HUB_URL}")
REALM = os.getenv("REALM", "${REALM}")
CLIENT_ID = os.getenv("CLIENT_ID", "${CLIENT_ID}")

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
        raise HTTPException(401, f"invalid token: {e}")
