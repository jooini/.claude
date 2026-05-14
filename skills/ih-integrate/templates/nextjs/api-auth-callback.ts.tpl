// src/app/api/auth/callback/route.ts
// Hub에서 로그인을 마친 사용자가 code를 들고 돌아옴 → Hub exchange 호출 → access_token httpOnly 쿠키 저장.
// refresh_token은 Hub 내부 Redis 세션에만 보관되고 서비스에는 내려오지 않는다.
import { NextRequest, NextResponse } from "next/server"

const HUB_URL = process.env.HUB_URL ?? "${HUB_URL}"

export async function GET(req: NextRequest) {
    const code = req.nextUrl.searchParams.get("code")
    if (!code) {
        return NextResponse.redirect(new URL("/login?error=no_code", req.url))
    }

    const resp = await fetch(`${HUB_URL}/api/v1/auth/exchange`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code }),
    })
    if (!resp.ok) {
        return NextResponse.redirect(new URL("/login?error=exchange_failed", req.url))
    }
    const { access_token, id_token, expires_in } = await resp.json()

    const res = NextResponse.redirect(new URL("/", req.url))
    res.cookies.set("access_token", access_token, {
        httpOnly: true, secure: true, sameSite: "lax", maxAge: expires_in,
    })
    if (id_token) {
        res.cookies.set("id_token", id_token, {
            httpOnly: true, secure: true, sameSite: "lax", maxAge: expires_in,
        })
    }
    return res
}
