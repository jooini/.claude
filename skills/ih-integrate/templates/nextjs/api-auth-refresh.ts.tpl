// ${APP_DIR}/api/auth/refresh/route.ts
// Access Token 만료 임박 시 호출. Hub /auth/refresh는 새 access_token만 반환 (expires_in 없음).
// 만료 시각은 JWT exp 클레임을 직접 파싱해서 계산.
// SECURITY: never log or return token raw values. 토큰은 httpOnly 쿠키로만 오가고 응답 본문/로그에 싣지 않는다.
import { NextRequest, NextResponse } from "next/server"

const HUB_URL = process.env.${ENV_PREFIX}URL ?? "${HUB_URL}"

function parseJwtExp(token: string): number | null {
    try {
        const payload = token.split(".")[1]
        const padded = payload + "=".repeat((4 - (payload.length % 4)) % 4)
        const json = JSON.parse(Buffer.from(padded, "base64").toString("utf-8"))
        return typeof json.exp === "number" ? json.exp : null
    } catch {
        return null
    }
}

export async function POST(req: NextRequest) {
    const accessToken = req.cookies.get("access_token")?.value
    if (!accessToken) {
        return NextResponse.json({ error: "no_session" }, { status: 401 })
    }

    const resp = await fetch(`${HUB_URL}/api/v1/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ access_token: accessToken }),
    })
    if (!resp.ok) {
        // SECURITY: Hub 응답 본문/상태를 그대로 전달하지 않고 일반화된 에러로만 응답
        return NextResponse.json({ error: "refresh_failed" }, { status: 401 })
    }
    const { access_token } = await resp.json()
    const exp = parseJwtExp(access_token)
    const maxAge = exp ? Math.max(0, exp - Math.floor(Date.now() / 1000)) : 300

    const res = NextResponse.json({ ok: true })
    res.cookies.set("access_token", access_token, {
        httpOnly: true, secure: true, sameSite: "lax", maxAge,
    })
    return res
}
