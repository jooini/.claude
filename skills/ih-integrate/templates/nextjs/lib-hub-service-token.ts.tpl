// ${LIB_DIR}/hub-service-token.ts
// 서비스 간 통신용 M2M 토큰 매니저. 만료 30초 전까지 캐시 재사용.
// client_secret은 Hub가 자기 DB에서 꺼내 Keycloak에 대신 붙여 보낸다. 서비스는 client_id만 제시.
// SECURITY: never log or return token raw values. 발급된 토큰은 호출자에게만 반환되고 로그에 남기지 않는다.
const HUB_URL = process.env.${ENV_PREFIX}URL ?? "${HUB_URL}"
const REALM = process.env.${ENV_PREFIX}REALM ?? "${REALM}"
const CLIENT_ID = process.env.${ENV_PREFIX}CLIENT_ID ?? "${CLIENT_ID}"

let cached: { token: string; expiresAt: number } | null = null

export async function getServiceToken(): Promise<string> {
    const now = Date.now()
    if (cached && now < cached.expiresAt - 30_000) return cached.token

    const resp = await fetch(`${HUB_URL}/api/v1/auth/service-token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ client_id: CLIENT_ID, realm: REALM }),
    })
    // SECURITY: 상태 코드만 노출, Hub 응답 본문(토큰 포함 가능)은 메시지에 싣지 않는다
    if (!resp.ok) throw new Error(`service-token failed: ${resp.status}`)
    const { access_token, expires_in } = await resp.json()
    cached = { token: access_token, expiresAt: now + expires_in * 1000 }
    return access_token
}
