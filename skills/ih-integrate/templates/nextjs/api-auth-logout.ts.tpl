// ${APP_DIR}/api/auth/logout/route.ts
// 두 단계: (1) Hub에 로그아웃 알림, (2) 브라우저를 Keycloak logout URL로 이동시켜 KC 세션 쿠키도 정리.
// SECURITY: never log or return token raw values. access_token은 Authorization 헤더로만 쓰고 응답·로그에 싣지 않는다.
import { NextRequest, NextResponse } from "next/server"

const HUB_URL = process.env.${ENV_PREFIX}URL ?? "${HUB_URL}"
const REALM = process.env.${ENV_PREFIX}REALM ?? "${REALM}"
const CLIENT_ID = process.env.${ENV_PREFIX}CLIENT_ID ?? "${CLIENT_ID}"
const POST_LOGOUT_URI = process.env.${ENV_PREFIX}POST_LOGOUT_REDIRECT_URI ?? "${POST_LOGOUT_REDIRECT_URI}"

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
        }).catch(() => { /* best-effort, 실패해도 raw 에러를 노출하지 않는다 */ })
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
