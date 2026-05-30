// middleware/verify-jwt.js
// JWT 검증 미들웨어. JWKS는 jose의 createRemoteJWKSet으로 캐시 자동 관리.
// requirements: jose
// SECURITY: never log or return token raw values. 검증 실패 시 내부 예외 메시지를 클라이언트에 노출하지 않고
// 일반화된 메시지로만 응답한다(상세는 서버 로그에만, 토큰 제외).
const { jwtVerify, createRemoteJWKSet } = require("jose")

const HUB_URL = process.env.${ENV_PREFIX}URL || "${HUB_URL}"
const REALM = process.env.${ENV_PREFIX}REALM || "${REALM}"
const CLIENT_ID = process.env.${ENV_PREFIX}CLIENT_ID || "${CLIENT_ID}"
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
        // SECURITY: e.message(검증 내부 사유)를 응답에 싣지 않는다. 서버 로그에만 남긴다(토큰 제외).
        console.warn("[auth] jwt verification failed:", e.message)
        res.status(401).json({ error: "invalid token" })
    }
}

module.exports = { verifyJwt }
