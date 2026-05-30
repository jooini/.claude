// ${MIDDLEWARE_PATH}
// 로그인이 필요한 경로 보호. PUBLIC_PATHS는 프로젝트에 맞춰 조정.
// NOTE: 이 thin-client는 Hub가 return_to를 왕복시키지 않으므로(flow-overview 참조) 로그인 후
// 기본 경로(/)로 복원한다. 딥링크 복원이 필요하면 /login 페이지에서 현재 경로를 쿠키/스토리지에
// 저장했다가 로그인 완료 후 클라이언트에서 이동하라 — middleware가 ?redirect= 쿼리를 심지 않는다
// (login 라우트가 그 값을 소비하지 않아 조용히 누락되던 혼선을 제거).
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
        loginUrl.search = ""
        return NextResponse.redirect(loginUrl)
    }
    return NextResponse.next()
}

export const config = {
    matcher: [
        "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
    ],
}
