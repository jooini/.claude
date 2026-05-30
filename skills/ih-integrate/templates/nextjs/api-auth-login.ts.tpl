// ${APP_DIR}/api/auth/login/route.ts
// 사용자를 Identity Hub 인증 시작점으로 보낸다. state/PKCE/nonce는 Hub가 생성·관리한다.
// SECURITY: never log or return token raw values. 이 라우트는 토큰을 다루지 않는다.
import { NextResponse } from "next/server"

const HUB_URL = process.env.${ENV_PREFIX}URL ?? "${HUB_URL}"
const REALM = process.env.${ENV_PREFIX}REALM ?? "${REALM}"
const CLIENT_ID = process.env.${ENV_PREFIX}CLIENT_ID ?? "${CLIENT_ID}"
const REDIRECT_URI = process.env.${ENV_PREFIX}REDIRECT_URI ?? "${REDIRECT_URI}"

export async function GET() {
    const params = new URLSearchParams({
        client_id: CLIENT_ID,
        redirect_uri: REDIRECT_URI,
        response_type: "code",
        scope: "openid profile email",
    })
    const authUrl = `${HUB_URL}/api/v1/auth/login/${REALM}?${params.toString()}`
    return NextResponse.redirect(authUrl)
}
