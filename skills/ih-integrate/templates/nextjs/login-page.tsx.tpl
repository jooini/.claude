// ${APP_DIR}/login/page.tsx
// Identity Hub thin-client 로그인 화면.
// 미인증 사용자가 보호 경로에 접근하면 middleware가 여기로 보낸다(?return_to=원래경로).
// 로그인 버튼은 /api/auth/login?return_to=... 로 이동 → 라우트가 Hub로 302.
// SECURITY: 이 페이지는 토큰을 다루지 않는다. return_to 검증은 login 라우트(sanitizeReturnTo)가 한다.

"use client";

import { useEffect, useState } from "react";

export default function LoginPage() {
    const [returnTo, setReturnTo] = useState("/");

    useEffect(() => {
        const p = new URLSearchParams(window.location.search).get("return_to");
        // 상대경로(/...)만 허용 — 절대 URL/protocol-relative 거부 (login 라우트가 재검증).
        if (p && p.startsWith("/") && !p.startsWith("//") && !p.startsWith("/\\")) {
            setReturnTo(p);
        }
    }, []);

    const loginHref = `/api/auth/login?return_to=${encodeURIComponent(returnTo)}`;

    return (
        <main className="flex min-h-screen items-center justify-center bg-background px-6">
            <div className="w-full max-w-sm rounded-xl border bg-card p-8 text-center shadow-sm">
                <h1 className="text-lg font-semibold tracking-tight">${CLIENT_ID}</h1>
                <p className="mt-2 text-sm text-muted-foreground">
                    계속하려면 Identity Hub 로그인이 필요합니다.
                </p>
                <a
                    href={loginHref}
                    className="mt-6 inline-flex w-full items-center justify-center rounded-md bg-primary px-4 py-2.5 text-sm font-medium text-primary-foreground hover:bg-primary/90"
                >
                    Identity Hub 로 로그인
                </a>
            </div>
        </main>
    );
}
