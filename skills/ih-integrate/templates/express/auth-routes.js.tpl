// routes/auth.js
// Hub BFF 경유 로그인/콜백/리프레시/로그아웃.
// requirements: express cookie-parser (Node 18+ 면 fetch 내장)
// SECURITY: never log or return token raw values. 토큰은 httpOnly 쿠키/Authorization 헤더로만 오가고
// 로그·에러 응답·리다이렉트 쿼리에 싣지 않는다. Hub 에러 본문은 일반화된 메시지로만 전달한다.
const express = require("express")
const router = express.Router()

const HUB_URL = process.env.${ENV_PREFIX}URL || "${HUB_URL}"
const REALM = process.env.${ENV_PREFIX}REALM || "${REALM}"
const CLIENT_ID = process.env.${ENV_PREFIX}CLIENT_ID || "${CLIENT_ID}"
const REDIRECT_URI = process.env.${ENV_PREFIX}REDIRECT_URI || "${REDIRECT_URI}"
const POST_LOGOUT_REDIRECT_URI =
    process.env.${ENV_PREFIX}POST_LOGOUT_REDIRECT_URI || "${POST_LOGOUT_REDIRECT_URI}"

// SECURITY (open-redirect 방어): return_to/redirect 파라미터는 same-origin 상대 경로만 허용.
// new URL(x, origin) 기반 origin 비교는 브라우저 URL 정규화(백슬래시→슬래시, protocol-relative,
// 선행 공백/제어문자)로 우회되므로 쓰지 않는다. 절대 URL은 허용하지 않는다.
function safeReturnPath(raw) {
    if (!raw || typeof raw !== "string") return "/"
    let v = raw.trim()
    for (let i = 0; i < 5; i++) {
        let decoded
        try {
            decoded = decodeURIComponent(v)
        } catch {
            return "/"
        }
        if (decoded === v) break
        v = decoded
    }
    // 제어문자(\x00-\x1F) 포함 시 거부
    if (/[\x00-\x1F]/.test(v)) return "/"
    // 백슬래시를 슬래시로 정규화
    v = v.replace(/\\/g, "/")
    // 스킴 형태(https:evil.com 등) 거부
    if (v.includes(":")) return "/"
    // 단일 '/'로 시작하고 두 번째 문자가 '/'가 아닐 때만 허용 (//, /\ 류 protocol-relative 거부)
    if (v.length >= 1 && v[0] === "/" && v[1] !== "/") return v
    return "/"
}

router.post("/api/auth/login", (_req, res) => {
    const params = new URLSearchParams({
        client_id: CLIENT_ID,
        realm: REALM,
        redirect_uri: REDIRECT_URI,
        response_mode: "query",
    })
    res.json({ loginUrl: `${HUB_URL}/api/v1/auth/login?${params}` })
})

router.get("/api/auth/callback", async (req, res) => {
    const code = req.query.code
    if (!code) return res.redirect("/login?error=no_code")

    const returnTo = safeReturnPath(req.query.return_to || req.query.redirect)

    const resp = await fetch(`${HUB_URL}/api/v1/auth/exchange`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code }),
    })
    // SECURITY: Hub 응답 본문을 그대로 전달하지 않고 일반화된 에러로만 리다이렉트
    if (!resp.ok) return res.redirect("/login?error=exchange_failed")
    const { access_token, id_token, expires_in } = await resp.json()

    res.cookie("access_token", access_token, {
        httpOnly: true, secure: true, sameSite: "lax", maxAge: expires_in * 1000,
    })
    if (id_token) {
        res.cookie("id_token", id_token, {
            httpOnly: true, secure: true, sameSite: "lax", maxAge: expires_in * 1000,
        })
    }
    res.redirect(returnTo)
})

router.post("/api/auth/refresh", async (req, res) => {
    const accessToken = req.cookies?.access_token
    if (!accessToken) return res.status(401).json({ error: "no_session" })

    const resp = await fetch(`${HUB_URL}/api/v1/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ access_token: accessToken }),
    })
    // SECURITY: Hub 상태/본문을 그대로 노출하지 않고 일반화된 에러로만 응답
    if (!resp.ok) return res.status(401).json({ error: "refresh_failed" })
    const { access_token } = await resp.json()
    res.cookie("access_token", access_token, {
        httpOnly: true, secure: true, sameSite: "lax",
    })
    res.json({ ok: true })
})

router.post("/api/auth/logout", async (req, res) => {
    const accessToken = req.cookies?.access_token
    if (accessToken) {
        try {
            await fetch(`${HUB_URL}/api/v1/auth/logout`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    Authorization: `Bearer ${accessToken}`,
                },
                body: JSON.stringify({ access_token: accessToken }),
            })
        } catch { /* best-effort, raw 에러 비노출 */ }
    }
    const kcLogoutUrl =
        `${HUB_URL}/realms/${REALM}/protocol/openid-connect/logout` +
        `?client_id=${CLIENT_ID}` +
        `&post_logout_redirect_uri=${encodeURIComponent(POST_LOGOUT_REDIRECT_URI)}`
    res.clearCookie("access_token")
    res.clearCookie("id_token")
    res.json({ ok: true, logoutUrl: kcLogoutUrl })
})

module.exports = router
