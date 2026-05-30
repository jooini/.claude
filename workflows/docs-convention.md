# 문서 작성 규칙

> CLAUDE.md에서 `@~/.claude/workflows/docs-convention.md` 로 참조됨.

## Obsidian Vault 경로

Base: `~/Workspace/weaversbrain/weaversbrain/`

| 용도 | 경로 패턴 |
|------|----------|
| 일일 보고서 | `Daily/YYYY-MM/YYYY-MM-DD.md` |
| 세션 히스토리 | `Sessions/YYYY-MM/YYYY-MM-DD-{project}.md` |
| 프로젝트 문서 | `Projects/{project}/YYYY-MM/YYYY-MM-DD-HHMM-{파일명}.md` |
| 설계/계획 | `Plans/YYYY-MM/YYYY-MM-DD-HHMM-{파일명}.md` |
| 주간 보고서 | `Reports/YYYY-MM/YYYY-MM-DD-weekly.md` |

## 규칙

- YAML frontmatter 필수 (date, type, project 등)
- 파일명에 시분 포함: `YYYY-MM-DD-HHMM-{파일명}.md`
- Claude 컨텍스트 파일: `~/.claude/{프로젝트명}/`

## 문서 링크 표기 규칙

문서/파일 경로를 사용자에게 안내할 때:

### Obsidian Vault 내부 파일 (`~/Workspace/weaversbrain/weaversbrain/` 하위)

**반드시 두 링크 모두 병기**:

```
- Obsidian: obsidian://open?vault=weaversbrain&file={vault_root_기준_상대경로_확장자제외_URL인코딩}
- Antigravity IDE: antigravity-ide://file/{절대경로}
  (URL 미지원 시: `open -a "Antigravity IDE" {절대경로}`)
```

예시 — `~/Workspace/weaversbrain/weaversbrain/Sessions/2026-05/2026-05-24-foo.md`:
```
- Obsidian: obsidian://open?vault=weaversbrain&file=Sessions%2F2026-05%2F2026-05-24-foo
- Antigravity IDE: antigravity-ide://file//Users/leonard/Workspace/weaversbrain/weaversbrain/Sessions/2026-05/2026-05-24-foo.md
```

### Vault 외부 파일 (코드, 프로젝트, `~/.claude/`, `~/Workspace/{project}/` 등)

**Antigravity IDE 링크만 안내** (Obsidian은 vault 외부 파일 못 염):

```
antigravity-ide://file/{절대경로}
(URL 미지원 시: `open -a "Antigravity IDE" {절대경로}`)
```

### 주의

- Obsidian URI의 `file=` 값은 vault 루트 기준 상대경로, **확장자 제외**, **URL 인코딩 필수** (`/` → `%2F`, 공백 → `%20`)
- Antigravity IDE URL 스킴: `antigravity-ide://` (앱 번들 `com.google.antigravity-ide`, VSCode 포크)
  - 구버전 `Antigravity.app` (`com.google.antigravity`) 의 `antigravity://` 와 다름. 시스템에 두 앱이 공존하면 `antigravity://` 는 구버전 앱으로 라우팅되어 안 열림. IDE 본체는 항상 `antigravity-ide://`
  - 실측 검증: `/usr/bin/plutil -p "/Applications/Antigravity IDE.app/Contents/Info.plist" | grep -A 5 CFBundleURLSchemes`
- 두 번째 슬래시(`antigravity-ide://file//Users/...`)는 오타 아님 — `://file` + `/{절대경로}` 구조
- 마크다운 링크로 걸 때 `[텍스트](antigravity-ide://file//절대경로)` 형식 — 코드 블록은 클릭 불가, 반드시 링크 문법

## 세션 히스토리

- 현재: `Sessions/YYYY-MM/YYYY-MM-DD-{project}.md`
- 아카이브 (1/22~2/16): `Projects/misc/2026-02/2026-02-17-claude-md-session-archive.md`
- 레거시 docs (보존 중): `~/Workspace/docs/` (마이그레이션 완료, 아카이브 예정)

## 금지 단어 / 권장 대체어

문서/보고서/세션 기록/커밋 메시지/PR 설명 작성 시 다음 단어는 사용 금지. 문맥에 맞게 대체.

| 금지 | 이유 | 권장 대체어 (문맥별) |
|------|------|---------------------|
| 회귀 | 통계/머신러닝 "regression"과 충돌. 한국어 일상 의미 "되돌아감"으로도 모호 | 통계적 추세 분석 → "선형 추세 분석", "구간별 분포 분석", "데이터 추세" / 소프트웨어 regression test → "기존 동작 무회손 검증", "기존 테스트 통과", "기존 동작 영향 점검" / 성능 저하 추세 → "성능 악화", "지표 악화 추세" |

룰:
- "회귀" 단어 발견 시 즉시 정정. 이미 작성된 문서도 다음 편집 시 같이 정정
- 작성 직전 자가 점검: "이 줄에 회귀 들어가나" 확인 후 대체어로 작성
- 위반 시 사용자 정정 신호 발생 → 같은 실수 두 번 금지
