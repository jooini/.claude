// routes/auth.js
// Hub BFF 경유 로그인/콜백/리프레시/로그아웃.
// requirements: express cookie-parser (Node 18+ 면 fetch 내장)
const express = require("express")
const router = express.Router()

const HUB_URL = process.env.HUB_URL || "${HUB_URL}"
const REALM = process.env.REALM || "${REALM}"
const CLIENT_ID = process.env.CLIENT_ID || "${CLIENT_ID}"
const REDIRECT_URI = process.env.REDIRECT_URI || "${REDIRECT_URI}"
const POST_LOGOUT_REDIRECT_URI =
    process.env.POST_LOGOUT_REDIRECT_URI || "${POST_LOGOUT_REDIRECT_URI}"

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

    const resp = await fetch(`${HUB_URL}/api/v1/auth/exchange`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code }),
    })
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
    res.redirect("/")
})

router.post("/api/auth/refresh", async (req, res) => {
    const accessToken = req.cookies?.access_token
    if (!accessToken) return res.status(401).json({ error: "no_session" })

    const resp = await fetch(`${HUB_URL}/api/v1/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ access_token: accessToken }),
    })
    if (!resp.ok) return res.status(resp.status).json({ error: "refresh_failed" })
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
        } catch { /* best-effort */ }
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
