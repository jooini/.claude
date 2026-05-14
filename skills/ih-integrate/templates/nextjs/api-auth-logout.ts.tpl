// src/app/api/auth/logout/route.ts
// 두 단계: (1) Hub에 로그아웃 알림, (2) 브라우저를 Keycloak logout URL로 이동시켜 KC 세션 쿠키도 정리.
import { NextRequest, NextResponse } from "next/server"

const HUB_URL = process.env.HUB_URL ?? "${HUB_URL}"
const REALM = process.env.REALM ?? "${REALM}"
const CLIENT_ID = process.env.CLIENT_ID ?? "${CLIENT_ID}"
const POST_LOGOUT_URI = process.env.POST_LOGOUT_REDIRECT_URI ?? "${POST_LOGOUT_REDIRECT_URI}"

export async function POST(req: NextRequest) {
    const accessToken = req.cookies.get("access_token")?.value
    if (accessToken) {
        await fetch(`${HUB_URL}/api/v1/auth/logout`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${accessToken}`,
            },
            body: JSON.stringify({ access_token: accessToken }),
        }).catch(() => { /* best-effort */ })
    }

    const kcLogoutUrl =
        `${HUB_URL}/realms/${REALM}/protocol/openid-connect/logout` +
        `?client_id=${CLIENT_ID}` +
        `&post_logout_redirect_uri=${encodeURIComponent(POST_LOGOUT_URI)}`

    const res = NextResponse.json({ ok: true, logoutUrl: kcLogoutUrl })
    res.cookies.delete("access_token")
    res.cookies.delete("id_token")
    return res
}
