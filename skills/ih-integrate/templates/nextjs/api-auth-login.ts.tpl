// src/app/api/auth/login/route.ts
// Hub login URL을 만들어 프론트에 돌려준다. state/PKCE/nonce는 Hub가 Redis로 관리.
import { NextResponse } from "next/server"

const HUB_URL = process.env.HUB_URL ?? "${HUB_URL}"
const REALM = process.env.REALM ?? "${REALM}"
const CLIENT_ID = process.env.CLIENT_ID ?? "${CLIENT_ID}"
const REDIRECT_URI = process.env.REDIRECT_URI ?? "${REDIRECT_URI}"

export async function POST() {
    const params = new URLSearchParams({
        client_id: CLIENT_ID,
        realm: REALM,
        redirect_uri: REDIRECT_URI,
        response_mode: "query",
    })
    return NextResponse.json({
        loginUrl: `${HUB_URL}/api/v1/auth/login?${params}`,
    })
}
