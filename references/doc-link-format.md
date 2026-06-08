# 참고 — 문서 링크 표기 규칙

> CLAUDE.md 본문에서 분리. 표 + 검증 명령은 디테일이라 본문 가독성 해침. 룰 자체는 단순.

## 규칙

| 위치 | 표기 |
|------|------|
| **Obsidian Vault 내부** (`~/Workspace/weaversbrain/weaversbrain/` 하위) | **두 링크 모두 병기** — ① `obsidian://open?vault=weaversbrain&file={vault_root_기준_경로(확장자 제외, URL 인코딩)}` ② `antigravity-ide://file/{절대경로}` (또는 `open -a "Antigravity IDE" {절대경로}`) |
| **Vault 외부 일반 파일** (코드/프로젝트/.claude/ 등) | **Antigravity IDE 링크만** — `antigravity-ide://file/{절대경로}` (URL 미지원 환경이면 `open -a "Antigravity IDE" {절대경로}`) |

## 주의

- Obsidian 링크는 vault 외부 파일에는 동작하지 않음 → 외부 파일에 `obsidian://` 절대 쓰지 말 것
- Antigravity IDE URL 스킴: `antigravity-ide://` (앱 번들 `com.google.antigravity-ide`, `/Applications/Antigravity IDE.app`)
- 구버전 `Antigravity.app` (`com.google.antigravity`) 가 등록한 `antigravity://` 와 다름
- 사용자 환경의 IDE 본체는 `antigravity-ide://` 임
- 환경별로 동작 다를 수 있어 `open -a "Antigravity IDE"` 폴백 함께 안내

## 검증 명령

```bash
/usr/bin/plutil -p "/Applications/Antigravity IDE.app/Contents/Info.plist" | grep -A 5 CFBundleURLSchemes
```
