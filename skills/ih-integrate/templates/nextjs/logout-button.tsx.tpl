// ${COMPONENTS_DIR}/LogoutButton.tsx
// 로그아웃 버튼 — POST /api/auth/logout (라우트가 Hub logout + 쿠키 clear + KC end_session 302).
// form POST 방식: JS 없이도 동작하고, 라우트의 302 redirect를 브라우저가 그대로 따라간다.
// 전역 네비(헤더/사이드바)에 배치한다.

export function LogoutButton() {
    return (
        <form action="/api/auth/logout" method="post" className="inline">
            <button
                type="submit"
                className="inline-flex items-center gap-1 rounded-md px-2.5 py-1.5 text-xs font-medium text-foreground/70 hover:bg-accent hover:text-foreground"
            >
                로그아웃
            </button>
        </form>
    );
}
