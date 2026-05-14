// lib/hub-service-token.js
// M2M 토큰 매니저. 만료 30초 전까지 캐시 재사용.
const HUB_URL = process.env.HUB_URL || "${HUB_URL}"
const REALM = process.env.REALM || "${REALM}"
const CLIENT_ID = process.env.CLIENT_ID || "${CLIENT_ID}"

let cached = null

async function getServiceToken() {
    const now = Date.now()
    if (cached && now < cached.expiresAt - 30_000) return cached.token

    const resp = await fetch(`${HUB_URL}/api/v1/auth/service-token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ client_id: CLIENT_ID, realm: REALM }),
    })
    if (!resp.ok) throw new Error(`service-token failed: ${resp.status}`)
    const { access_token, expires_in } = await resp.json()
    cached = { token: access_token, expiresAt: now + expires_in * 1000 }
    return access_token
}

module.exports = { getServiceToken }
