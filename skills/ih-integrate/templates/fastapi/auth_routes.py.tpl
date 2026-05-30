# app/routes/auth.py
# Hub BFF 경유 로그인/콜백/리프레시/로그아웃.
# client_secret 보관/전송 없음. state/PKCE는 Hub가 관리.
# requirements: fastapi httpx
# SECURITY: never log or return token raw values. 토큰은 httpOnly 쿠키로만 오가고 응답 본문/로그에 싣지 않는다.
# Hub 에러 본문은 그대로 전달하지 않고 일반화된 메시지로만 응답한다.
import os
import re
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import RedirectResponse

router = APIRouter()

HUB_URL = os.getenv("${ENV_PREFIX}URL", "${HUB_URL}")
REALM = os.getenv("${ENV_PREFIX}REALM", "${REALM}")
CLIENT_ID = os.getenv("${ENV_PREFIX}CLIENT_ID", "${CLIENT_ID}")
REDIRECT_URI = os.getenv("${ENV_PREFIX}REDIRECT_URI", "${REDIRECT_URI}")
POST_LOGOUT_REDIRECT_URI = os.getenv(
    "${ENV_PREFIX}POST_LOGOUT_REDIRECT_URI", "${POST_LOGOUT_REDIRECT_URI}"
)

_CONTROL_CHARS = re.compile(r"[\x00-\x1F]")


def safe_return_path(raw: str | None) -> str:
    # SECURITY (open-redirect 방어): same-origin 상대 경로만 허용. 절대 URL/스킴/protocol-relative 거부.
    # urlparse 기반 netloc 비교는 정규화 우회가 있어 쓰지 않고, 허용 리스트(상대경로)+정규화로 처리.
    if not raw:
        return "/"
    from urllib.parse import unquote

    v = raw.strip()
    for _ in range(5):
        decoded = unquote(v)
        if decoded == v:
            break
        v = decoded
    if _CONTROL_CHARS.search(v):
        return "/"
    v = v.replace("\\", "/")
    if ":" in v:
        return "/"
    if len(v) >= 1 and v[0] == "/" and (len(v) < 2 or v[1] != "/"):
        return v
    return "/"


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
async def callback(code: str, return_to: str | None = None, redirect: str | None = None):
    target = safe_return_path(return_to or redirect)
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{HUB_URL}/api/v1/auth/exchange",
            json={"code": code},
        )
    if resp.status_code != 200:
        # SECURITY: Hub 응답 본문(resp.text)을 그대로 전달하지 않고 일반화된 에러로만 응답
        raise HTTPException(status_code=401, detail="exchange_failed")
    tokens = resp.json()

    response = RedirectResponse(target)
    response.set_cookie(
        "access_token", tokens["access_token"],
        httponly=True, secure=True, samesite="lax",
        max_age=tokens["expires_in"],
    )
    if tokens.get("id_token"):
        response.set_cookie(
            "id_token", tokens["id_token"],
            httponly=True, secure=True, samesite="lax",
            max_age=tokens["expires_in"],
        )
    return response


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
        # SECURITY: Hub 상태/본문을 그대로 노출하지 않고 일반화된 에러로만 응답
        raise HTTPException(status_code=401, detail="refresh_failed")
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
                pass  # best-effort, raw 에러 비노출

    kc_logout = (
        f"{HUB_URL}/realms/{REALM}/protocol/openid-connect/logout"
        f"?client_id={CLIENT_ID}"
        f"&post_logout_redirect_uri={POST_LOGOUT_REDIRECT_URI}"
    )
    return {"ok": True, "logoutUrl": kc_logout}
