// ${MIDDLEWARE_PATH}
// 로그인이 필요한 경로 보호 + (있으면) 기존 x-request-id 등 부가 로직 유지.
//
// 쿠키 이름(${SESSION_COOKIE})은 callback 라우트가 발급하는 세션 쿠키와 정확히 일치해야 한다.
// 불일치 시 인증된 사용자도 무한히 /login 으로 튕긴다 — 설치 시 반드시 확인할 것.
//
// 미인증 시 /login?return_to=<원래 경로> 로 보낸다. /login 페이지의 로그인 버튼이
// 이 return_to 를 /api/auth/login 으로 넘기고, callback 이 로그인 후 그 경로로 복원한다.
//
// MERGE NOTE: 대상 프로젝트에 이미 middleware.ts 가 있으면 이 파일로 덮어쓰지 말 것.
//   기존 미들웨어의 로직(예: x-request-id 주입)을 보존하면서, 아래 "인증 가드" 블록과
//   PUBLIC_PATHS / matcher 만 합쳐 넣는다.
import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

const PUBLIC_PATHS = ["/login", "/api/auth", "/api/healthz", "/api/readyz"]
const SESSION_COOKIE = "${SESSION_COOKIE}"

export function middleware(request: NextRequest) {
    const { pathname } = request.nextUrl

    // (기존 부가 로직이 있으면 여기서 함께 수행 — 예: x-request-id 주입)

    const isPublic = PUBLIC_PATHS.some(
        (p) => pathname === p || pathname.startsWith(`${p}/`),
    )
    if (isPublic) return NextResponse.next()

    // 인증 가드: 세션 쿠키 없으면 /login?return_to=원래경로 로 리다이렉트.
    const hasSession = Boolean(request.cookies.get(SESSION_COOKIE)?.value)
    if (!hasSession) {
        const loginUrl = request.nextUrl.clone()
        loginUrl.pathname = "/login"
        loginUrl.search = ""
        loginUrl.searchParams.set("return_to", pathname + request.nextUrl.search)
        return NextResponse.redirect(loginUrl)
    }

    return NextResponse.next()
}

export const config = {
    matcher: [
        // 정적 자산/이미지 제외, 나머지 전부 가드. /api/* 도 포함(보호 API는 401, 화면은 /login).
        "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
    ],
}
