# app/hub_service_token.py
# 서비스 간 통신용 M2M 토큰 매니저. 만료 30초 전까지 캐시 재사용.
import os
import time

import httpx

HUB_URL = os.getenv("HUB_URL", "${HUB_URL}")
REALM = os.getenv("REALM", "${REALM}")
CLIENT_ID = os.getenv("CLIENT_ID", "${CLIENT_ID}")
TOKEN_URL = f"{HUB_URL}/api/v1/auth/service-token"


class HubServiceToken:
    def __init__(self) -> None:
        self._token: str | None = None
        self._expires_at: float = 0

    async def get(self) -> str:
        if self._token and time.time() < self._expires_at - 30:
            return self._token
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                TOKEN_URL, json={"client_id": CLIENT_ID, "realm": REALM}
            )
            resp.raise_for_status()
            data = resp.json()
            self._token = data["access_token"]
            self._expires_at = time.time() + data["expires_in"]
            return self._token


service_token = HubServiceToken()
