// ${APP_DIR}/api/auth/callback/route.ts
// Hub에서 로그인을 마친 사용자가 code를 들고 돌아옴 → Hub exchange 호출 → access_token httpOnly 쿠키 저장.
// refresh_token은 Hub 내부 Redis 세션에만 보관되고 서비스에는 내려오지 않는다.
// SECURITY: never log or return token raw values. access_token/id_token은 로그·에러 응답·리다이렉트 쿼리 어디에도 출력하지 않는다.
import { NextRequest, NextResponse } from "next/server"

const HUB_URL = process.env.${ENV_PREFIX}URL ?? "${HUB_URL}"

// SECURITY (open-redirect 방어): return_to/redirect 파라미터는 same-origin 상대 경로만 허용한다.
// new URL(x, origin) 기반 origin 비교는 브라우저 URL 정규화(백슬래시→슬래시, protocol-relative,
// 선행 공백/제어문자)로 우회되므로 쓰지 않는다. 절대 URL은 허용하지 않는다.
function safeReturnPath(raw: string | null): string {
    if (!raw) return "/"
    let v = raw.trim()
    // 이중 인코딩 방어: 더 이상 바뀌지 않을 때까지 디코딩
    for (let i = 0; i < 5; i++) {
        let decoded: string
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
    // 백슬래시를 슬래시로 정규화 (브라우저가 \를 /로 해석하는 것에 선제 대응)
    v = v.replace(/\\/g, "/")
    // 스킴 형태(https:evil.com 등) 거부
    if (v.includes(":")) return "/"
    // 단일 '/'로 시작하고 두 번째 문자가 '/'가 아닐 때만 허용 (//, /\ 류 protocol-relative 거부)
    if (v.length >= 1 && v[0] === "/" && v[1] !== "/") return v
    return "/"
}

export async function GET(req: NextRequest) {
    const code = req.nextUrl.searchParams.get("code")
    if (!code) {
        return NextResponse.redirect(new URL("/login?error=no_code", req.url))
    }

    const returnTo = safeReturnPath(
        req.nextUrl.searchParams.get("return_to") ?? req.nextUrl.searchParams.get("redirect"),
    )

    const resp = await fetch(`${HUB_URL}/api/v1/auth/exchange`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code }),
    })
    if (!resp.ok) {
        // SECURITY: Hub 응답 본문을 그대로 전달하지 않고 일반화된 에러로만 리다이렉트
        return NextResponse.redirect(new URL("/login?error=exchange_failed", req.url))
    }
    const { access_token, id_token, expires_in } = await resp.json()

    const res = NextResponse.redirect(new URL(returnTo, req.url))
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
