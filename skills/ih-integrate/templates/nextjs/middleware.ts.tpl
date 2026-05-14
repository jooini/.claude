// src/middleware.ts
// 로그인이 필요한 경로 보호. PUBLIC_PATHS는 프로젝트에 맞춰 조정.
import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

const PUBLIC_PATHS = ["/login", "/callback", "/api/auth", "/api/health"]

export function middleware(request: NextRequest) {
    const pathname = request.nextUrl.pathname
    const isPublic = PUBLIC_PATHS.some(
        (path) => pathname === path || pathname.startsWith(`${path}/`),
    )
    if (isPublic) return NextResponse.next()

    const token = request.cookies.get("access_token")
    if (!token) {
        const loginUrl = request.nextUrl.clone()
        loginUrl.pathname = "/login"
        loginUrl.searchParams.set("redirect", pathname)
        return NextResponse.redirect(loginUrl)
    }
    return NextResponse.next()
}

export const config = {
    matcher: [
        "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
    ],
}
