# dev-data-collector — sources

수집 대상 정의.

## 1. Git 레포

- 루트: `~/Workspace/`
- 탐색 규칙: `~/Workspace/*/.git` 존재하는 디렉토리 모두
- 스코프 필터: fnmatch 패턴 (콤마 구분)
  - 예: `--scope "identity-hub*,sso-*"`
  - 미지정 시 전체

## 2. 프로젝트 그룹 분류

Python 스크립트의 `PROJECT_GROUPS`에서 관리:

| 그룹 | 패턴 |
|---|---|
| identity-hub | `identity-hub*` |
| identity-keycloak | `identity-keycloak*`, `keycloak-*`, `apple-identity-provider-keycloak` |
| maxai | `maxai*` |
| sso | `sso-*`, `sso_*` |
| speakingmax | `speakingmax*`, `speech-*` |
| weaversbrain-infra | `weaversbrain*`, `terracore-infra`, `*-infra*`, `*-docker` |
| b2c | `b2c-*`, `*-b2c-*` |
| tools-and-scripts | `tools`, `scripts`, `*-sdk*`, `sso-log-viewer`, `sso-trace-visualizer`, `sso-fallback-monitor` |
| other | 위 어디에도 속하지 않는 나머지 |

규칙: **위에서 아래로 먼저 매칭되는 그룹 사용**. 새 레포 타입이 생기면 여기와 스크립트 양쪽 수정.

## 3. 저자 필터

- 기본: `git config --global user.email`
- 오버라이드: `--email` 옵션
- 주의: 회사 이메일과 개인 이메일 둘 다 쓰면 분기마다 확인 필요. 필요하면 `--email A --email B` 확장 (현재 단일만 지원)

## 4. Obsidian Vault

- 루트: `~/Workspace/weaversbrain/weaversbrain/`
- Daily: `Daily/YYYY-MM/YYYY-MM-DD*.md` (weekly 보고서 포함)
- 범위 필터: 파일명 앞 10글자(`YYYY-MM-DD`) 파싱

## 5. GitHub

- `gh` CLI 필요 (없으면 스킵)
- `gh api user` 로 로그인 확인
- 쿼리:
  - PR opened: `author:{login} is:pr created:{since}..{until}`
  - PR merged: `author:{login} is:pr is:merged merged:{since}..{until}`
  - PR reviewed-by: `reviewed-by:{login} is:pr created:{since}..{until}`
  - Issues opened: `author:{login} is:issue created:{since}..{until}`

## 6. Jira / Confluence (미구현)

- MCP 연동이나 API 토큰 붙일 때 확장 예정
- 현재 버전에서는 수집하지 않음
