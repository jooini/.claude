# app/routes/auth.py
# Hub BFF 경유 로그인/콜백/리프레시/로그아웃.
# client_secret 보관/전송 없음. state/PKCE는 Hub가 관리.
# requirements: fastapi httpx
import os
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import RedirectResponse

router = APIRouter()

HUB_URL = os.getenv("HUB_URL", "${HUB_URL}")
REALM = os.getenv("REALM", "${REALM}")
CLIENT_ID = os.getenv("CLIENT_ID", "${CLIENT_ID}")
REDIRECT_URI = os.getenv("REDIRECT_URI", "${REDIRECT_URI}")
POST_LOGOUT_REDIRECT_URI = os.getenv(
    "POST_LOGOUT_REDIRECT_URI", "${POST_LOGOUT_REDIRECT_URI}"
)


@router.post("/api/auth/login")
def login_start():
    qs = urlencode({
        "client_id": CLIENT_ID,
        "realm": REALM,
        "redirect_uri": REDIRECT_URI,
        "response_mode": "query",
    })
    return {"loginUrl": f"{HUB_URL}/api/v1/auth/login?{qs}"}


@router.get("/api/auth/callback")
async def callback(code: str):
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{HUB_URL}/api/v1/auth/exchange",
            json={"code": code},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)
    tokens = resp.json()

    redirect = RedirectResponse("/")
    redirect.set_cookie(
        "access_token", tokens["access_token"],
        httponly=True, secure=True, samesite="lax",
        max_age=tokens["expires_in"],
    )
    if tokens.get("id_token"):
        redirect.set_cookie(
            "id_token", tokens["id_token"],
            httponly=True, secure=True, samesite="lax",
            max_age=tokens["expires_in"],
        )
    return redirect


@router.post("/api/auth/refresh")
async def refresh(response: Response, access_token: str | None = None):
    if not access_token:
        raise HTTPException(status_code=401, detail="no_session")
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{HUB_URL}/api/v1/auth/refresh",
            json={"access_token": access_token},
        )
    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail="refresh_failed")
    data = resp.json()
    response.set_cookie(
        "access_token", data["access_token"],
        httponly=True, secure=True, samesite="lax",
    )
    return {"ok": True}


@router.post("/api/auth/logout")
async def logout(access_token: str | None = None):
    if access_token:
        async with httpx.AsyncClient() as client:
            try:
                await client.post(
                    f"{HUB_URL}/api/v1/auth/logout",
                    json={"access_token": access_token},
                    headers={"Authorization": f"Bearer {access_token}"},
                )
            except httpx.HTTPError:
                pass

    kc_logout = (
        f"{HUB_URL}/realms/{REALM}/protocol/openid-connect/logout"
        f"?client_id={CLIENT_ID}"
        f"&post_logout_redirect_uri={POST_LOGOUT_REDIRECT_URI}"
    )
    return {"ok": True, "logoutUrl": kc_logout}
