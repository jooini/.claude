// middleware/verify-jwt.js
// JWT 검증 미들웨어. JWKS는 jose의 createRemoteJWKSet으로 캐시 자동 관리.
// requirements: jose
const { jwtVerify, createRemoteJWKSet } = require("jose")

const HUB_URL = process.env.HUB_URL || "${HUB_URL}"
const REALM = process.env.REALM || "${REALM}"
const CLIENT_ID = process.env.CLIENT_ID || "${CLIENT_ID}"
const ISSUER = `${HUB_URL}/realms/${REALM}`
const JWKS = createRemoteJWKSet(new URL(`${HUB_URL}/api/v1/auth/jwks/${REALM}`))

async function verifyJwt(req, res, next) {
    const auth = req.headers.authorization || ""
    if (!auth.startsWith("Bearer ")) {
        return res.status(401).json({ error: "missing bearer token" })
    }
    const token = auth.slice("Bearer ".length).trim()
    try {
        const { payload } = await jwtVerify(token, JWKS, {
            issuer: ISSUER,
            audience: CLIENT_ID,
        })
        req.user = payload
        next()
    } catch (e) {
        res.status(401).json({ error: `invalid token: ${e.message}` })
    }
}

module.exports = { verifyJwt }
